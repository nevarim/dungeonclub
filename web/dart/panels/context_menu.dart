import 'dart:async';
import 'dart:html';

import '../font_awesome.dart';

final _e = querySelector('#contextMenu');

class ContextMenu {
  ContextMenu() {
    _e.children.clear();
  }

  int addButton(String label, String icon, [String className]) {
    _e.append(iconButton(icon, label: label, className: className));
    return _e.children.length - 1;
  }

  Future<int> display(MouseEvent event) async {
    var p = event.page;

    var bottom = window.innerHeight - p.y;
    if (bottom > 120) {
      _e.style
        ..top = '${p.y - 12}px'
        ..bottom = 'auto';
    } else {
      _e.style
        ..bottom = '12px'
        ..top = 'auto';
    }

    _e.style.left = '${p.x}px';
    _e.classes.add('show');

    var ev = await Future.any([
      _e.onMouseLeave.first,
      _e.onClick.first,
    ]);

    _e.classes.remove('show');

    if (ev.type == 'mouseleave' || ev.target == _e) return null;

    for (var i = 0; i < _e.children.length; i++) {
      if (ev.path.contains(_e.children[i])) {
        return i;
      }
    }

    return null;
  }
}