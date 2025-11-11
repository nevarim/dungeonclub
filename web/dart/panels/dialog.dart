import 'dart:async';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

import '../html_helpers.dart';
import 'panel_overlay.dart';

final web.HTMLElement _overlay = queryDom('#overlay');

class Dialog<T> {
  final web.HTMLElement _e;
  final _completer = Completer<T>();
  bool _isCompleted = false;
  web.HTMLInputElement? _input;
  late web.HTMLButtonElement _okButton;

  Dialog(
    String title, {
    T Function()? onClose,
    String okText = 'OK',
    String? okClass,
  }) : _e = web.document.createElement('div') as web.HTMLDivElement..className = 'panel dialog' {
    final closeButton = iconButton('times')
      ..className = 'close'
      ..addEventListener('click', ((web.Event event) {
        if (!_isCompleted) {
          _isCompleted = true;
          final result = onClose == null ? null : onClose();
          _completer.complete(result);
        }
      }).toJS);

    _e
      ..append(web.document.createElement('h2') as web.HTMLHeadingElement..textContent = title)
      ..append(closeButton)
      ..append(_okButton = web.document.createElement('button') as web.HTMLButtonElement
        ..className = 'big' + (okClass != null ? ' $okClass' : '')
        ..textContent = okText
        ..addEventListener('click', ((web.Event event) {
          if (!_isCompleted) {
            _isCompleted = true;
            _completer.complete((_input?.value ?? true) as T);
          }
        }).toJS));
  }

  Dialog addParagraph(String html) {
    _e.insertBefore(web.document.createElement('p') as web.HTMLParagraphElement..innerHTML = html.toJS, _okButton);
    return this;
  }

  Dialog withInput({String type = 'text', String? placeholder}) {
    _input = web.document.createElement('input') as web.HTMLInputElement..type = type
      ..addEventListener('keydown', ((web.Event event) {
        if ((event as web.KeyboardEvent).code == 'Enter' && !_isCompleted) {
          _isCompleted = true;
          _completer.complete(_input!.value as T);
        }
      }).toJS);

    if (placeholder != null) {
      _input!.placeholder = placeholder;
    }

    _e.insertBefore(_input!, _okButton);
    return this;
  }

  void close() {
    _e.className = _e.className.replaceAll(' show', '').replaceAll('show', '');
    unawaited(
        Future.delayed(Duration(seconds: 1)).then((value) => _e.remove()));
    overlayVisible = false;
  }

  Future<T> display() async {
    overlayVisible = true;
    _overlay.append(_e);
    _e.innerText; // Trigger reflow
    _e.className += ' show';
    (_input ?? _okButton).focus();

    var result = await _completer.future;
    close();
    return result;
  }
}

class ConstantDialog {
  final web.HTMLElement _e;

  ConstantDialog(String title) : _e = web.document.createElement('div') as web.HTMLDivElement..className = 'panel dialog' {
    _e.append(web.document.createElement('h2') as web.HTMLHeadingElement..textContent = title);
  }

  void addParagraph(String html) {
    _e.append(web.document.createElement('p') as web.HTMLParagraphElement..innerHTML = html.toJS);
  }

  void append(web.Element element) {
    _e.append(element);
  }

  void display() {
    overlayVisible = true;
    _overlay.append(_e);
    _e.innerText; // Trigger reflow
    _e.className += ' show';
  }

  void close() async {
    _e.className = _e.className.replaceAll(' show', '').replaceAll('show', '');
    overlayVisible = false;
    await Future.delayed(Duration(seconds: 1));
    _e.remove();
  }
}
