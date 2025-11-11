import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';

import '../communication.dart';
import '../html_helpers.dart';
import '../resource.dart';
import 'prefab.dart';
import 'session.dart';

class Character {
  final int id;
  final CharacterPrefab prefab;

  final _onlineIndicator = web.document.createElement('span') as web.HTMLSpanElement;
  final _onlineIndicatorName = web.document.createElement('div') as web.HTMLDivElement;
  final _onlineIndicatorTooltip = web.document.createElement('span') as web.HTMLSpanElement;

  bool _hasJoined = false;
  bool get hasJoined => _hasJoined;
  set hasJoined(bool hasJoined) {
    _hasJoined = hasJoined;

    if (hasJoined) {
      (queryDom('#online') as dynamic).append(_onlineIndicator);
    } else {
      _onlineIndicator.remove();
    }
  }

  String get name => prefab.name;
  Resource get image => prefab.image!;

  Character(
    this.id,
    Session session, {
    required String color,
    required String name,
    required String avatarUrl,
    Map<String, dynamic>? prefabJson,
    bool joined = false,
  }) : prefab = CharacterPrefab(id, name, Resource(avatarUrl)) {
    final iconElement = icon('circle');
    (iconElement as dynamic).style.color = color;
    _onlineIndicator
      ..append(iconElement as web.Node)
      ..append(_onlineIndicatorName as web.Node);

    if (session.isDM) {
      _onlineIndicator
        ..className = 'with-tooltip'
        ..append(_onlineIndicatorTooltip as web.Node)
        ..addEventListener('click', (web.Event _) {
          socket.sendAction(GAME_KICK, {'pc': id});
        } as web.EventListener);
    }

    hasJoined = joined;
    prefab
      ..fromJson(prefabJson ?? {})
      ..character = this;

    applyNameToOnlineIndicator();
  }

  Character.fromJson(String color, Session session, Map<String, dynamic> json)
      : this(
          json['id'],
          session,
          color: color,
          name: json['name'],
          avatarUrl: json['prefab']['image'],
          joined: json['connected'] ?? false,
          prefabJson: json['prefab'],
        );

  void applyNameToOnlineIndicator() {
    _onlineIndicatorTooltip.textContent = 'Kick $name';
    _onlineIndicatorName.textContent = name;
  }
}
