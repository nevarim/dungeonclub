import 'dart:math';
import 'package:web/web.dart' as web;

import 'painter.dart';

class PaintTransform {
  final Point<double> offset;
  final Point<double> sizing;

  PaintTransform(this.offset, this.sizing);

  Point<double> translate(Point p) {
    return Point<double>(
      offset.x + p.x * sizing.x,
      offset.y + p.y * sizing.y,
    );
  }
}

class SvgShapePainter extends ShapePainter {
  final web.SVGGElement rootElement;
  final PaintTransform transform;

  SvgShapePainter(this.rootElement, this.transform);

  @override
  void addShape(covariant SvgShape e) {
    rootElement.append(e.element);
  }

  @override
  void removeShape(covariant SvgShape e) {
    rootElement.append(e.element);
  }

  @override
  Circle circle() => SvgCircle(transform);

  @override
  Rect rect() => SvgRect(transform);

  @override
  Polygon polygon() => SvgPolygon(transform);
}

extension SvgAttributeHelper on web.SVGElement {
  void attrPx(String name, dynamic value) {
    setAttribute(name, '${value}px');
  }

  void attrPoint(String nameX, String nameY, Point point) {
    attrPx(nameX, point.x);
    attrPx(nameY, point.y);
  }
}

abstract class SvgShape<E extends web.SVGElement> with Shape {
  final PaintTransform transform;
  final E element;

  SvgShape(this.transform, this.element) {
    element.classList.add('no-fill');
  }
}

class SvgCircle extends SvgShape<web.SVGCircleElement> with Circle {
  SvgCircle(PaintTransform transform) : super(transform, web.SVGCircleElement());

  @override
  set radius(double r) {
    super.radius = r;
    element.attrPx('r', r * transform.sizing.x);
  }

  @override
  set center(Point<double> p) {
    super.center = p;
    final normalized = transform.translate(p);
    element.attrPoint('cx', 'cy', normalized);
  }
}

class SvgRect extends SvgShape<web.SVGRectElement> with Rect {
  SvgRect(PaintTransform transform) : super(transform, web.SVGRectElement());

  @override
  set position(Point p) {
    super.position = p;
    final normalized = transform.translate(p);
    element.attrPoint('x', 'y', normalized);
  }

  @override
  set size(Point s) {
    super.position = s;
    final scale = transform.sizing;
    final normalized = Point(s.x * scale.x, s.y * scale.y);
    element.attrPoint('width', 'height', normalized);
  }
}

class SvgPolygon extends SvgShape<web.SVGPolygonElement> with Polygon {
  SvgPolygon(PaintTransform transform) : super(transform, web.SVGPolygonElement());

  @override
  void handlePointsChanged() {
    final svgPointString = points.map((point) {
      final p = transform.translate(point);
      return '${p.x},${p.y}';
    }).join(' ');

    element.setAttribute('points', svgPointString);
  }
}
