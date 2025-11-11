import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';

import '../../main.dart';
import '../communication.dart';
import '../html_helpers.dart';
import 'panel_overlay.dart';

final web.HTMLElement _panel = queryDom('#feedbackPanel') as web.HTMLElement;
final web.HTMLSelectElement _select = _panel.querySelector('select') as web.HTMLSelectElement;
final web.HTMLTextAreaElement _content = _panel.querySelector('textarea') as web.HTMLTextAreaElement;
final web.HTMLButtonElement _cancelButton = _panel.querySelector('button.close') as web.HTMLButtonElement;
final web.HTMLButtonElement _sendButton = _panel.querySelector('#sendFeedback') as web.HTMLButtonElement;

Future<void> display() async {
  overlayVisible = true;

  // Set up content input listener
  _content.addEventListener('input', ((web.Event _) => _updateSendButton()).toJS);

  for (int i = 0; i < _select.options.length; i++) {
    final opt = _select.options.item(i) as web.HTMLOptionElement;
    if (opt.value == 'account') opt.disabled = !user.registered;
  }

  _content.select();
  _updateSendButton();

  var closer = Completer();
  bool isCompleted = false;
  
  void sendHandler(web.Event event) async {
    event.preventDefault();
    _cancelButton.disabled = true;
    if (await _trySend()) {
      if (!isCompleted) {
        isCompleted = true;
        closer.complete();
      }
    }
    _cancelButton.disabled = false;
  }
  
  void cancelHandler(web.Event event) {
    event.preventDefault();
    if (!isCompleted) {
      isCompleted = true;
      closer.complete();
    }
  }
  
  _sendButton.addEventListener('click', sendHandler.toJS);
  _cancelButton.addEventListener('click', cancelHandler.toJS);

  _panel.classList.add('show');

  await closer.future;
  _panel.classList.remove('show');
  
  _sendButton.removeEventListener('click', sendHandler.toJS);
  _cancelButton.removeEventListener('click', cancelHandler.toJS);
  
  overlayVisible = false;
}

Future<bool> _trySend() async {
  _sendButton.disabled = true;

  var sent = await socket.request(FEEDBACK, {
    'type': _select.value,
    'content': _content.value,
  });

  if (sent == true) {
    _content.value = '';
    return true;
  }

  _sendButton.disabled = false;
  return false;
}

void _updateSendButton() {
  _sendButton.disabled = _content.value.length < 20;
}
