import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/environment.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';

import 'dart/communication.dart';
import 'dart/home.dart' as home;
import 'dart/panels/code_panel.dart';
import 'dart/panels/join_session.dart' as join_session;
import 'dart/panels/feedback.dart' as feedback;
import 'dart/session/demo.dart';
import 'dart/user.dart';

final bool isMobile = web.window.screen.width < 800;
final _interaction = Completer();
Future get requireFirstInteraction => _interaction.future;

final user = User();
const appName = 'Dungeon Club';
late String _homeUrl;
String get homeUrl => _homeUrl;

void main() async {
  web.document.title = appName;
  _listenToCssReload();
  applyEnvironmentStyling();
  applyMobileStyling();

  web.document.querySelector('#signup')!.addEventListener('click', (web.Event _) {
    registerPanel.display();
  }.toJS);
  web.document.querySelector('#feedback')!.addEventListener('click', (web.Event _) {
    if (!Environment.isCompiled) {
      feedback.display();
    } else {
      (web.document.querySelector('#discordLink')! as web.HTMLAnchorElement).click();
    }
  }.toJS);

  web.document.querySelector('button#save')!.addEventListener('click', (web.Event _) {
    socket.send('{"action":"manualSave"}');
  }.toJS);

  web.document.addEventListener('drop', (web.Event e) {
    e.preventDefault();
  }.toJS);
  web.document.addEventListener('dragover', (web.Event e) {
    e.preventDefault();
  }.toJS);
  web.window.addEventListener('popstate', (web.Event _) {
    web.window.location.reload();
  }.toJS);
  unawaited(Future(() => web.document.addEventListener('mousedown', (web.Event _) {
    _interaction.complete();
  }.toJS)));

  _homeUrl = dirname(web.window.location.href);
  await home.init();
  processUrlPath();
}

void applyMobileStyling() {
  if (isMobile) {
    // Remove text from icon buttons
    final iconButtons = web.document.querySelectorAll('#playerControls .icon');
    for (int i = 0; i < iconButtons.length; i++) {
      final btn = iconButtons.item(i)!;
      for (int j = 0; j < btn.childNodes.length; j++) {
        final node = btn.childNodes.item(j)!;
        if (node.nodeType == web.Node.TEXT_NODE) {
          node.parentNode?.removeChild(node);
        }
      }
    }
  }

  // Register a custom .hovered selector to use instead of :hover
  final hoverButtons = web.document.querySelectorAll('button:not(no-hover)');
  for (int i = 0; i < hoverButtons.length; i++) {
    final e = hoverButtons.item(i)! as web.HTMLButtonElement;
    if (isMobile) {
      e.addEventListener('touchstart', (web.Event _) {
        e.classList.add('hovered');
        // Wait for touch outside element
        e.classList.remove('hovered');
      }.toJS);
    } else {
      e.addEventListener('mouseenter', (web.Event _) {
        e.classList.add('hovered');
        // Wait for mouse leave
        e.classList.remove('hovered');
      }.toJS);
    }
  }
}

void applyEnvironmentStyling() {
  if (Environment.isCompiled) {
    // Apply environment variables from backend
    // TODO: Fix globalContext access for web package
    // final embeddedConfig = globalContext.getProperty('ENV'.toJS);
    // Environment.applyConfig(embeddedConfig);

    // Apply "self-hosted" changes
    web.document.querySelector('#privacy')!.remove();
    var time = DateTime.fromMillisecondsSinceEpoch(Environment.buildTimestamp);
    var buildTime = DateFormat('y-MM-dd').format(time);
    web.document.querySelector('#hostInfo')!.innerHTML = 'Self-Hosted (Build $buildTime)'.toJS;
  }

  web.document.body!.classList.toggle('no-music', !Environment.enableMusic);
}

void processUrlPath() {
  if (web.window.location.href.contains('game')) {
    var gameId = web.window.location.pathname;

    if (gameId.contains('game/')) {
      gameId = gameId.substring(gameId.indexOf('game/') + 5);
      _homeUrl = dirname(_homeUrl);
    } else {
      gameId = web.window.location.search;
      gameId = gameId.substring(gameId.indexOf('?game=') + 6);

      if (gameId.contains('&')) {
        gameId = gameId.substring(0, gameId.indexOf('&'));
      }
    }

    if (gameId.length >= 3) {
      if (user.registered && user.account!.games.any((g) => g.id == gameId)) {
        user.joinSession(gameId);
      } else if (gameId == DemoSession.demoId) {
        user.joinDemo();
      } else {
        join_session.display(gameId);
      }
    }
  }

  final titleLinks = web.document.querySelectorAll('a.title');
  for (int i = 0; i < titleLinks.length; i++) {
    (titleLinks.item(i)! as web.HTMLAnchorElement).href = _homeUrl;
  }
}

void _listenToCssReload() {
  web.document.addEventListener('keypress', (web.Event event) {
    final keyEvent = event as web.KeyboardEvent;
    if (keyEvent.target is web.HTMLInputElement) return;
    if (keyEvent.key == 'R') {
      final links = web.document.querySelectorAll('link');
      for (int i = 0; i < links.length; i++) {
        final link = links.item(i)! as web.HTMLLinkElement;
        link.href += '';
      }
    }
  }.toJS);
}
