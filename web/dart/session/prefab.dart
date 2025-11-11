import 'dart:js_interop';
import 'dart:math';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/models/entity_base.dart';

import '../../main.dart';
import '../html/instance_component.dart';
import '../html_helpers.dart';
import '../resource.dart';
import 'character.dart';
import 'movable.dart';
import 'prefab_palette.dart';

mixin ClampedEntityBase on EntityBase {
  int get minSize;

  @override
  int get jsonFallbackSize => minSize;

  @override
  set size(int size) {
    super.size = min(max(size, minSize), 25);
  }
}

abstract class Prefab extends InstanceComponent
    with EntityBase, ClampedEntityBase {
  final web.HTMLSpanElement _nameSpan;
  final Resource? image;

  @override
  set size(int size) {
    super.size = size;
    movables.forEach((m) => m.onPrefabUpdate());
  }

  Iterable<Movable> get movables =>
      user.session!.board.movables.where((movable) => movable.prefab == this);

  String get id;
  String get name;

  @override
  int get minSize => 1;

  Prefab(this.image)
      : _nameSpan = web.document.createElement('span') as web.HTMLSpanElement,
        super(web.document.createElement('div') as web.HTMLDivElement) {
    (htmlRoot as web.HTMLElement)
      ..className = 'prefab'
      ..addEventListener('click', ((web.Event _) {
        if (selectedPrefab == this) {
          selectedPrefab = null;
        } else {
          selectedPrefab = this;
        }
      }).toJS)
      ..appendChild(_nameSpan);
  }

  void applyImage() {
    if (image != null) {
      final src = image!.url;

      if (user.session!.isDM) {
        (htmlRoot as web.HTMLElement).style.setProperty('background-image', 'url($src)');
      }
    }
  }

  void applyName() {
    _nameSpan.textContent = name;
  }
}

class EmptyPrefab extends Prefab {
  @override
  String get id => 'e';

  @override
  String get name => 'Labeled Token';

  String get iconId => 'pen';

  EmptyPrefab() : super(null) {
    size = 1;
    htmlRoot.append(icon(iconId));
    applyName();
  }
}

mixin ChangeableName on Prefab {
  String _name = '';

  @override
  String get name => _name;
  set name(String name) {
    _name = name;
    applyName();
  }

  @override
  void applyName() {
    super.applyName();

    user.session!.board.onPrefabNameChange(this);
    for (var m in movables) {
      user.session!.board.initiativeTracker.onNameUpdate(m);
      m.updateTooltip();
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'name': name,
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);
    if (json['name'] != null) name = json['name'];
  }
}

class CharacterPrefab extends Prefab with HasInitiativeMod, ChangeableName {
  late Character _character;
  Character get character => _character;
  set character(Character c) {
    _character = c;
    applyImage();
    applyName();
  }

  @override
  String get id => 'c${character.id}';

  @override
  set name(String name) {
    super.name = name;
    character.applyNameToOnlineIndicator();
  }

  CharacterPrefab(int id, String name, Resource avatar) : super(avatar) {
    _name = name;
  }
}

class CustomPrefab extends Prefab with HasInitiativeMod, ChangeableName {
  final int _id;
  final Set<int> accessIds = {};

  @override
  String get id => '$_id';
  int get idNum => _id;

  CustomPrefab(int id, Resource image)
      : _id = id,
        super(image);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'access': accessIds.toList(),
      };

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);
    accessIds.clear();
    accessIds.addAll(Set.from(json['access']));

    applyImage();
  }
}
