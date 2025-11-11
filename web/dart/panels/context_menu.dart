import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import '../../main.dart';
import '../html_helpers.dart';

final _e = queryDom('#contextMenu');

class ContextMenu {
  ContextMenu() {
    while (_e.children.length > 0) {
      _e.children.item(0)!.remove();
    }
  }

  int addButton(String label, String icon, [String? className]) {
    _e.append(iconButton(icon, label: label, className: className));
    return _e.children.length - 1;
  }

  bool _prefer(web.EventTarget e) {
    return e is web.HTMLButtonElement ||
        (e is web.HTMLElement && e.classList.contains('with-tooltip'));
  }

  Future<int?> display(web.MouseEvent event, [web.HTMLElement? hovered]) async {
    hovered ??=
        event.composedPath().toDart.cast<web.EventTarget>().firstWhere(_prefer, orElse: () => event.target!) as web.HTMLElement;
    var px = event.pageX;
    var py = event.pageY;

    var startsHovered = true;
    var bottom = web.window.innerHeight - py;
    if (bottom > 120) {
      (_e as web.HTMLElement).style.top = '${py - 12}px';
      (_e as web.HTMLElement).style.bottom = 'auto';
    } else {
      (_e as web.HTMLElement).style.bottom = '12px';
      (_e as web.HTMLElement).style.top = 'auto';
    }

    var right = web.window.innerWidth - px;
    if (right > 180) {
      (_e as web.HTMLElement).style.left = '${px}px';
      (_e as web.HTMLElement).style.right = 'auto';
    } else {
      startsHovered = false;
      (_e as web.HTMLElement).style.right = '12px';
      (_e as web.HTMLElement).style.left = 'auto';
    }

    (_e as web.HTMLElement).classList.add('show');
    hovered.classList.add('hovered');

    late web.Event ev;
    if (isMobile) {
      final completer = Completer<web.Event>();
      var isCompleted = false;
      void handler(web.Event e) {
        if (!isCompleted) {
          isCompleted = true;
          completer.complete(e);
          web.window.removeEventListener('touchstart', handler.toJS);
        }
      }
      web.window.addEventListener('touchstart', handler.toJS);
      ev = await completer.future;
    } else {
       final completer = Completer<web.Event>();
       var mouseUpCount = 0;
       var isCompleted = false;
       
       late void Function(web.Event) mouseLeaveHandler;
       late void Function(web.Event) mouseUpHandler;
       
       mouseLeaveHandler = (web.Event e) {
          if (!isCompleted) {
            isCompleted = true;
            completer.complete(e);
            (_e as web.HTMLElement).removeEventListener('mouseleave', mouseLeaveHandler.toJS);
            (_e as web.HTMLElement).removeEventListener('mouseup', mouseUpHandler.toJS);
          }
        };
        
        mouseUpHandler = (web.Event e) {
          if (e.target != _e) {
            mouseUpCount++;
            if (mouseUpCount > (startsHovered ? 0 : 1) && !isCompleted) {
              isCompleted = true;
              completer.complete(e);
              (_e as web.HTMLElement).removeEventListener('mouseleave', mouseLeaveHandler.toJS);
              (_e as web.HTMLElement).removeEventListener('mouseup', mouseUpHandler.toJS);
            }
          }
        };
       
       (_e as web.HTMLElement).addEventListener('mouseleave', mouseLeaveHandler.toJS);
       (_e as web.HTMLElement).addEventListener('mouseup', mouseUpHandler.toJS);
       ev = await completer.future;
     }

    (_e as web.HTMLElement).classList.remove('show');
    hovered.classList.remove('hovered');

    if (!isMobile && ev.type == 'mouseleave') return null;

    for (var i = 0; i < _e.children.length; i++) {
      if (ev.composedPath().toDart.contains(_e.children.item(i))) {
        return i;
      }
    }

    return null;
  }
}
