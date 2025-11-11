import 'dart:async';
import 'dart:math' show Point, max, atan2, pi, sqrt;
import 'package:web/web.dart' as web;

import 'package:dungeonclub/models/entity_base.dart';
import 'package:dungeonclub/models/token.dart';
import 'package:dungeonclub/models/token_bar.dart';
import 'package:dungeonclub/point_json.dart';
import 'package:grid_space/grid_space.dart';

import '../html/instance_component.dart';
import '../html/instance_list.dart';
import '../html_helpers.dart';
import 'board.dart';
import 'condition.dart';
import 'prefab.dart';
import 'token_bar_component.dart';

class Movable extends InstanceComponent
    with EntityBase, ClampedEntityBase, TokenModel {
  @override
  final int id;
  final Board board;
  final Prefab prefab;

  @override
  String get prefabId => prefab.id;

  final _aura = web.document.createElement('div') as web.HTMLDivElement;
  final _barsRoot = web.document.createElement('ul') as web.HTMLUListElement;
  late final barInstances = InstanceList<TokenBarComponent>(_barsRoot as dynamic);

  String get name => prefab.name;

  bool get accessible {
    if (board.session.isDM) return true;

    var charId = board.session.charId;
    if (prefab is CharacterPrefab) {
      return (prefab as CharacterPrefab).character.id == charId;
    }
    if (prefab is CustomPrefab) {
      return (prefab as CustomPrefab).accessIds.contains(charId);
    }
    return false;
  }

  @override
  int get minSize => 0;

  @override
  set label(String label) {
    super.label = label;
    board.initiativeTracker.onNameUpdate(this);
    updateTooltip();
  }

  String get displayName {
    if (label.isEmpty) return prefab.name;
    return '${prefab.name} ($label)';
  }

  @override
  set angle(double angle) {
    super.angle = angle;
    (htmlRoot as web.HTMLElement).style.setProperty('--angle', '$angle');
  }

  @override
  set invisible(bool invisible) {
    super.invisible = invisible;
    (htmlRoot as web.HTMLElement).classList.toggle('invisible', invisible);
  }

  set styleActive(bool value) {
    (htmlRoot as web.HTMLElement).classList.toggle('active', value);
  }

  bool get styleSelected => (htmlRoot as web.HTMLElement).classList.contains('selected');
  set styleSelected(bool value) {
    (htmlRoot as web.HTMLElement).classList.toggle('selected', value);
  }

  bool get stylePinged => (htmlRoot as web.HTMLElement).classList.contains('pinged');
  set stylePinged(bool value) {
    (htmlRoot as web.HTMLElement).classList.toggle('pinged', value);
  }

  set styleHovered(bool value) {
    (htmlRoot as web.HTMLElement).classList.toggle('hovered', value);
  }

  set stylePreventTransition(bool value) {
    (htmlRoot as web.HTMLElement).classList.toggle('no-animate-move', value);
  }

  @override
  set auraRadius(double auraRadius) {
    super.auraRadius = auraRadius;
    _aura.style.display = auraRadius == 0 ? 'none' : '';
    _aura.style.setProperty('--aura', '$auraRadius');
  }

  @override
  set position(Point<double> position) {
    super.position = position.snapDeviationAny();
    applyPosition();
  }

  @override
  set size(int size) {
    super.size = size;
    (htmlRoot as web.HTMLElement).style.setProperty('--size', '$displaySize');
    applyPosition();
  }

  int get displaySize => size != 0 ? size : prefab.size;
  Point<int> get displaySizePoint => Point(displaySize, displaySize);
  Point<double> get topLeft =>
      position - Point(0.5 * displaySize, 0.5 * displaySize);

  Point<double> get positionScreenSpace =>
      board.grid.grid.gridToWorldSpace(position);

  Movable._({
    required this.board,
    required this.prefab,
    required this.id,
    required Point<double>? pos,
    required Iterable<int>? conds,
    bool createTooltip = true,
  }) : super(web.document.createElement('div') as dynamic) {
    final htmlElement = htmlRoot as web.HTMLElement;
    htmlElement.className = 'movable';
    
    _aura.className = 'aura';
    htmlElement.appendChild(_aura);
    
    final ring = web.document.createElement('div') as web.HTMLDivElement..className = 'ring';
    htmlElement.appendChild(ring);
    
    final img = web.document.createElement('div') as web.HTMLDivElement..className = 'img rotating';
    htmlElement.appendChild(img);
    
    final condsElement = web.document.createElement('div') as web.HTMLDivElement..className = 'conds';
    htmlElement.appendChild(condsElement);
    
    _barsRoot.className = 'bars';
    htmlElement.appendChild(_barsRoot);

    if (createTooltip) {
      final toast = web.document.createElement('span') as web.HTMLSpanElement..className = 'toast';
      htmlElement.appendChild(board.transform.registerInvZoom(
        toast as dynamic,
        scaleByCell: true,
      ) as web.Node);
    }

    applyImage();
    super.size = 0;

    if (pos != null) {
      position = pos;
      onPrefabUpdate();
    }
    if (conds != null) applyConditions(conds);

    _createBarComponents();
    angle = 0;
  }

  static Movable create({
    required Board board,
    required Prefab prefab,
    required int id,
    Iterable<int>? conds,
    Point<double>? pos,
  }) {
    if (prefab is EmptyPrefab) {
      return EmptyMovable._(
          board: board, prefab: prefab, id: id, pos: pos, conds: conds);
    }
    return Movable._(
        board: board, prefab: prefab, id: id, pos: pos, conds: conds);
  }

  @override
  List<StreamSubscription> initializeListeners() => [
        board.selected
            .observe(this)
            .listen((selected) => this.styleSelected = selected)
      ];

  TokenBarComponent getTokenBarComponent(TokenBar data) {
    return barInstances.firstWhere((bar) => bar.data == data);
  }

  void onRemoveTokenBar(TokenBar data) {
    final component = getTokenBarComponent(data);
    barInstances.remove(component);
  }

  TokenBarComponent createTokenBarComponent(TokenBar bar) {
    final component = TokenBarComponent(this, bar);
    barInstances.add(component);
    return component;
  }

  bool _doDisplayTokenBar(TokenBar bar) {
    switch (bar.visibility) {
      case TokenBarVisibility.VISIBLE_TO_ALL:
        return true;
      case TokenBarVisibility.VISIBLE_TO_OWNERS:
        return accessible;
      case TokenBarVisibility.HIDDEN:
        return board.session.isDM;
    }
  }

  void _createBarComponents() {
    barInstances.clear();

    for (final bar in bars) {
      if (_doDisplayTokenBar(bar)) {
        createTokenBarComponent(bar);
      }
    }
  }

  void applyPosition() {
    final pos = positionScreenSpace;
    board.updateSnapToGrid();

    (htmlRoot as web.HTMLElement).style
      ..setProperty('--x', '${pos.x}px')
      ..setProperty('--y', '${pos.y}px');
  }

  void setSizeWithGridSpecifics(int newSize) {
    final oldTopLeft = topLeft;
    size = newSize;

    if (board.grid.grid is SquareGrid) {
      position += oldTopLeft - topLeft;
    }
  }

  void updateTooltip() {
    htmlRoot.queryDom('.toast').textContent = displayName;
  }

  void onPrefabUpdate() {
    if (size == 0) {
      (htmlRoot as web.HTMLElement).style.setProperty('--size', '$displaySize');
      applyPosition();
    }
    (htmlRoot as web.HTMLElement).classList.toggle('accessible', accessible);
    updateTooltip();
  }

  void applyImage() {
    final img = prefab.image!.url;
    (htmlRoot.queryDom('.img') as web.HTMLElement).style.backgroundImage = 'url($img)';
  }

  void roundToGrid() {
    position =
        board.grid.grid.gridSnapCentered(position, displaySize).cast<double>();
  }

  bool toggleCondition(int id, [bool? add]) {
    var didAdd = false;
    if (add != null) {
      didAdd = add ? conds.add(id) : conds.remove(id);
    } else if (!conds.remove(id)) {
      conds.add(id);
      didAdd = true;
    }
    _applyConds();
    return didAdd;
  }

  void _applyConds() {
    var container = htmlRoot.queryDom('.conds');
    for (var i = 0; i < container.children.length; i++) {
      var child = container.children.item(i)!;
      child.remove();
    }

    for (var id in conds) {
      var cond = Condition.items[id]!;
      final span = web.document.createElement('span') as web.HTMLSpanElement;
      span.textContent = cond.name;
      final iconElement = icon(cond.icon);
      (iconElement as web.HTMLElement).appendChild(span);
      container.append(iconElement);
    }
  }

  void applyConditions(Iterable<int> conds) {
    this.conds.clear();
    this.conds.addAll(conds);
    _applyConds();
  }

  @override
  void dispose(InstanceList list) async {
    board.initiativeTracker.onRemove(this);

    (htmlRoot as web.HTMLElement).classList.add('animate-remove');
    await Future.delayed(Duration(milliseconds: 500));

    final toast = htmlRoot.querySelector('.toast');
    if (toast != null) {
      board.transform.unregisterInvZoom(toast);
    }

    super.dispose(list);
  }

  Map<String, dynamic> toCloneJson() => {
        'prefab': prefab.id,
        ...toJsonExcludeID(),
      };

  @override
  Map<String, dynamic> toJson() => {
        'movable': id,
        ...toJsonExcludeID(),
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);
    _createBarComponents();
    applyConditions(List<int>.from(json['conds'] ?? []));
    onPrefabUpdate();
  }

  void ping() {
    this.stylePinged = true;
    Future.delayed(const Duration(seconds: 10), () {
      this.stylePinged = false;
    });
  }

  void goTo() {
    this.stylePinged = true;
    board.animateTransformToToken(this);
    Future.delayed(const Duration(seconds: 10), () {
      this.stylePinged = false;
    });
  }
}

class EmptyMovable extends Movable {
  late web.HTMLSpanElement _labelSpan;

  @override
  set label(String label) {
    super.label = label;

    _labelSpan.textContent = label;
    var lines = label.split(' ');

    var length = lines.fold<int>(0, (len, line) => max(len, line.length));
    _labelSpan.style.setProperty('--length', '${length + 1}');
  }

  @override
  String get displayName {
    return label;
  }

  EmptyMovable._({
    required Board board,
    required EmptyPrefab prefab,
    required int id,
    required Point<double>? pos,
    required Iterable<int>? conds,
  }) : super._(
          board: board,
          prefab: prefab,
          id: id,
          pos: pos,
          conds: conds,
          createTooltip: false,
        ) {
    final htmlElement = htmlRoot as web.HTMLElement;
    htmlElement.classList.add('empty');
    _labelSpan = web.document.createElement('span') as web.HTMLSpanElement;
    htmlElement.appendChild(_labelSpan);
  }

  @override
  void applyImage() {}

  @override
  void updateTooltip() {}
}

class AngleArrow {
  static final web.HTMLElement container = queryDom('#angleArrow') as web.HTMLElement;
  static final web.HTMLElement angleCurrent = queryDom('#angleCurrent') as web.HTMLElement;

  bool _visible = false;
  bool get visible => _visible;
  set visible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    container.classList.toggle('show', visible);
  }

  Point<double> _origin = Point(0.0, 0.0);
  Point<double> get origin => _origin;
  set origin(Point<double> origin) {
    _origin = origin;
    container.style.setProperty('--x', '${origin.x}px');
    container.style.setProperty('--y', '${origin.y}px');
  }

  double _angle = 0;
  double get angle => _angle;
  set angle(double angle) {
    _angle = angle.undeviate();
    container.style.setProperty('--angle', '$_angle');
  }

  set sourceAngle(double sourceAngle) {
    angleCurrent.style.setProperty('--angle', '$sourceAngle');
  }

  set length(int length) {
    container.style.setProperty('--size', '$length');
  }

  static double _radToDegrees(double rad) {
    return rad * 180 / pi;
  }

  static double _degBetween(Point<double> a, Point<double> b) {
    final vector = a - b;
    final radAngleBetween = atan2(vector.x, -vector.y);
    return _radToDegrees(radAngleBetween);
  }

  void align(Board board, Point end, {bool updateSourceAngle = false}) {
    final activeMovable = board.activeMovable!;

    origin = board.grid.grid.gridToWorldSpace(activeMovable.position);
    length = activeMovable.displaySize;

    // Snap angle to closest "step" (square: 45°, hex: 30°)
    final degrees = _degBetween(origin, end.cast<double>());
    final degSnapStep = board.grid.measuringRuleset.snapTokenAngle(degrees);

    // Snap cursor position to closest cell
    final endSnapped = board.grid.grid.worldSnapCentered(end, 1).cast<double>();
    final degSnapCell = _degBetween(origin, endSnapped);

    // Check whether the closest step or the hovered cell center
    // is closest to the actual angle
    if ((degrees - degSnapStep).abs() < (degrees - degSnapCell).abs()) {
      angle = degSnapStep;
    } else {
      angle = degSnapCell;
    }

    if (updateSourceAngle) {
      sourceAngle = angle;
    } else {
      sourceAngle = activeMovable.angle;
    }
  }
}

final angleArrow = AngleArrow();
