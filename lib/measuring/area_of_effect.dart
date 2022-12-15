import 'dart:math';

import 'package:dungeonclub/measuring/ruleset.dart';
import 'package:grid/grid.dart';
import 'package:meta/meta.dart';

abstract class AreaOfEffectPainter with ShapeMaker {
  void addShape(Shape shape);
  void removeShape(Shape shape);
}

mixin ShapeMaker {
  Circle circle();
  Rect rect();
}

class ShapeGroup with ShapeMaker {
  final ShapeMaker _maker;
  final shapes = <Shape>[];

  ShapeGroup(ShapeMaker maker) : _maker = maker;

  Shape _wrap(Shape shape) {
    shapes.add(shape);
    return shape;
  }

  @override
  Circle circle() => _wrap(_maker.circle());
  @override
  Rect rect() => _wrap(_maker.rect());
}

abstract class AreaOfEffectTemplate<S extends _Supports> {
  S _ruleset;
  S get ruleset => _ruleset;

  Grid _grid;
  Grid get grid => _grid;

  ShapeGroup _group;

  void create(
    Point<double> origin,
    AreaOfEffectPainter painter,
    S ruleset,
    Grid grid,
  ) {
    _ruleset = ruleset;
    _grid = grid;
    _group = ShapeGroup(painter);
    initialize(origin, _group);
    onMove(origin, 0);

    for (var shape in _group.shapes) {
      painter.addShape(shape);
    }
  }

  void dispose(AreaOfEffectPainter painter) {
    for (var shape in _group.shapes) {
      painter.removeShape(shape);
    }
  }

  Set<Point<int>> getAffectedTiles();

  @protected
  void initialize(Point<double> origin, ShapeMaker maker);
  void onMove(Point<double> position, double distance);
}

class SphereAreaOfEffect<G extends Grid>
    extends AreaOfEffectTemplate<SupportsSphere<G>> {
  @override
  G get grid => _grid;
  Circle _outline;

  Point<double> get center => _outline.center;
  double get radius => _outline.radius;

  @override
  void initialize(Point<double> origin, ShapeMaker maker) {
    _outline = maker.circle()..center = origin;
  }

  @override
  void onMove(Point<double> position, double distance) {
    _outline.radius = distance;
  }

  @override
  Set<Point<int>> getAffectedTiles() => ruleset.getTilesAffectedBySphere(this);
}

abstract class CubeAreaOfEffect<G extends Grid>
    extends AreaOfEffectTemplate<SupportsCube<G>> {
  @override
  G get grid => _grid;

  @override
  Set<Point<int>> getAffectedTiles() => ruleset.getTilesAffectedByCube(this);
}

class SquareCubeAreaOfEffect extends CubeAreaOfEffect {
  final bool useDistance;
  Rect _rect;

  Point<double> _from;
  Point<double> _to;

  Point<double> get boundsMin =>
      Point(min(_from.x, _to.x), min(_from.y, _to.y));
  Point<double> get boundsMax =>
      Point(max(_from.x, _to.x), max(_from.y, _to.y));

  SquareCubeAreaOfEffect({@required this.useDistance});

  void _updateRect() {
    final bMin = boundsMin;
    _rect
      ..position = bMin
      ..size = boundsMax - bMin;
  }

  @override
  void initialize(Point<double> origin, ShapeMaker maker) {
    _rect = maker.rect();
    _from = _to = origin;
    _updateRect();
  }

  @override
  void onMove(Point<double> position, double distance) {
    final v = position - _from;
    final size = useDistance ? distance : max(v.x.abs(), v.y.abs());

    _to = _from + Point(v.x.sign * size, v.y.sign * size);
    _updateRect();
  }
}

class HexCubeAreaOfEffect extends CubeAreaOfEffect<HexagonalGrid> {
  @override
  void initialize(Point<double> origin, ShapeMaker maker) {
    // TODO
  }

  @override
  void onMove(Point<double> position, double distance) {
    // TODO
  }
}

mixin _Supports<G extends Grid> on MeasuringRuleset<G> {}

mixin SupportsSphere<G extends Grid> implements _Supports<G> {
  SphereAreaOfEffect<G> aoeSphere(
    Point<double> origin,
    AreaOfEffectPainter painter,
    G grid,
  ) =>
      SphereAreaOfEffect()..create(origin, painter, this, grid);

  Set<Point<int>> getTilesAffectedBySphere(SphereAreaOfEffect<G> aoe);
}

mixin SupportsCube<G extends Grid> implements _Supports<G> {
  CubeAreaOfEffect aoeCube(
    Point<double> origin,
    AreaOfEffectPainter painter,
    G grid,
  ) =>
      makeInstance()..create(origin, painter, this, grid);

  CubeAreaOfEffect makeInstance();
  Set<Point<int>> getTilesAffectedByCube(CubeAreaOfEffect aoe);
}

mixin Shape {}

mixin Circle implements Shape {
  Point<double> center;
  double radius;
}

mixin Rect implements Shape {
  Point position;
  Point size;
}
