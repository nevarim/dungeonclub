import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';

import '../../main.dart';
import '../communication.dart';
import '../html_helpers.dart';
import 'panel_overlay.dart';

const pwLengthMin = 7;

final CodePanel registerPanel =
    CodePanel('#registerPanel', ACCOUNT_REGISTER, ACCOUNT_ACTIVATE);

final CodePanel resetPanel = CodePanel(
    '#resetPanel', ACCOUNT_RESET_PASSWORD, ACCOUNT_RESET_PASSWORD_ACTIVATE);

class CodePanel {
  final web.HTMLElement _panel;

  late web.HTMLElement _sectionRegister;
  late web.HTMLElement _sectionActivate;

  late web.HTMLInputElement _emailInput;

  late web.HTMLInputElement _passwordInput;

  late web.HTMLInputElement _confirmInput;

  late web.HTMLInputElement _codeInput;
  late web.HTMLSpanElement _emailReader;

  late web.HTMLButtonElement _registerButton;
  late web.HTMLButtonElement _activateButton;

  late web.HTMLElement _errorText1;
  late web.HTMLElement _errorText2;

  late web.HTMLButtonElement _cancelButton;
  final web.HTMLButtonElement _loginButton = queryDom('button#login') as web.HTMLButtonElement;

  final String actionSend;
  final String actionVerify;

  CodePanel(String panelId, this.actionSend, this.actionVerify)
      : _panel = queryDom(panelId) as web.HTMLElement {
    _sectionRegister = _panel.querySelector('.credentials') as web.HTMLElement;
    _sectionActivate = _panel.querySelector('.activate') as web.HTMLElement;

    _emailInput = _panel.querySelector('.email') as web.HTMLInputElement
      ..addEventListener('input', ((web.Event event) => _updateCreateButton()).toJS);

    _passwordInput = _panel.querySelector('.password') as web.HTMLInputElement
      ..addEventListener('input', ((web.Event event) => _updateCreateButton()).toJS);

    _confirmInput = _panel.querySelector('.confirm') as web.HTMLInputElement
      ..addEventListener('input', ((web.Event event) => _updateCreateButton()).toJS);

    _codeInput = _panel.querySelector('.code') as web.HTMLInputElement
      ..addEventListener('input', ((web.Event _) {
        _activateButton.disabled = _codeInput.value.length != 5;
      }).toJS);
    _emailReader = _panel.querySelector('.email-reader') as web.HTMLSpanElement;

    _registerButton = _panel.querySelector('.send') as web.HTMLButtonElement;
    _activateButton = _panel.querySelector('.activate-code') as web.HTMLButtonElement;

    _errorText1 = _sectionRegister.querySelector('p.bad') as web.HTMLElement;
    _errorText2 = _sectionActivate.querySelector('p.bad') as web.HTMLElement;

    _cancelButton = _panel.querySelector('button.close') as web.HTMLButtonElement;
  }

  Future<void> display() async {
    overlayVisible = true;
    _loginButton.classList.add('disabled');
    _emailInput.value = '';
    _passwordInput.value = '';
    _confirmInput.value = '';
    _errorText1.textContent = '';
    _errorText2.textContent = '';
    _updateCreateButton();

    var closer = Completer();
    bool isCompleted = false;
    
    void registerHandler(web.Event event) async {
      event.preventDefault();
      _registerButton.disabled = true;

      var moveOn = await socket.request(actionSend, {
        'email': _emailInput.value,
        'password': _passwordInput.value,
      });

      // Yes. I actually DO have to use "== true"!
      // moveOn can be a string. Checkmate.
      if (moveOn == true) {
        _emailReader.textContent = _emailInput.value;
        _activateButton.disabled = true;
        _setSection(_sectionActivate);
        _codeInput
          ..value = ''
          ..focus();
        blockPageExit = true;
      } else {
        _errorText1.textContent = moveOn;
        _registerButton.disabled = false;
      }
    }
    
    void activateHandler(web.Event event) async {
      event.preventDefault();
      _errorText2.textContent = '';
      var account = await socket.request(actionVerify, {
        'code': _codeInput.value,
      });
      if (account == null) {
        _errorText2.textContent = 'Invalid code!';
        return;
      }

      user.onActivate(account);
      if (!isCompleted) {
        isCompleted = true;
        closer.complete();
      }
    }
    
    void cancelHandler(web.Event event) {
      event.preventDefault();
      if (!isCompleted) {
        isCompleted = true;
        closer.complete();
      }
    }
    
    _registerButton.addEventListener('click', registerHandler.toJS);
    _activateButton.addEventListener('click', activateHandler.toJS);
    _cancelButton.addEventListener('click', cancelHandler.toJS);

    _setSection(_sectionRegister);

    _panel.classList.add('show');

    await closer.future;
    _panel.classList.remove('show');
    _loginButton.classList.remove('disabled');
    
    _registerButton.removeEventListener('click', registerHandler.toJS);
    _activateButton.removeEventListener('click', activateHandler.toJS);
    _cancelButton.removeEventListener('click', cancelHandler.toJS);
    
    overlayVisible = false;
    blockPageExit = false;
  }

  void _setSection(web.HTMLElement section) {
    final elements = _panel.querySelectorAll('section.show');
    for (int i = 0; i < elements.length; i++) {
      (elements.item(i) as web.HTMLElement).classList.remove('show');
    }
    section.classList.add('show');
  }

  bool isValidPassword(web.HTMLInputElement pw, web.HTMLInputElement confirm) =>
      pw.value.length >= pwLengthMin && pw.value == confirm.value;

  void _updateCreateButton() {
    _registerButton.disabled = !_emailInput.value.contains('@') ||
        !isValidPassword(_passwordInput, _confirmInput);
  }
}
