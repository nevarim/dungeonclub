import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import '../../main.dart';
import '../html_helpers.dart';
import 'panel_overlay.dart';

final web.HTMLElement _panel = queryDom('#joinPanel');
final web.HTMLInputElement _sessionNameInput = _panel.queryDom('#sessionName');

final web.HTMLButtonElement _cancelButton = _panel.queryDom('button.close');
final web.HTMLButtonElement _joinButton = _panel.queryDom('button#join');
final web.HTMLElement _error = _panel.queryDom('#joinError');

Future<void> display(String gameId) async {
  overlayVisible = true;
  _joinButton.disabled = true;
  _error.textContent = '';

  _sessionNameInput
    ..value = web.window.localStorage.getItem('name') ?? ''
    ..select();

  _updateJoinButton();

  var closer = Completer();
  _sessionNameInput.addEventListener('input', (web.Event _) {
    _updateJoinButton();
  }.toJS);
  
  _joinButton.addEventListener('click', (web.Event _) {
    _cancelButton.disabled = true;
    _tryJoin(gameId).then((success) {
      if (success) closer.complete();
      _cancelButton.disabled = false;
    });
  }.toJS);
  
  _sessionNameInput.addEventListener('keydown', (web.Event ev) {
    if ((ev as web.KeyboardEvent).keyCode == 13 && !_joinButton.disabled) {
      _cancelButton.disabled = true;
      _tryJoin(gameId).then((success) {
        if (success) closer.complete();
        _cancelButton.disabled = false;
      });
    }
  }.toJS);
  
  _cancelButton.addEventListener('click', (web.Event event) {
    closer.complete();
  }.toJS);

  _panel.classList.add('show');

  await closer.future;
  _panel.classList.remove('show');
  overlayVisible = false;
}

Future<bool> _tryJoin(String gameId) async {
  web.window.localStorage.setItem('name', _sessionNameInput.value);
  _joinButton.disabled = true;
  _error
    ..className = ''
    ..textContent = 'Access requested...';

  var err = await user.joinSession(gameId, _sessionNameInput.value);

  if (err == null) return true;

  _joinButton.disabled = false;
  _error
    ..className = 'bad'
    ..textContent = err.message;
  return false;
}

void _updateJoinButton() {
  _joinButton.disabled = _sessionNameInput.value.isEmpty;
}
