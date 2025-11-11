import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart' as a;
import 'package:dungeonclub/iterable_extension.dart';
import 'package:dungeonclub/models/token_bar.dart';
import 'package:dungeonclub/point_json.dart';
import 'package:dungeonclub/reactive/selection_system.dart';
import 'package:dungeonclub/session_util.dart';

import '../../main.dart';
import '../communication.dart';
import '../html/input_extension.dart';
import '../html/instance_list.dart';
import '../html_helpers.dart';
import '../html_transform.dart';
import '../notif.dart';
import '../panels/upload.dart' as upload;
import '../resource.dart';
import 'fog_of_war.dart';
import 'grid.dart';
import 'log.dart';
import 'initiative_tracker.dart';
import 'map.dart';
import 'measuring.dart';
import 'movable.dart';
import 'prefab.dart';
import 'prefab_palette.dart';
import 'roll_dice.dart';
import 'scene.dart';
import 'selection_conditions.dart';
import 'selection_token_bar.dart';
import 'session.dart';

final web.HTMLElement _container = queryDom('#boardContainer') as web.HTMLElement;
final web.HTMLElement _e = queryDom('#board') as web.HTMLElement;
final web.HTMLImageElement _ground = _e.queryDom('#ground') as web.HTMLImageElement;

final web.HTMLButtonElement _editScene = _container.queryDom('#editScene') as web.HTMLButtonElement;
final web.HTMLButtonElement _exitEdit = _container.queryDom('#exitEdit') as web.HTMLButtonElement;

final web.HTMLElement _controls = _container.queryDom('#sceneEditor') as web.HTMLElement;
final web.HTMLButtonElement _changeImage = _controls.queryDom('#changeImage') as web.HTMLButtonElement;


final web.HTMLElement _selectionProperties = queryDom('#selectionProperties') as web.HTMLElement;
final web.HTMLElement _selectedLabelWrapper = queryDom('#movableLabel') as web.HTMLElement;
final _selectedLabelPrefix =
    _selectedLabelWrapper.children.item(0) as web.HTMLElement;
final _selectedLabel = _selectedLabelWrapper.children.item(_selectedLabelWrapper.children.length - 1) as web.HTMLInputElement;
final web.HTMLInputElement _selectedSize = queryDom('#movableSize') as web.HTMLInputElement;
final web.HTMLInputElement _selectedAura = queryDom('#movableAura') as web.HTMLInputElement;
final web.HTMLButtonElement _addTokenBarButton = queryDom('#barAddButton') as web.HTMLButtonElement;
final web.HTMLButtonElement _selectedInvisible = queryDom('#movableInvisible') as web.HTMLButtonElement;
final web.HTMLButtonElement _selectedRemove = queryDom('#movableRemove') as web.HTMLButtonElement;
final web.HTMLButtonElement _selectedSnap = queryDom('#movableSnap') as web.HTMLButtonElement;
final web.HTMLButtonElement _selectedGoTo = queryDom('#movableGoTo') as web.HTMLButtonElement;
final web.HTMLButtonElement _selectedPing = queryDom('#movablePing') as web.HTMLButtonElement;

final web.HTMLButtonElement _fowToggle = queryDom('#fogOfWar') as web.HTMLButtonElement;
final web.HTMLButtonElement _measureToggle = queryDom('#measureDistance') as web.HTMLButtonElement;
web.HTMLElement get _measureSticky => queryDom('#measureSticky') as web.HTMLElement;
web.HTMLElement get _measureVisible => queryDom('#measureVisible') as web.HTMLElement;

class Board {
  final Session session;
  final grid = SceneGrid();
  final mapTab = MapTab();
  late final movables = InstanceList<Movable>(grid.e);
  final selected = SelectionSystem<Movable>();
  final fogOfWar = FogOfWar();
  final initiativeTracker = InitiativeTracker();
  final selectedBars =
      InstanceList<SelectionTokenBar>(queryDom('#selectionBars'));
  late SelectionConditions _selectionConditions;
  List<Movable> clipboard = [];

  static const PAN = 'pan';
  static const MEASURE = 'measure';
  static const FOG_OF_WAR = 'fow';

  final showMoveDistances = true;

  late BoardTransform _transform;
  BoardTransform get transform => _transform;

  Point get position => transform.position;
  set position(Point p) => transform.position = p;

  double get zoom => transform.zoom;
  set zoom(double zoom) => transform.zoom = zoom;

  double get scaledZoom => transform.scaledZoom;

  int get nextMovableId => movables.getNextAvailableID((e) => e.id);

  bool get editingGrid => _container.className.contains('edit');
  set editingGrid(bool v) {
    if (v) {
      if (!_container.className.contains('edit')) {
        _container.className = '${_container.className} edit'.trim();
      }
    } else {
      _container.className = _container.className.replaceAll('edit', '').replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    if (v) {
      _deselectAll();
      mode = PAN;
    } else {
      socket.sendAction(a.GAME_SCENE_UPDATE, {
        'grid': grid.toJson(),
        'movables': movables
            .map((e) => {
                  'id': e.id,
                  ...writePoint(e.position),
                })
            .toList()
      });
      rescaleMeasurings();
    }
  }

  bool get measureVisible => _measureVisible.classList.contains('active');
  set measureVisible(bool v) {
    _measureVisible
      ..className = 'fas fa-' + (v ? 'eye active' : 'eye-slash')
      ..queryDom('span').textContent = v ? 'Public' : 'Private';

    removeMeasuring(session.charId, sendEvent: true);
  }

  String _mode = '';
  String get mode => _mode;
  set mode(String mode) {
    if (mode == _mode) mode = PAN;

    if (_mode == MEASURE) {
      // Exiting measure mode
      removeMeasuring(session.charId, sendEvent: true);
    }

    _mode = mode;

    var isPan = mode == PAN;
    _container.setAttribute('mode', '$mode');
    _measureToggle.classList.toggle('active', mode == MEASURE);
    _fowToggle.classList.toggle('active', mode == FOG_OF_WAR);
    fogOfWar.canvas.captureInput = mode == FOG_OF_WAR;

    if (!isPan) {
      _deselectAll();

      if (mode == MEASURE) {
        displayTooltip(getMeasureTooltip());
      } else {
        displayTooltip(fogOfWar.tooltip);
      }
    } else {
      displayTooltip('');
    }
  }

  Movable? get activeMovable => selected.active;

  late Scene _refScene;
  Scene get refScene => _refScene;
  bool _init = false;

  Board(this.session) {
    _transform = BoardTransform(this, _e, getMaxPosition: () {
      return Point(
        _ground.naturalWidth,
        _ground.naturalHeight,
      );
    });
    position = Point(0, 0);
    _selectionConditions = SelectionConditions(this);

    if (!_init) {
      _initBoard();
      _init = true;
    }
  }

  void _onActiveMovableChange(SetActiveEvent<Movable> event) {
    final activeMovable = event.active;
    final previousActiveMovable = event.previousActive;

    if (previousActiveMovable != null) {
      // Firefox doesn't automatically blurrr inputs when their parent
      // element gets moved or removed
      _selectedLabel.blur();
      _selectedSize.blur();
      previousActiveMovable.styleActive = false;
    }

    if (activeMovable != null) {
      activeMovable.styleActive = true;

      // Assign current values to HTML inputs
      var nicknamePrefix = '';
      if (activeMovable is! EmptyMovable) {
        nicknamePrefix = activeMovable.name;
      }

      _selectedLabelPrefix.textContent = nicknamePrefix;
      _selectedLabel.value = activeMovable.label;
      _selectedAura.valueAsNumber = activeMovable.auraRadius;
      _updateSelectedInvisible(activeMovable.invisible);
      _selectedSize.valueAsNumber = activeMovable.size;
      _updateSelectionSizeInherit();

      _selectionConditions.onActiveTokenChange(activeMovable);

      selectedBars.clear();
      for (final bar in activeMovable.bars) {
        selectedBars.add(SelectionTokenBar(activeMovable, bar));
      }
    }

    _selectionProperties.classList.toggle('hidden', activeMovable == null);
  }

  void onPrefabNameChange(Prefab prefab) {
    if (activeMovable?.prefab == prefab) {
      _selectedLabelPrefix.textContent = prefab.name;
    }

    if (prefab is CharacterPrefab) {
      applyCharacterNameToAccessEntry(prefab.character);
    }
  }

  void _toggleMeasureSticky() {
    if (!_measureSticky.classList.toggle('active')) {
      removeMeasuring(session.charId, sendEvent: true);
    }
  }

  void _initBoard() {
    selected.onSetActive.listen(_onActiveMovableChange);

    _initMouseControls();
    initDiceTable();
    initGameLog();
    initiativeTracker.init(session.isDM);
    measureVisible = true;
    measureMode = 0;
    _measureToggle.addEventListener('click', ((web.MouseEvent ev) {
      var target = ev.target;

      if (target is web.HTMLElement) {
        var mMode = target.getAttribute('mode');
        if (mMode != null) {
          measureMode = int.parse(mMode);
          displayTooltip(getMeasureTooltip());

          // Prevent mode toggle
          if (mode == MEASURE) return;
        } else if (target == _measureSticky) {
          return _toggleMeasureSticky();
        } else if (target == _measureVisible) {
          measureVisible = !measureVisible;
          return;
        }
      }

      mode = MEASURE;
    }).toJS);
    _fowToggle.addEventListener('click', ((web.MouseEvent ev) {
      final clickedBox = ev.composedPath().toDart.cast<web.EventTarget?>().firstWhere(
        (e) => e is web.Element && e.className.contains('toolbox'),
        orElse: () => null,
      );

      if (clickedBox != null) {
        if (mode == FOG_OF_WAR || (clickedBox as web.Element).previousElementSibling != null) {
          return;
        }
      }
      mode = FOG_OF_WAR;
    }).toJS);

    _container.addEventListener('wheel', ((web.WheelEvent event) {
      if (event.target is web.HTMLInputElement) {
        if (event.target != web.document.activeElement) {
          (event.target as web.HTMLInputElement).focus();
        }
      } else {
        if (mode == FOG_OF_WAR && fogOfWar.canvas.activeTool.employMouseWheel) {
          return;
        }

        if (mapTab.visible ||
            event.composedPath().toDart.cast<web.EventTarget?>().any((e) => e is web.Element && e.className.contains('controls'))) {
          return;
        }
        // Create a simple wrapper for the wheel event
        final deltaY = event.deltaY;
        final v = min(50, deltaY.abs()) / 50;
        transform.zoom -= deltaY.sign * v * transform.zoomAmount;
      }
    }).toJS);

    _changeImage.addEventListener('mousedown', ((web.MouseEvent ev) {
      if (ev.button == 0) _changeImageDialog(ev);
    }).toJS);
    _editScene.addEventListener('click', ((web.Event _) { editingGrid = true; }).toJS);
    _exitEdit.addEventListener('click', ((web.Event _) { editingGrid = false; }).toJS);

    (_container.queryDom('#inactiveSceneWarning') as web.HTMLElement).addEventListener('click', ((web.Event _) {
      refScene.enterPlay();
    }).toJS);

    (_container.queryDom('#openMap') as web.HTMLElement).addEventListener('click', ((web.Event _) {
      mapTab.visible = true;
    }).toJS);

    _container.addEventListener('contextmenu', ((web.MouseEvent ev) {
      ev.preventDefault();

      // Only deselect if no other mouse button is currently pressed
      if (ev.buttons == 0) {
        _deselectAll();
      }
    }).toJS);

    // Prevent menu bar dropdown on Alt key
    web.window.addEventListener('keyup', ((web.KeyboardEvent event) {
      if (event.keyCode == 18) event.preventDefault();
    }).toJS);

    web.window.addEventListener('keydown', ((web.KeyboardEvent ev) {
      if (ev.target is web.HTMLInputElement || ev.target is web.HTMLTextAreaElement) return;

      if (ev.keyCode == 27) {
        // Escape
        if (selectedPrefab != null) {
          ev.preventDefault();
          _deselectAll();
        } else if (mode != PAN) {
          Future.delayed(Duration(milliseconds: 4), () {
            // Event might be handled by polymask or map view
            if (!ev.defaultPrevented) {
              mode = PAN;
              ev.preventDefault();
            }
          });
        }
      } else if (ev.key == 'm') {
        mapTab.visible = !mapTab.visible;
      } else if (session.isDM) {
        if (ev.keyCode == 46 || ev.keyCode == 8) {
          // Delete/Backspace
          ev.preventDefault();
          _removeSelectedMovables();
        }
        // Paste from clipboard
        else if (ev.key == 'v') {
          ev.preventDefault();
          if (clipboard.isNotEmpty) {
            cloneMovables(clipboard);
          }
        }
        // Copy to clipboard or duplicate
        else if (selected.isNotEmpty) {
          if (ev.ctrlKey || ev.metaKey) {
            // Copy with Ctrl+C or Cmd+C (MacOS)
            if (ev.key == 'c') {
              ev.preventDefault();
              clipboard = selected.toList();
            }
            // Cut with Ctrl+X or Cmd+X (MacOS)
            else if (ev.key == 'x') {
              ev.preventDefault();
              clipboard = selected.toList();
              _removeSelectedMovables();
            }
            // Duplicate with Ctrl+D or Cmd+D (MacOS)
            else if (ev.key == 'd') {
              ev.preventDefault();
              cloneMovables(selected);
            }
          }
        }
      }
    }).toJS);

    _initSelectionHandler();
    mapTab.initMapControls();
    fogOfWar.initFogOfWar(this);
  }

  void toggleSelect(
    Iterable<Movable> movables, {
    bool additive = false,
    bool? state,
  }) {
    if (!additive) {
      _deselectAll();
    }

    final doSelect = state ??
        activeMovable == null || !movables.any((m) => selected.contains(m));

    movables.forEach((m) {
      if (doSelect) {
        selected.add(m);
      } else {
        selected.remove(m);

        if (m == activeMovable) {
          selected.active = null;
        }
      }
    });

    if (doSelect && movables.length == 1) {
      Movable? active = movables.first;
      if (!active.accessible) {
        active = null;
      }
      selected.active = movables.first;
    }
    updateSnapToGrid();
  }

  void applyInactiveSceneWarning() {
    final isActiveScene = refScene.isPlaying;

    initiativeTracker.disabled = !isActiveScene;
    final warningElement = _container.queryDom('#inactiveSceneWarning') as web.HTMLElement;
    if (isActiveScene) {
      if (!warningElement.className.contains('hidden')) {
        warningElement.className = '${warningElement.className} hidden'.trim();
      }
    } else {
      warningElement.className = warningElement.className.replaceAll('hidden', '').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }

  void _removeSelectedMovables() async {
    if (mapTab.visible) return;

    await socket.sendAction(a.GAME_MOVABLE_REMOVE, {
      'movables': selected.map((m) => m.id).toList(),
    });

    for (var m in selected) {
      movables.remove(m);
      if (m == activeMovable) {
        selected.active = null;
      }
    }
    selected.clear();
  }

  void _snapSelection() {
    if (mapTab.visible) return;

    for (var m in selected) {
      m.roundToGrid();
    }

    _sendSelectedMovablesSnap();
  }

  void _goToMovable() {
    selected.active!.goTo();
    socket.sendAction(a.GAME_MOVABLE_GOTO, {
      'movable': selected.active!.id,
    });
  }

  void _pingMovable() {
    selected.active!.ping();
    socket.sendAction(a.GAME_MOVABLE_PING, {
      'movable': selected.active!.id,
    });
  }

  void onMovableSnap(Map<String, dynamic> json) {
    for (var jm in json['movables']) {
      var m = movables.firstWhere((mv) => mv.id == jm['id']);
      m.handleSnapEvent(jm);
    }
  }

  void onMovableGoTo(Map<String, dynamic> json) {
    var m = movables.firstWhere((mv) => mv.id == json['movable']);
    m.goTo();
  }

  void onMovablePing(Map<String, dynamic> json) {
    var m = movables.firstWhere((mv) => mv.id == json['movable']);
    m.ping();
  }

  void _deselectAll() {
    selected.clear();
    selectedPrefab = null;
  }

  void _updateSelectionSizeInherit() {
    (_selectedSize.parentElement!.children.item(_selectedSize.parentElement!.children.length - 1) as web.HTMLElement).style.display =
        activeMovable!.size == 0 ? '' : 'none';
  }

  void sendSelectedMovablesUpdate() {
    socket.sendAction(a.GAME_MOVABLE_UPDATE, {
      'changes': selected.map((e) => e.toJson()).toList(),
    });
  }

  /// Sends the current position and angle of all selected movables.
  void _sendSelectedMovablesSnap() {
    Map convertToJson(Movable m) => {
          'id': m.id,
          ...writePoint(m.position),
          'angle': m.angle,
        };

    socket.sendAction(a.GAME_MOVABLE_SNAP, {
      'movables': selected.map(convertToJson).toList(),
    });
  }

  void _updateSelectedInvisible(bool v) {
    if (v) {
      if (!_selectedInvisible.className.contains('active')) {
        _selectedInvisible.className = '${_selectedInvisible.className} active'.trim();
      }
    } else {
      _selectedInvisible.className = _selectedInvisible.className.replaceAll('active', '').replaceAll(RegExp(r'\\s+'), ' ').trim();
    }
    _selectedInvisible.queryDom('span').textContent = v ? 'Invisible' : 'Visible';
    _selectedInvisible.queryDom('i').className =
        'fas fa-' + (v ? 'eye-slash' : 'eye');
  }

  void updateSnapToGrid() {
    final allSnapped = selected.every((m) {
      final p =
          grid.grid.gridSnapCentered(m.position, m.displaySize).snapDeviation();
      return p == m.position;
    });
    _selectedSnap.disabled = allSnapped;
  }

  void _initSelectionHandler() {
    _selectedRemove.onClick.listen((_) => _removeSelectedMovables());
    _selectedSnap.onClick.listen((_) => _snapSelection());
    _selectedGoTo.onClick.listen((_) => _goToMovable());
    _selectedPing.onClick.listen((_) => _pingMovable());

    _listenSelectedLazyUpdate(_selectedLabel, onChange: (m, value) {
      m.label = value;
    });
    _listenSelectedLazyUpdate(_selectedAura, onChange: (m, value) {
      m.auraRadius = double.parse(value);
    });
    _selectedInvisible.onClick.listen((_) {
      var inv = !_selectedInvisible.className.contains('active');
      _updateSelectedInvisible(inv);
      selected.forEach((m) => m.invisible = inv);
      sendSelectedMovablesUpdate();
    });
    _listenSelectedLazyUpdate(_selectedSize, onChange: (m, value) {
      m.setSizeWithGridSpecifics(int.parse(value));
      _updateSelectionSizeInherit();
    });

    _addTokenBarButton.onClick.listen((_) => _addNewBarToSelectedTokens());
  }

  void _addNewBarToSelectedTokens() {
    var label = 'HP';
    if (activeMovable!.bars.any((bar) => bar.label == label)) {
      final number = activeMovable!.bars.length + 1;
      label = 'Bar $number';
    }

    final activeBar = TokenBar(label: label);
    activeMovable!.bars.add(activeBar);
    activeMovable!.createTokenBarComponent(activeBar);

    for (var movable in selected.where((m) => m != activeMovable)) {
      final hasBarOfName = movable.bars.any((bar) => bar.label == label);
      if (!hasBarOfName) {
        final bar = TokenBar(label: label);
        movable.bars.add(bar);

        final component = movable.createTokenBarComponent(bar);
        component.updateHighlight(activeMovable);
      }
    }

    final barComponent = SelectionTokenBar(activeMovable!, activeBar);
    selectedBars.add(barComponent);

    sendSelectedMovablesUpdate();
  }

  void modifySelectedTokenBars(
    TokenBar originBar,
    void Function(Movable token, TokenBar bar) modify,
  ) {
    modify(activeMovable!, originBar);

    final label = originBar.label;

    for (var movable in selected.where((m) => m != activeMovable)) {
      final similarBar = movable.bars.find((bar) => bar.label == label);
      if (similarBar != null) {
        modify(movable, similarBar);
      }
    }
  }

  void _listenSelectedLazyUpdate(
    web.HTMLInputElement input, {
    required void Function(Movable m, String value) onChange,
  }) {
    input.listenLazyUpdate(
      onChange: (value) => selected.forEach((m) => onChange(m, value)),
      onSubmit: (value) => sendSelectedMovablesUpdate(),
    );
  }

  void _initMouseControls() {
    SimpleEvent? lastEv;
    StreamController<SimpleEvent>? moveStreamCtrl;

    void _alignAngleArrow() {
      if (activeMovable == null) return;

      var display = false;

      if (lastEv != null && lastEv.alt) {
        // Only show angle arrow if no movable is hovered
        final domPath = lastEv.path!;

        display = !domPath.any(
          (e) => e is web.Element && (e as web.HTMLElement).className.contains('movable'),
        );
      }

      if (display && lastEv != null) {
        angleArrow.align(this, lastEv.p * (1 / scaledZoom));
      }
      angleArrow.visible = display;
    }



    // Note: Simplified event handling for package:web compatibility
    // The original dart:html stream-based approach needs to be reimplemented
    _container.addEventListener('mousedown', ((web.Event event) {
      // Handle mouse down event
    }).toJS);
    
    _container.addEventListener('touchstart', ((web.Event event) {
      // Handle touch start event
    }).toJS);

    void triggerUpdate(bool alt) {
      
    }

    web.window.addEventListener('keydown', ((web.Event event) {
      final ev = event as web.KeyboardEvent;
      if (!ev.repeat && ev.keyCode == 18) {
        triggerUpdate(true);
      }
    }).toJS);
    
    web.window.addEventListener('keyup', ((web.Event event) {
      final ev = event as web.KeyboardEvent;
      if (ev.keyCode == 18) {
        triggerUpdate(false);
      }
    }).toJS);
  }




  void displayTooltip(String text) {
    (_container.queryDom('#tooltip') as web.HTMLElement).innerHTML = formatToHtml(text).toJS;
  }

  void displayPing(Point p, int? player) async {
    var ping = web.document.createElement('div') as web.HTMLDivElement
      ..className = 'ping'
      ..style.left = '${p.x}px'
      ..style.top = '${p.y}px'
      ..style.borderColor = session.getPlayerColor(player);
    _e.append(ping);
    await Future.delayed(Duration(seconds: 3));
    ping.remove();
  }

  void _changeImageDialog(web.MouseEvent ev) async {
    final previousSize = Point(_ground.naturalWidth, _ground.naturalHeight);
    final previousGridPos = grid.offset;
    final previousGridSize = grid.size;

    final result = await upload.display(
      event: ev,
      action: a.GAME_SCENE_UPDATE,
      type: a.IMAGE_TYPE_SCENE,
      extras: {'id': refScene.id},
    );

    if (result == null) return; // Upload was cancelled

    final path = result['image'];
    final tiles = result['tiles'];

    await changeSceneImage(path);

    final w = _ground.naturalWidth;
    final h = _ground.naturalHeight;

    if (tiles != null) {
      grid.tiles = tiles;
      gridTiles.valueAsNumber = tiles;
      grid.resetPosAndSize(w, h);
    } else {
      // Stretch grid
      final wRatio = w / previousSize.x;
      final hRatio = h / previousSize.y;

      final pos = Point(previousGridPos.x * wRatio, previousGridPos.y * hRatio);
      final size =
          Point(previousGridSize.x * wRatio, previousGridSize.y * hRatio);
      grid.setPosAndSize(pos, size);
    }
  }

  Future<void> changeSceneImage(String path) async {
    refScene.background.path = path;
    refScene.applyBackground();

    final src = Resource(path).url;
    await _applyImage(src);
  }

  Future<void> _applyImage(String src) async {
    _ground.src = src;

    await _ground.onLoad.first;
    grid.constrainSize(_ground.naturalWidth, _ground.naturalHeight);
    fogOfWar.fixSvgInit(_ground.naturalWidth, _ground.naturalHeight);
  }

  void applyCellSize() {
    const fowPatternReferenceSize = 120;
    final tokenSize = grid.tokenSize;
    _e.style.setProperty('--cell-size', '$tokenSize');
    fogOfWar.setSvgPatternScaling(tokenSize / fowPatternReferenceSize);
  }

  void clear() {
    _deselectAll();
    movables.clear();
  }

  Point<double> gridToHtmlSpace(Point p) {
    final world = grid.grid.gridToWorldSpace(p);

    final groundHalfSize =
        Point(_ground.naturalWidth / -2, _ground.naturalHeight / -2);

    return groundHalfSize + world;
  }

  Future<void> animateTransformToToken(Movable m) async {
    final pos = gridToHtmlSpace(m.position);
    final inverse = pos * -1;

    final duration = Duration(milliseconds: 800);

    await transform.animateTo(inverse, duration);
  }

  void _syncMovableAnim() async {
    var elems = _e.querySelectorAll('.movable .ring');
    for (var i = 0; i < elems.length; i++) {
      var m = elems.item(i)! as web.HTMLElement;
      m.style.animation = 'none';
      m.innerText; // Trigger reflow
    }
    for (var i = 0; i < elems.length; i++) {
      var m = elems.item(i)! as web.HTMLElement;
      m.style.animation = '';
    }
  }

  Future<void> cloneMovables(Iterable<Movable> source) async {
    var jsons = source.map((m) => m.toCloneJson());

    var result = await socket.request(a.GAME_MOVABLE_CREATE_ADVANCED, {
      'movables': jsons.toList(),
    });

    if (session.isDemo) {
      result = List<int>.generate(source.length, (i) => nextMovableId + i);
    } else if (result == null) {
      return _onMovableCountLimitReached();
    }

    var ids = List<int>.from(result);

    var dest = <Movable>[];
    for (var i = 0; i < ids.length; i++) {
      var src = source.elementAt(i);

      var m = Movable.create(
        board: this,
        prefab: src.prefab,
        id: ids[i],
        pos: src.position,
        conds: src.conds,
      )..fromJson(jsons.elementAt(i));

      m.label = generateNewLabel(m, movables);

      dest.add(m);
      movables.add(m);
    }
    _deselectAll();
    _syncMovableAnim();
    toggleSelect(dest, state: true);
    updateRerollableInitiatives();
  }

  Future<Movable> addMovable(Prefab prefab, Point<double> pos) async {
    var id = await socket.request(a.GAME_MOVABLE_CREATE, {
      ...writePoint(pos),
      'prefab': prefab.id,
    });

    if (session.isDemo) {
      id = nextMovableId;
    } else if (id == null) {
      _onMovableCountLimitReached();
      throw RangeError('Limit of tokens reached');
    }

    var m = Movable.create(
        board: this, prefab: prefab, id: id, pos: pos, conds: []);

    m.label = generateNewLabel(m, movables);

    movables.add(m);
    _syncMovableAnim();
    updateRerollableInitiatives();
    return m;
  }

  void _onMovableCountLimitReached() {
    HtmlNotification('Limit of ${user.tokensPerScene} movables reached.').display();
    _deselectAll();
  }

  void onMovableCreateAdvanced(Map<String, dynamic> json) {
    for (var m in json['movables']) {
      onMovableCreate(m);
    }
  }

  void onMovableCreate(Map<String, dynamic> json) {
    String pref = json['prefab'];
    var isEmpty = pref[0] == 'e';

    var m = Movable.create(
      board: this,
      prefab: isEmpty ? emptyPrefab : getPrefab(pref)!,
      id: json['id'],
    )..fromJson(json);
    movables.add(m);
  }

  void onUpdatePrefabImage(Prefab p) {
    for (var movable in movables) {
      if (movable.prefab == p) {
        movable.applyImage();
      }
    }

    initiativeTracker.onUpdatePrefabImage(p);
  }

  void _movableEvent(json, void Function(Movable m) action) {
    List ids = json['movables'] ?? [json['movable']];

    for (var m in List.from(movables)) {
      if (ids.contains(m.id)) {
        action(m);
      }
    }
  }

  void onMovablesMove(json) {
    List movements = json['movables'];

    for (Map movableJson in movements) {
      final int movableId = movableJson['id'];
      final position = parsePoint<double>(movableJson)!;

      movables.find((m) => m.id == movableId)!.position = position;
    }
  }

  void onMovableRemove(json) => _movableEvent(json, (m) {
        if (selected.contains(m)) {
          toggleSelect([m], additive: true, state: false);
        }
        movables.remove(m);
      });

  void onMovablesUpdate(json) {
    Iterable changes = json['changes'];
    for (var change in changes) {
      var id = change['movable'];
      var m = movables.firstWhere((m) => m.id == id);
      m.fromJson(change);
    }
  }

  void rescaleMeasurings() {
    fogOfWar.applyUseGrid(this);
  }

  void resetTransform() {
    zoom = -0.5;
    position = Point(0, 0);
  }

  Future<void> _onSceneChange() async {
    clear();

    await _applyImage(refScene.background.url);
    mode = PAN;
  }

  void load({
    required int sceneID,
    bool setAsPlaying = true,
    String? fowData,
    Map<String, dynamic>? refSceneData,
    required void Function(SceneGrid grid) loadGrid,
    required Iterable movablesData,
    Iterable? initiativeData,
  }) async {
    if (session.isDM) {
      _refScene = session.scenes.find((e) => e.id == sceneID)!;
      if (setAsPlaying) {
        session.playingScene = _refScene;
      }

      session.applySceneEditPlayStates();
    } else {
      _refScene = Scene.fromJson(refSceneData!);
    }

    await _onSceneChange();

    fogOfWar.load(fowData);
    loadGrid(grid);
    rescaleMeasurings();

    for (var m in movablesData) {
      onMovableCreate(m);
    }

    initiativeTracker.fromJson(initiativeData);
    resetTransform();
  }

  void fromJson(Map<String, dynamic> json, {bool setAsPlaying = true}) async {
    load(
      sceneID: json['id'],
      setAsPlaying: setAsPlaying,
      refSceneData: json,
      fowData: json['fow'],
      loadGrid: (grid) => grid.fromJson(json['grid']),
      movablesData: json['movables'],
      initiativeData: json['initiative'],
    );
  }
}

class BoardTransform extends HtmlTransform {
  final Board board;
  final Map<web.Element, bool> _invZoom = {};

  BoardTransform(
    this.board,
    web.Element element, {
    required Point Function() getMaxPosition,
  }) : super(element, getMaxPosition: getMaxPosition);

  @override
  set zoom(double zoom) {
    super.zoom = zoom;
    applyInvZoom();
  }

  String get _invZoomScale => 'scale(${1 / scaledZoom})';
  String get _invZoomScaleCell =>
      'scale(${70 / board.grid.cellWidth / scaledZoom})';

  void applyInvZoom() {
    final scale = _invZoomScale;
    final scaleCell = _invZoomScaleCell;
    _invZoom.forEach((e, c) => (e as web.HTMLElement).style.transform = c ? scaleCell : scale);
  }

  web.Element registerInvZoom(web.Element e, {bool scaleByCell = false}) {
    _invZoom[e] = scaleByCell;
    (e as web.HTMLElement).style.transform = scaleByCell ? _invZoomScaleCell : _invZoomScale;
    return e;
  }

  void unregisterInvZoom(web.Element e) {
    _invZoom.remove(e);
  }
}
