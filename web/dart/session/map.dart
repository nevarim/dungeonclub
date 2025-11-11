import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

// import 'package:async/async.dart'; // Unused import
import 'package:dungeonclub/actions.dart';
import 'package:dungeonclub/iterable_extension.dart';
import 'package:dungeonclub/session_util.dart';
import 'package:web_whiteboard/whiteboard.dart';

import '../../main.dart';
import '../communication.dart';
import '../html_helpers.dart';
import '../html_transform.dart';
import '../panels/upload.dart' as uploader;
import '../resource.dart';
import 'map_tool_info.dart';

final web.HTMLElement _e = queryDom('#map');
final web.HTMLElement _mapContainer = _e.queryDom('#maps');
final web.HTMLElement _minimapContainer = _e.queryDom('#mapSelect');
final web.HTMLButtonElement _backButton = _e.queryDom('button[type=reset]');
final web.HTMLButtonElement _imgButton = _e.queryDom('#addMap');
final web.HTMLInputElement _name = _e.queryDom('#mapName');
final web.HTMLButtonElement _shared = _e.queryDom('#mapShared');
final web.HTMLElement _tools = _e.queryDom('#mapTools');
final web.HTMLElement _toolInfo = _e.queryDom('#toolInfo');
final web.HTMLInputElement _color = _e.queryDom('#activeColor');

final web.HTMLElement _indexText = _e.queryDom('#mapIndex');
final _navLeft = _name.previousElementSibling as web.HTMLButtonElement;
final _navRight = _name.parentElement!.children.item(_name.parentElement!.children.length - 1) as web.HTMLButtonElement;

web.HTMLButtonElement get _deleteButton => _e.queryDom('#mapDelete');

class MapTab {
  final maps = <GameMap>[];

  bool get editMode => _e.className.contains('edit');
  set editMode(bool editMode) {
    if (editMode) {
      if (!_e.className.contains('edit')) _e.className += ' edit';
    } else {
      _e.className = _e.className.replaceAll(' edit', '').replaceAll('edit', '');
    }
    (_backButton.childNodes.item(0) as web.Text).data = editMode ? 'Overview' : 'Exit Map View';

    if (!editMode) {
      map!.transform.reset();
    }

    Future.delayed(
      Duration(milliseconds: editMode ? 400 : 0),
      () {
        if (editMode) {
          if (!_mapContainer.className.contains('animate')) _mapContainer.className += ' animate';
        } else {
          _mapContainer.className = _mapContainer.className.replaceAll(' animate', '').replaceAll('animate', '');
        }
      },
    );
  }

  int _mapIndex = 0;
  int get mapIndex => _mapIndex;
  set mapIndex(int mapIndex) {
    if (map != null) {
      map!.whiteboard.captureInput = false;
      map!.transform.reset();
    }

    _mapIndex = mapIndex;

    final focusedMap = map!;

    _mapContainer.style.left = '${mapIndex * -100}%';
    _name.value = focusedMap.name;
    shared = focusedMap.shared;
    mode = mode;
    _updateHistoryButtons();
    _updateNavigateButtons();
    _updateIndexText();
    Future.microtask(() => focusedMap._fixScaling());
  }

  Point get mapSize {
    if (map == null) return Point(0, 0);

    var img = map!.whiteboard.backgroundImageElement;
    return Point(img.naturalWidth, img.naturalHeight);
  }

  GameMap? get map =>
      (maps.isNotEmpty && mapIndex < maps.length) ? maps[mapIndex] : null;

  String _mode = 'draw';
  String get mode => _mode;
  set mode(String mode) {
    _mode = mode;
    final activeElements = _tools.querySelectorAll('.active:not(#mapShared)');
    for (int i = 0; i < activeElements.length; i++) {
      final element = activeElements.item(i)! as web.HTMLElement;
       element.className = element.className.replaceAll(' active', '').replaceAll('active', '');
    }
    final activeElement = _tools.queryDom('[mode=$mode]');
    if (!activeElement.className.contains('active')) activeElement.className += ' active';
    _setToolInfo(mode);

    _color.disabled = mode != 'draw';

    if (maps.isNotEmpty) {
      var wb = map!.whiteboard;
      if (mode == 'erase') {
        wb.mode = Whiteboard.modeDraw;
        wb.eraser = true;
      } else {
        wb.mode = mode;
        wb.eraser = false;

        if (mode == 'draw') {
          wb.activeColor = _color.value;
        }
      }
    }
  }

  bool get visible => _e.className.contains('show');
  set visible(bool visible) {
    if (visible) {
      if (!_e.className.contains('show')) _e.className += ' show';
    } else {
      _e.className = _e.className.replaceAll(' show', '').replaceAll('show', '');
    }
    if (visible) {
      _updateNavigateButtons();
    }
  }

  set shared(bool shared) {
    if (shared) {
      if (!_shared.className.contains('active')) _shared.className += ' active';
    } else {
      _shared.className = _shared.className.replaceAll(' active', '').replaceAll('active', '');
    }
    _updateToolsVisibility();
  }

  void _updateToolsVisibility() {
    final currentMap = map!;

    final useTools = (user.session!.isDM || currentMap.shared) &&
        !currentMap.transform.isOffCenter;

    currentMap.whiteboard.captureInput = useTools;
    if (!useTools) {
      if (!_tools.className.contains('hidden')) _tools.className += ' hidden';
    } else {
      _tools.className = _tools.className.replaceAll(' hidden', '').replaceAll('hidden', '');
    }
  }

  void _updateNavigateButtons() {
    _navLeft.disabled = mapIndex == 0;

    if (user.session!.isDM) {
      var showAdd = mapIndex == maps.length - 1;
      var icon = showAdd ? 'plus' : 'chevron-right';
      if (showAdd) {
        if (!_navRight.className.contains('add-map')) _navRight.className += ' add-map';
      } else {
        _navRight.className = _navRight.className.replaceAll(' add-map', '').replaceAll('add-map', '');
      }
      (_navRight.children.item(0) as web.HTMLElement).className = 'fas fa-$icon';

      if (showAdd && maps.length >= user.mapsPerCampaign) {
        _navRight.disabled = true;
        _navRight.queryDom('span').textContent =
            'Limit of ${user.mapsPerCampaign} Maps Reached!';
      } else {
        _navRight.disabled = maps.isEmpty;
        _navRight.queryDom('span').textContent = 'Create New Map';
      }
    } else {
      _navRight.disabled = mapIndex >= maps.length - 1;
    }
  }

  web.HTMLButtonElement _toolBtn(String name) => _tools.queryDom('[action=$name]');

  void _updateHistoryButtons() {
    _toolBtn('clear').disabled = map!.whiteboard.isClear;
    _toolBtn('undo').disabled = map!.whiteboard.history.positionInStack == 0;
    _toolBtn('redo').disabled = !map!.whiteboard.history.canRedo;
  }

  void _setToolInfo(String id) {
    try {
      final info = getToolInfo(id, user.session!.isDM);
      _toolInfo.innerHTML = info.toJS;
    } on ArgumentError catch (_) {}
  }

  Future<bool> _uploadNewMap(dynamic ev) async {
    if (maps.length >= user.mapsPerCampaign) return false;

    final response = await uploader.display(
      event: ev,
      action: GAME_MAP_CREATE,
      type: IMAGE_TYPE_MAP,
    );

    if (response != null) {
      // Fallback to next available ID in demo session
      final mapID = response['map'] ?? maps.getNextAvailableID((e) => e.id);

      addMap(mapID, '', response['image'], false);
      _enterEdit(mapID);
      _name.focus();
      return true;
    }
    return false;
  }

  void _back() {
    if (editMode) {
      editMode = false;
    } else {
      visible = false;
    }
  }

  void initMapControls() {
    _backButton.addEventListener('click', ((web.Event _) => _back()).toJS);

    web.window.addEventListener('resize', ((web.Event _) => maps.forEach((m) => m._fixScaling())).toJS);
    web.window.addEventListener('keydown', (web.Event event) {
      final ev = event as web.KeyboardEvent;
      if (!visible ||
          ev.target is web.HTMLInputElement ||
          ev.target is web.HTMLTextAreaElement) {
        return;
      }

      if (ev.keyCode == 27) {
        ev.preventDefault();
        _back();
        // Arrow key controls
      } else if (editMode) {
        if (ev.keyCode == 37 && mapIndex > 0) {
          mapIndex--;
        } else if (ev.keyCode == 39 && mapIndex < maps.length - 1) {
          mapIndex++;
        }
      }
    }.toJS);

    _navLeft.addEventListener('click', ((web.Event _) => mapIndex--).toJS);
    _navRight.addEventListener('click', (web.Event event) {
      final ev = event as web.MouseEvent;
      if (user.session!.isDM && mapIndex == maps.length - 1) {
        _uploadNewMap(ev);
      } else {
        mapIndex++;
      }
    }.toJS);

    _imgButton.addEventListener('click', (web.Event event) {
      _uploadNewMap(event as web.MouseEvent);
    }.toJS);
    _deleteButton.addEventListener('click', ((web.Event _) => _deleteCurrentMap()).toJS);

    _initZoom();
    _initTools();
    _initMapName();
    _shared.addEventListener('click', ((web.Event _) {
      final currentMap = map!;

      currentMap.shared = !currentMap.shared;
      shared = currentMap.shared;
      socket.sendAction(GAME_MAP_UPDATE, {
        'map': currentMap.id,
        'shared': currentMap.shared,
      });
    }).toJS);
  }

  void _initZoom() {
    // Removed unused variables: moveStreamCtrl, previous, initialButton

    _e.addEventListener('wheel', ((web.Event event) {
      final ev = event as web.WheelEvent;
      if (map != null) {
        if (visible && editMode && map!.whiteboard.selectedText == null) {
          map!.transform.handleMousewheel(ev);
        }
      }
    }).toJS);

    // Note: These event listeners need to be implemented differently for package:web
    // The listenToCursorEvents function expects dart:html streams which are not available in package:web
  }

  void _initTools() {
    void registerAction(String name, void Function(dynamic ev) action) {
      web.HTMLButtonElement button = _tools.queryDom('[action=$name]');
      button.addEventListener('click', ((web.Event event) => action(event)).toJS);

      button.addEventListener('mouseenter', ((web.Event _) => _setToolInfo(name)).toJS);
      button.addEventListener('mouseleave', ((web.Event _) => _setToolInfo(mode)).toJS);
    }

    void clearMap() {
      map?.whiteboard.clear();
      _toolBtn('clear').disabled = true;
    }

    _color.addEventListener('input', ((web.Event _) {
      if (maps.isNotEmpty) {
        map!.whiteboard.activeColor = _color.value;
      }
    }).toJS);

    final toolChildren = _tools.children.item(0)!.children;
    for (int i = 0; i < toolChildren.length; i++) {
      final element = toolChildren.item(i)!;
      if (element is web.HTMLButtonElement) {
        element.addEventListener('click', ((web.Event _) {
          mode = element.getAttribute('mode')!;
        }).toJS);
      }
    }

    registerAction('undo', (_) => map?.whiteboard.history.undo());
    registerAction('redo', (_) => map?.whiteboard.history.redo());
    registerAction('clear', (_) => clearMap());
    registerAction('change', (ev) async {
      final currentMap = map!;

      final response = await uploader.display(
        event: ev,
        action: GAME_MAP_UPDATE,
        type: IMAGE_TYPE_MAP,
        extras: {'map': currentMap.id},
      );

      if (response != null) {
        clearMap();
        currentMap.image.path = response['image'];
        currentMap.applyImage();
      }
    });

    _toolInfo.addEventListener('click', ((web.Event _) => _setInfoVisible(false)).toJS);
    _e.queryDom('#infoShow').addEventListener('click', ((web.Event _) => _setInfoVisible(true)).toJS);
    if (web.window.localStorage.getItem('mapToolInfo') == 'false') {
      if (!_tools.className.contains('collapsed')) _tools.className += ' collapsed';
    } else {
      _tools.className = _tools.className.replaceAll(' collapsed', '').replaceAll('collapsed', '');
    }
  }

  void _setInfoVisible(bool v) {
    if (!v) {
      if (!_tools.className.contains('collapsed')) _tools.className += ' collapsed';
    } else {
      _tools.className = _tools.className.replaceAll(' collapsed', '').replaceAll('collapsed', '');
    }
    web.window.localStorage.setItem('mapToolInfo', '$v');
  }

  void _listenToEraseAcross() {
    web.window.addEventListener('keydown', (web.Event event) {
      final ev = event as web.KeyboardEvent;
      if (ev.keyCode == 16) map?.whiteboard.eraseAcrossLayers = true;
    }.toJS);
    web.window.addEventListener('keyup', (web.Event event) {
      final ev = event as web.KeyboardEvent;
      if (ev.keyCode == 16) map?.whiteboard.eraseAcrossLayers = false;
    }.toJS);
  }

  void _deleteCurrentMap() {
    socket.sendAction(GAME_MAP_REMOVE, {'map': map!.id});
    onMapRemove(map!.id);
  }

  void onMapRemove(int id) {
    final map = maps.find((m) => m.id == id)!;

    map._dispose();
    maps.remove(map);

    if (maps.isEmpty) {
      _onAllRemoved();
    } else {
      mapIndex = min(max(mapIndex, 0), maps.length - 1);
    }
  }

  void _initMapName() {
    final parent = _name.parentElement!;
    web.HTMLButtonElement confirmBtn = parent.queryDom('.dm');
    var focus = false;
     
     // Simple event listeners without StreamGroup for now
     _name.addEventListener('keydown', (web.Event event) {
       final ev = event as web.KeyboardEvent;
       if (ev.keyCode == 13 && focus) {
         focus = false;
         parent.className = parent.className.replaceAll(' focus', '').replaceAll('focus', '');
         _name.blur();
         map!.name = _name.value;
         socket.sendAction(GAME_MAP_UPDATE, {'map': map!.id, 'name': _name.value});
       }
     }.toJS);
     
     confirmBtn.addEventListener('mousedown', (web.Event _) {
       if (focus) {
         focus = false;
         parent.className = parent.className.replaceAll(' focus', '').replaceAll('focus', '');
         _name.blur();
         map!.name = _name.value;
         socket.sendAction(GAME_MAP_UPDATE, {'map': map!.id, 'name': _name.value});
       }
     }.toJS);
    _name.addEventListener('focus', (web.Event _) {
      focus = true;
      if (!parent.className.contains('focus')) parent.className += ' focus';
    }.toJS);
    _name.addEventListener('blur', (web.Event _) {
      Future.delayed(Duration(milliseconds: 50)).then((_) {
        if (focus) {
          _name.value = map!.name;
          parent.className = parent.className.replaceAll(' focus', '').replaceAll('focus', '');
          focus = false;
        }
      });
    }.toJS);

    // Event listeners already added above
  }

  void _onFirstUpload() {
    mapIndex = 0;
    if (user.session!.isDM) {
      _name.disabled = false;
    }
  }

  void _onAllRemoved() {
    editMode = false;
    _updateNavigateButtons();
    _name.value = '';
    if (user.session!.isDM) {
      _name.disabled = true;
    }
  }

  void fromJson(Iterable json) {
    maps.removeWhere((m) {
      m._em.remove();
      return true;
    });

    json.forEach((jMap) => addMap(jMap['map'], jMap['name'], jMap['image'],
        jMap['shared'], jMap['data']));
    if (maps.isNotEmpty) {
      _onFirstUpload();
    }

    if (user.session!.isDM) {
      _color.value = '#000000';
    } else {
      _color.value = user.session!.getPlayerColor(user.session!.charId);
    }
    mode = Whiteboard.modeDraw;

    if (user.session!.isDM) {
      _listenToEraseAcross();
    }
  }

  void _updateIndexText() => _indexText.textContent = '${mapIndex + 1}/${maps.length}';

  void addMap(int id, String name, String image, bool shared,
      [String? encodedData]) {
    final map = GameMap(
      this,
      id,
      name: name,
      shared: shared,
      encodedData: encodedData,
      onEnterEdit: () => _enterEdit(id),
      image: Resource(image),
    );
    map.whiteboard.history.onChange.listen((_) => _updateHistoryButtons());
    maps.add(map);

    if (maps.length == 1) _onFirstUpload();

    _updateNavigateButtons();
    _updateIndexText();
  }

  void _enterEdit(int id) {
    mapIndex = maps.indexWhere((m) => m.id == id);
    editMode = true;
  }

  void onMapUpdate(Map<String, dynamic> json) {
    var map = maps.firstWhere((m) => m.id == json['map']);
    var name = json['name'];
    var shared = json['shared'];
    if (name != null) {
      map.name = name;
      if (maps[mapIndex] == map) _name.value = map.name;
    } else if (shared != null) {
      map.shared = shared;
      if (maps[mapIndex] == map) this.shared = shared;
    } else {
      map.image.path = json['image'];
      map.applyImage();
    }
  }

  void handleEvent(Uint8List bytes) {
    var map = maps.firstWhere((m) => m.id == bytes.first);

    map.whiteboard.socket.handleEventBytes(bytes.sublist(1));
    map.updateMiniImage();
  }
}

class GameMap {
  final MapTab mapTab;

  final int id;
  final Resource image;
  late MapTransform transform;
  late web.HTMLElement _em;
  late web.HTMLElement _container;
  late web.HTMLElement _minimap;
  late web.HTMLSpanElement _miniTitle;
  late Whiteboard whiteboard;
  bool shared;

  String get name => _miniTitle.textContent ?? '';
  set name(String name) {
    _miniTitle.textContent = name;
  }

  GameMap(
    this.mapTab,
    this.id, {
    String name = '',
    this.shared = false,
    String? encodedData,
    required this.image,
    required void Function() onEnterEdit,
  }) {
    _em = web.document.createElement('div') as web.HTMLElement;
    _em.className = 'map';
    _container = web.document.createElement('div') as web.HTMLElement;
    _em.appendChild(_container);
    _mapContainer.appendChild(_em);

    _minimap = web.document.createElement('div') as web.HTMLElement;
    _minimap.className = 'minimap';
    _miniTitle = web.document.createElement('span') as web.HTMLSpanElement;
    _minimap.appendChild(_miniTitle);
    _minimap.addEventListener('click', ((web.Event _) => onEnterEdit()).toJS);
    _minimapContainer.insertBefore(_minimap, _imgButton);
    this.name = name;

    whiteboard = Whiteboard(_container as dynamic, textControlsWrapMin: 150)
      ..backgroundImageElement.crossOrigin = 'anonymous'
      ..socket.sendStream.listen((data) {
        updateMiniImage();
        socket.send(Uint8List.fromList([id, ...data]).buffer);
      })
      ..useStartEvent = (ev) {
        if (isMobile) return false;
        return ev is! web.MouseEvent || (ev as web.MouseEvent).button == 0;
      };

    if (encodedData != null) {
      whiteboard.fromBytes(base64.decode(encodedData));
    } else {
      for (var i = 0; i <= user.session!.characters.length; i++) {
        whiteboard.addDrawingLayer();
      }
    }

    // Assign user their own exclusive drawing layer
    if (user.session!.isDM) {
      whiteboard.layerIndex = 0;
    } else {
      final myChar = user.session!.myCharacter!;
      final pcIndex = user.session!.characters.indexOf(myChar);

      whiteboard.layerIndex = 1 + pcIndex;
    }
    applyImage();

    transform = new MapTransform(this);
  }

  void _dispose() {
    _em.remove();
    _minimap.remove();
    whiteboard.history.erase();
    whiteboard.captureInput = false;
  }

  void _fixScaling() {
    _container.style.width = '100%';
    whiteboard.updateScaling();
    var img = _container.queryDom('image');

    var bestWidth = img.getBoundingClientRect().width;
    if (bestWidth > 0) {
      _container.style.width = '${bestWidth}px';
      whiteboard.updateScaling();
    }
  }

  Future<void> updateMiniImage() async {
    var divide = whiteboard.naturalWidth / 300;
    var canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
    canvas.width = whiteboard.naturalWidth ~/ divide;
    canvas.height = whiteboard.naturalHeight ~/ divide;
    var context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.scale(1 / divide, 1 / divide);
    // Note: whiteboard.drawToCanvas and uploader.canvasToBase64 may need updates for package:web canvas
    // whiteboard.drawToCanvas(canvas);
    // var base64 = await uploader.canvasToBase64(canvas, includeHeader: true);
    _minimap.style.backgroundImage = "url('$base64')";
  }

  void applyImage() async {
    final src = image.url;

    await whiteboard.changeBackground(src);
    await updateMiniImage();

    // Different browsers need different times to be able to call _fixScaling
    for (var i = 0; i < 5; i++) {
      await Future.delayed(Duration(milliseconds: 20), _fixScaling);
    }
  }
}

class MapTransform extends HtmlTransform {
  final GameMap map;
  bool isOffCenter = false;
  Point Function()? getMapSize;

  MapTransform(this.map) : super(map._em, zoomAmount: 0.2) {
    getMaxPosition = () => map.mapTab.mapSize * zoom;
  }

  void _setOffCenter(bool v) {
    if (isOffCenter != v) {
      isOffCenter = v;
      map.mapTab._updateToolsVisibility();
    }
  }

  @override
  set zoom(double zoom) {
    super.zoom = min(max(zoom, 0), 0.85);
    clampPosition();
    _setOffCenter(super.zoom != 0);
  }
}
