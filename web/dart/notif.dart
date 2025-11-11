import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'html_helpers.dart';

class HtmlNotification {
  static final _parent = queryDom('#notifications') as web.HTMLElement;
  final web.HTMLElement e;

  HtmlNotification(String msg)
      : e = web.document.createElement('div') as web.HTMLElement {
    e.className = 'notification';
    var span = web.document.createElement('span') as web.HTMLElement;
    span.innerHTML = msg.toJS;
    e.appendChild(span);
  }

  void display() {
    var closeBtn = iconButton('times') as web.HTMLElement;
    closeBtn.addEventListener('click', ((web.Event _) => remove()).toJS);
    e.appendChild(closeBtn);
    _parent.appendChild(e);
  }

  Future<bool> prompt() {
    var completer = Completer<bool>();
    var isCompleted = false;
    
    var checkBtn = iconButton('check', className: 'good') as web.HTMLElement;
    checkBtn.addEventListener('click', ((web.Event _) {
      if (!isCompleted) {
        isCompleted = true;
        completer.complete(true);
        remove();
      }
    }).toJS);
    e.appendChild(checkBtn);

    var timesBtn = iconButton('times', className: 'bad') as web.HTMLElement;
    timesBtn.addEventListener('click', ((web.Event _) {
      if (!isCompleted) {
        isCompleted = true;
        completer.complete(false);
        remove();
      }
    }).toJS);
    e.appendChild(timesBtn);

    _parent.appendChild(e);
    return completer.future;
  }

  void remove() {
    e.parentNode?.removeChild(e);
  }
}
