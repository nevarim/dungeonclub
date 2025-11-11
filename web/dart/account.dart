import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import '../main.dart';
import 'game.dart';
import 'html_helpers.dart';
import 'notif.dart';
import 'panels/edit_game.dart' as edit_game;
import 'panels/panel_overlay.dart';

class Account {
  final List<Game> games;
  final _joinStream = StreamController<bool>.broadcast();
  final Map<String, dynamic> limits;
  int _lockJoin = 0;

  Account(Map<String, dynamic> json)
      : games = List.from(json['games'])
            .map((e) => Game(e['id'], e['name'], e['mine']))
            .toList(),
        limits = (json['limits'] ?? {}) {
    var token = json['token'];
    if (token != null) {
      web.window.localStorage.setItem('token', token.toString());
    }
  }

  int get mediaBytesPerCampaign => limits["media_bytes_per_campaign"] as int;
  int get prefabsPerCampaign => limits["prefabs_per_campaign"] as int;
  int get scenesPerCampaign => limits["scenes_per_campaign"] as int;
  int get mapsPerCampaign => limits["maps_per_campaign"] as int;
  int get campaignsPerAccount => limits["campaigns_per_account"] as int;
  int get playersPerCampaign => limits["players_per_campaign"] as int;
  int get tokensPerScene => limits["tokens_per_scene"] as int;

  Future<Game?> createNewGame() async {
    final game = await edit_game.displayPrepare();
    if (game != null) games.add(game);
    return game;
  }

  Future displayPickCharacterDialog(String name) async {
    var notif = HtmlNotification('<b>$name</b> wants to join.');
    web.document.title = '$name wants to join | $appName';

    var letIn = await notif.prompt();
    web.document.title = appName;

    if (!letIn) return null;

    _lockJoin++;
    var count = _lockJoin;
    for (var i = 1; i < count; i++) {
      await _joinStream.stream.first;
    }

    var completer = Completer<int>();
    bool isCompleted = false;
    var chars = user.session!.characters;

    var available = chars.where((c) => !c.hasJoined);

    if (available.isEmpty) {
      return HtmlNotification('Every available character is already assigned!')
          .display();
    }
    if (available.length == 1) {
      // Prevent adding multiple events to _joinStream simultaneously
      await Future.microtask(() => null);
      _lockJoin--;
      _joinStream.add(true);
      return available.first.id;
    }

    web.HTMLElement parent = queryDom('#charPick') as web.HTMLElement;
    web.HTMLElement roster = parent.querySelector('.roster') as web.HTMLElement;
    for (int i = roster.children.length - 1; i >= 0; i--) {
      roster.children.item(i)!.remove();
    }

    (parent.querySelector('span') as web.HTMLElement).innerHTML = "Pick <b>$name</b>'s Character".toJS;

    for (var ch in chars) {
      final div = web.document.createElement('div') as web.HTMLDivElement;
      div.className = 'char';
      div.classList.toggle('reserved', ch.hasJoined);
      
      final img = web.document.createElement('img') as web.HTMLImageElement;
      img.src = ch.image.url;
      div.appendChild(img);
      
      final span = web.document.createElement('span') as web.HTMLSpanElement;
      span.textContent = ch.name;
      div.appendChild(span);
      
      div.addEventListener('click', ((web.Event e) {
          if (!isCompleted) {
            isCompleted = true;
            completer.complete(ch.id);
          }
        }).toJS);
      
      roster.appendChild(div);
    }

    overlayVisible = true;
    parent.classList.add('show');
    var result = await completer.future;

    overlayVisible = false;
    parent.classList.remove('show');

    unawaited(
        user.session!.connectionEvent.firstWhere((join) => join).then((_) {
      _lockJoin--;
      _joinStream.add(true);
    }));
    return result;
  }
}
