import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import '../main.dart';
import 'changelog.dart';
import 'html_helpers.dart';
import 'game.dart';
import 'icon_wall.dart';
import 'notif.dart';
import 'panels/code_panel.dart';
import 'panels/edit_game.dart' as edit_game;
import 'panels/join_session.dart' as join_session;
import 'section_page.dart';

final web.HTMLElement _gamesContainer = queryDom('#gamesContainer');
final web.HTMLButtonElement _createGameButton = queryDom('#create');
final web.HTMLElement _loginTab = queryDom('#loginTab');
final web.HTMLButtonElement _logout = queryDom('#logOut');
web.HTMLElement get _enterDemoButton => queryDom('#enterDemo');

void _initLogoutHandler() {
  _logout.addEventListener('click', ((web.Event _) {
    web.window.localStorage.removeItem('token');
    web.window.location.reload();
  }).toJS);
}

final iconWall = IconWall(queryDom('#iconWall'));

Future<void> init() {
  iconWall.spawnParticles();
  changelog.fetch();
  _initLogoutHandler();

  _enterDemoButton.addEventListener('click', ((web.Event _) {
    user.joinDemo();
  }).toJS);

  _createGameButton.addEventListener('click', ((web.Event event) {
    if (!user.registered) {
      HtmlNotification('No permissions to create a new game!').display();
      return;
    }

    if (_gamesContainer.children.length > user.campaignsPerAccount) {
      HtmlNotification(
              'Limit of ${user.campaignsPerAccount} campaigns reached.')
          .display();
      return;
    }

    user.account!.createNewGame().then((game) {
      if (game != null) {
        _addEnteredGame(game);
      }
    });
  }).toJS);

  _displayLocalEnteredGames();

  showPage('home');
  return _initLogInTab();
}

Future<bool> _initLogInTab() async {
  web.HTMLInputElement loginEmail = queryDom('#loginEmail');
  web.HTMLInputElement loginPassword = queryDom('#loginPassword');
  web.HTMLButtonElement loginButton = queryDom('button#login');
  web.HTMLElement loginError = queryDom('#loginError');
  web.HTMLAnchorElement resetPassword = queryDom('#resetPassword');
  web.HTMLInputElement rememberMe = queryDom('#rememberMe input');
  rememberMe.checked = web.window.localStorage.getItem('rememberMe') == 'true';

  resetPassword.addEventListener('click', ((web.Event _) {
    resetPanel.display();
  }).toJS);

  loginButton.addEventListener('click', ((web.Event _) {
    loginButton.disabled = true;
    loginError.textContent = null;

    final doRemember = rememberMe.checked;
    if (!doRemember) web.window.localStorage.removeItem('token');

    web.window.localStorage.setItem('rememberMe', '$doRemember');

    user.login(
      loginEmail.value,
      loginPassword.value,
      rememberMe: doRemember,
    ).then((loggedIn) {
      if (!loggedIn) {
        loginError.textContent = 'Failed to log in.';
        loginButton.disabled = false;
      } else {
        loginError.textContent = null;
      }
    });
  }).toJS);

  var token = web.window.localStorage.getItem('token');
  if (token != null) {
    if (await user.loginToken(token)) return true;
  }
  _loginTab.classList.remove('hidden');
  return false;
}

void onLogin() {
  (queryDom('#loginText') as web.HTMLElement).style.setProperty('animation-play-state', 'running');
  _loginTab.classList.add('hidden');
  _logout.classList.remove('hidden');
  _showGamesContainer();
  _displayAccountEnteredGames();
  final elements = web.document.querySelectorAll('.acc-enable');
  for (int i = 0; i < elements.length; i++) {
    (elements.item(i) as web.HTMLButtonElement).disabled = false;
  }
}

Future<void> _displayAccountEnteredGames() async {
  for (var g in user.account!.games) {
    // Remove saved game if you're actually the owner
    var saved = _gamesContainer.querySelector('[id="${g.id}"]');
    if (saved != null) saved.remove();

    _addEnteredGame(g);
  }
}

Future<void> _displayLocalEnteredGames() async {
  var idNames = Map<String, String>.from(
      jsonDecode(web.window.localStorage.getItem('joined') ?? '{}'));

  for (var g in idNames.entries) {
    _addEnteredGame(Game(g.key, g.value, false));
  }
}

void _showGamesContainer() {
  (queryDom('#savedGames') as web.HTMLElement).style.setProperty('display', 'flex');
}

void _addEnteredGame(Game game) {
  _showGamesContainer();
  web.HTMLElement nameEl;
  web.HTMLElement topRow;
  var e = web.document.createElement('div') as web.HTMLDivElement
    ..className = 'game'
    ..setAttribute('id', game.id);
  
  topRow = web.document.createElement('span') as web.HTMLSpanElement;
  nameEl = web.document.createElement('h3') as web.HTMLHeadingElement
    ..textContent = game.name;
  topRow.appendChild(nameEl);
  e.appendChild(topRow);
  
  var sessionButton = web.document.createElement('button') as web.HTMLButtonElement
    ..textContent = game.owned ? 'Host Session' : 'Join Session';
  sessionButton.addEventListener('click', ((web.Event event) {
    if (game.owned) {
      user.joinSession(game.id);
    } else {
      join_session.display(game.id);
    }
  }).toJS);
  e.appendChild(sessionButton);

  if (game.owned) {
    var settingsButton = iconButton('cog', className: 'with-tooltip');
    settingsButton.addEventListener('click', ((web.Event _) {
      edit_game.display(game, nameEl, e);
    }).toJS);
    var settingsSpan = web.document.createElement('span') as web.HTMLSpanElement
      ..textContent = 'Settings';
    settingsButton.appendChild(settingsSpan);
    topRow.appendChild(settingsButton);
  } else {
    var unsaveButton = iconButton('times', className: 'with-tooltip');
    unsaveButton.addEventListener('click', ((web.Event _) {
      e.remove();
      _unsaveGame(game.id);
    }).toJS);
    var unsaveSpan = web.document.createElement('span') as web.HTMLSpanElement
      ..textContent = 'Unsave Campaign';
    unsaveButton.appendChild(unsaveSpan);
    topRow.appendChild(unsaveButton);
  }

  _gamesContainer.insertBefore(e, _createGameButton);
}

void _unsaveGame(String id) {
  var idNames = Map<String, String>.from(
      jsonDecode(web.window.localStorage.getItem('joined') ?? '{}'));
  idNames.remove(id);
  web.window.localStorage.setItem('joined', jsonEncode(idNames));
}
