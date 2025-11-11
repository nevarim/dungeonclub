import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import '../html_helpers.dart';

web.HTMLElement _overlay = queryDom('#overlay');
int _stack = 0;

set overlayVisible(bool visible) {
  if (visible) {
    if (_stack == 0) {
      _overlay.classList.add('block');
    }

    _stack++;
  } else {
    _stack--;

    if (_stack == 0) {
      _overlay.classList.remove('block');
    }
  }
}

int _blockStack = 0;
StreamSubscription? _pageExitSub;

void _initPageExitHandler() {
  _pageExitSub ??= (() {
    final controller = StreamController<web.BeforeUnloadEvent>.broadcast();
    web.window.addEventListener('beforeunload', ((web.BeforeUnloadEvent ev) {
      controller.add(ev);
    }).toJS);
    return controller.stream;
  })().listen((ev) {
    if (_blockStack > 0) {
      ev.preventDefault();
      ev.returnValue = '';
    }
  });
}

set blockPageExit(bool block) {
  _initPageExitHandler(); // Initialize unload handler
  if (block) {
    _blockStack++;
  } else if (_blockStack > 0) {
    _blockStack--;
  }
}
