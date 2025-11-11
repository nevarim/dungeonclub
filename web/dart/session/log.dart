import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';
import 'package:dungeonclub/dice_parser.dart';
import 'package:dungeonclub/iterable_extension.dart';

import '../../main.dart';
import '../communication.dart';
import '../html_helpers.dart';
import 'roll_dice.dart';
import 'session.dart';

const _historyLimit = 50;

RollCombo? _command;
late List<String> _history;
int _historyIndex = 0;
web.HTMLElement get logElem => queryDom('#log');
web.HTMLButtonElement get _chatOpenButton => queryDom('#chatOpen');
web.HTMLElement get _miniChat => queryDom('#miniChat');

bool get mobileShowLog => !logElem.classList.contains('hidden');
set mobileShowLog(bool v) => logElem.classList.toggle('hidden', !v);

final web.HTMLElement _messages = queryDom('#messages');
final web.HTMLButtonElement _sendButton = queryDom('#chatSend');
web.HTMLElement get _rollButtonContainer => queryDom('#chatRoller');
final web.HTMLButtonElement _rollButton = _rollButtonContainer.queryDom('#chatRoll');
final web.HTMLTextAreaElement _chat = queryDom('#chat textarea');

void _initializeEventListeners() {
  _sendButton.addEventListener('click', (web.Event _) {
    _submitChat();
  }.toJS);
  
  _rollButton.addEventListener('click', (web.Event _) {
    _submitChat(roll: true);
  }.toJS);
  
  _chat.addEventListener('keydown', (web.Event event) {
    final ev = event as web.KeyboardEvent;
    switch (ev.keyCode) {
      // Enter
      case 13:
        _submitChat(roll: _command != null);
        return ev.preventDefault();
      // Arrow Up
      case 38:
        _navigateHistory(-1);
        return ev.preventDefault();
      // Arrow Down
      case 40:
        _navigateHistory(1);
        return ev.preventDefault();
      // Tab
      case 9:
        if (_command != null) {
          rollPublic = !rollPublic;
        }
        return ev.preventDefault();
      default:
    }
  }.toJS);
  
  _chat.addEventListener('input', (web.Event _) {
    _updateSendButton();
  }.toJS);
}


void _navigateHistory(int step) {
  var lastIndex = _history.length - 1;
  if (_historyIndex == lastIndex) {
    _history[lastIndex] = _chat.value;
  }
  _historyIndex = min(max(_historyIndex + step, 0), _history.length - 1);
  _chat.value = _history[_historyIndex];
  _updateSendButton();
}

void _cleanupHistory() {
  var unique = <String>{};
  for (var i = _history.length - 1; i >= 0; i--) {
    var msg = _history[i];

    if (!unique.add(msg)) {
      _history.removeAt(i);
    }
  }

  _chat.value = '';
  _historyIndex = _history.length - 1;
  _navigateHistory(0);
}

void _updateSendButton() {
  var msg = _chat.value.trim();
  _sendButton.disabled = msg.isEmpty;

  if (DiceParser.isCommand(msg)) {
    _command = DiceParser.parse(msg);
    if (_command != null) {
      var cmdHtml = wrapAround(_command!.toCommandString(), 'b');
      _rollButton.queryDom('span').innerHTML = 'Roll $cmdHtml'.toJS;
    }
  } else {
    _command = null;
  }
  _rollButtonContainer.classList.toggle('disabled', _command == null);
}

void _submitChat({bool roll = false}) {
  var msg = _chat.value.trimRight();
  if (msg.isNotEmpty) {
    var pc = user.session!.charId;

    if (roll) {
      sendRollDice(_command!);
    } else {
      _performChat(pc, msg);
      socket.sendAction(GAME_CHAT, {'msg': msg, 'pc': pc});
    }

    if (_historyIndex < _history.length - 1) {
      _history.removeLast();
    }

    _history.add(msg);
    _history.add('');
    _cleanupHistory();
    _saveHistory();
  }
  if (isMobile) {
    _chat.focus();
  }
}

void _performChat(int? pcID, String msg) {
  final pc = user.session!.characters.find((e) => e.id == pcID);
  var name = pc?.name ?? 'GM';
  var mine = pcID == user.session!.charId;

  gameLog(
    (mine ? '' : '<span class="dice">$name</span> ') + msg,
    msgType: mine ? msgMine : msgOthers,
  );
}

void onChat(Map<String, dynamic> params) {
  String msg = params['msg'];
  int? id = params['pc'];
  _performChat(id, msg);
}

void _saveHistory() {
  while (_history.length - 1 > _historyLimit) {
    _history.removeAt(0);
  }

  web.window.localStorage.setItem('chat',
      jsonEncode(_history.sublist(0, _history.length - 1)));
}

void initGameLog() {
  _initializeEventListeners();
  
  _chat.classList.add('ready');
  _sendButton.classList.add('ready');

  var jsonList = jsonDecode(web.window.localStorage.getItem('chat') ?? '[]');
  _history = List<String>.from([...jsonList, '']);
  _cleanupHistory();

  if (isMobile) {
    _chat.rows = 1;
    _chatOpenButton.addEventListener('click', (web.Event _) {
      mobileShowLog = true;
      // Note: Touch event handling needs to be implemented differently in package:web
      // This is a simplified version - full touch handling may need additional work
      mobileShowLog = false;
    }.toJS);
  }
}

const msgMine = 0;
const msgOthers = 1;
const msgSystem = 2;
const msgBig = 3;

web.HTMLSpanElement gameLog(
  String s, {
  int msgType = msgSystem,
  bool mild = false,
  bool private = false,
}) {
  var line = web.document.createElement('span') as web.HTMLSpanElement;
  line.innerHTML = s.toJS;

  if (msgType == msgSystem) {
    line.className = 'system';
  } else if (msgType == msgBig) {
    line.className = 'big';
  } else if (msgType == msgMine) {
    line.className = 'mine';
  }

  if (mild) {
    line.classList.add('hidden');
  }
  if (private) {
    final iconElement = icon('eye-slash');
    iconElement.classList.add('with-tooltip');
    final tooltipSpan = web.document.createElement('span') as web.HTMLSpanElement;
    tooltipSpan.textContent = 'Private';
    iconElement.appendChild(tooltipSpan);
    line.appendChild(iconElement);
  }

  _messages.appendChild(line);
  _messages.scrollTop = _messages.scrollHeight;

  if (!mild) {
    Future.delayed(Duration(seconds: 8), () {
      line.animate([
        {'opacity': 1}.jsify(),
        {'opacity': 0.6}.jsify(),
      ].toJS, {'duration': 2000}.jsify()!);
      line.classList.add('hidden');
    });
  }

  if (isMobile) miniLog(s);

  return line;
}

void miniLog(String s) {
  if (mobileShowLog) return;
  var mini = web.document.createElement('span') as web.HTMLSpanElement;
  mini.className = 'tooltip';
  mini.innerHTML = s.toJS;

  _miniChat.appendChild(mini);

  mini.animate([
    {'opacity': 1}.jsify(),
    {'opacity': 0.9}.jsify(),
  ].toJS, {'duration': 1000}.jsify()!);

  Future.delayed(Duration(seconds: 4), () {
    mini.animate([
      {'opacity': 0.9}.jsify(),
      {'opacity': 0}.jsify(),
    ].toJS, {'duration': 3000}.jsify()!);
    Future.delayed(Duration(seconds: 3), () => mini.remove());
  });
}

void demoLog(String s) {
  gameLog(s, mild: true, msgType: msgBig);
}

void logInviteLink(Session session) async {
  if (session.isDemo) {
    demoLog('Welcome to your very own session!');
    demoLog(
        'Explore the editor, press all the buttons and make yourself at home.');
    return;
  }

  final clipboard = web.window.navigator.clipboard;
  final isClipboardSupported = clipboard != null;

  final line = gameLog(
    'Hello, GM!<br>Players can join at <b>${session.inviteLink}</b>.',
    msgType: msgBig,
  );
  line.classList.add('clickable');

  final tooltip = web.document.createElement('span') as web.HTMLSpanElement;
  tooltip.textContent = isClipboardSupported
      ? 'Copied to Clipboard!'
      : 'Copy this link with Ctrl+C';

  line.addEventListener('mousedown', (web.Event _) {
    if (isClipboardSupported) {
      // Copy invite link to clipboard
      clipboard.writeText(session.inviteLink);
    }

    line.appendChild(tooltip);
  }.toJS);
  
  line.addEventListener('mouseleave', (web.Event _) {
    Future.delayed(Duration(milliseconds: 500)).then((_) {
      tooltip.remove();
    });
  }.toJS);

  if (isClipboardSupported) {
    line.classList.add('no-select');
  } else {
    // Select invite link on click
    line.addEventListener('mouseup', (web.Event _) {
      Future.delayed(Duration(milliseconds: 100)).then((_) {
        final inviteTextNode = line.queryDom('b');
        web.window.getSelection()!.selectAllChildren(inviteTextNode);

        // Note: Complex event handling for Ctrl+C detection needs additional implementation
        // This is a simplified version
        Future.delayed(Duration(milliseconds: 100)).then((_) {
          web.window.getSelection()!.empty();
        });
      });
    }.toJS);
  }
}
