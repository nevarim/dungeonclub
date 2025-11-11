import 'dart:async';

import 'dart:js_interop';
import 'dart:math';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';
import 'package:dungeonclub/models/entity_base.dart';

import '../../main.dart';
import '../communication.dart';
import '../html_helpers.dart';
import '../panels/context_menu.dart';
import '../panels/panel_overlay.dart';

import 'movable.dart';
import 'prefab.dart';

web.HTMLElement get initiativeBar => queryDom('#initiativeBar');
web.HTMLElement get charContainer => initiativeBar.queryDom('.roster');
web.HTMLButtonElement get rerollButton => queryDom('#initiativeReroll');
InitiativeSummary? _summary;

class InitiativeTracker {
  final rng = Random();

  Timer? _diceAnim;
  Iterable<Movable>? _similar;

  web.HTMLButtonElement get callRollsButton => queryDom('#initiativeTracker');
  web.HTMLSpanElement get initiativeDice => queryDom('#initiativeDice');
  web.HTMLSpanElement get targetText => queryDom('#initiativeTarget');
  web.HTMLButtonElement get userRollButton => queryDom('#initiativeRoll');
  web.HTMLButtonElement get skipButton => queryDom('#initiativeSkip');
  web.HTMLButtonElement get skipTypeButton => queryDom('#initiativeSkipType');
  web.HTMLElement get panel => queryDom('#initiativePanel');

  bool get rollerPanelVisible => panel.classList.contains('show');
  set showBar(bool v) => initiativeBar.classList.toggle('hidden', !v);
  set disabled(bool disabled) => callRollsButton.disabled = disabled;

  void init(bool isDM) {
    callRollsButton.addEventListener('click', (web.Event _) {
      callRollsButton.classList.toggle('active');
      var trackerActive = callRollsButton.classList.contains('active');

      if (trackerActive) {
        sendRollForInitiative();
      } else {
        outOfCombat();
        if (!(user.session!.board.refScene.isPlaying)) {
          disabled = true;
        }
        socket.sendAction(GAME_CLEAR_INITIATIVE);
      }
    }.toJS);

    userRollButton.addEventListener('click', (web.Event _) {
      rollDice();
    }.toJS);
    skipButton.classList.toggle('hidden', !isDM);
    skipTypeButton.addEventListener('click', (web.Event _) {
      _skipAllOfType();
    }.toJS);
    if (isDM) {
      skipButton.addEventListener('click', (web.Event _) {
        _summary!.mine.removeAt(0);
        nextRoll();
      }.toJS);
      rerollButton.addEventListener('click', (web.Event _) {
        sendReroll();
      }.toJS);
      panel.queryDom('.close').addEventListener('click', (web.Event _) {
        _summary!.mine.clear();
        nextRoll();
      }.toJS);
    }
  }

  void sendReroll() {
    _summary!.rollRemaining();
    socket.sendAction(GAME_REROLL_INITIATIVE);
    nextRoll();
  }

  void sendRollForInitiative() {
    resetBar();
    _summary!.rollRemaining();
    socket.sendAction(GAME_ROLL_INITIATIVE);
    nextRoll();
  }

  void rollDice() {
    _diceAnim?.cancel();
    var r = rng.nextInt(20) + 1;
    initiativeDice.textContent = '$r';

    var movable = _summary!.mine.removeAt(0);
    var prefab = movable.prefab;
    var dmOnly = user.session!.isDM &&
        (prefab is EmptyPrefab ||
            (prefab is CustomPrefab && prefab.accessIds.isEmpty));

    _summary!.registerRoll(movable, r, dmOnly);
    socket.sendAction(
        GAME_ADD_INITIATIVE, {'id': movable.id, 'roll': r, 'dm': dmOnly});

    _disableButtons(true);

    Future.delayed(Duration(milliseconds: 500), () {
      nextRoll();
    });
  }

  void _disableButtons(bool v) {
    skipButton.disabled = userRollButton.disabled = skipTypeButton.disabled = v;
  }

  void addToInBar(Map<String, dynamic> json) {
    int id = json['id'];
    int total = json['roll'];
    int? mod = json['mod'];
    bool dm = json['dm'] ?? false;
    for (var movable in user.session!.board.movables) {
      if (id == movable.id) {
        return _summary!.registerRoll(movable, total, dm, mod);
      }
    }
  }

  void reroll() {
    _summary!.rollRemaining();
    if (!rollerPanelVisible) {
      nextRoll();
    }
  }

  void showRollerPanel() {
    resetBar();
    _summary!.rollRemaining();
    nextRoll();
  }

  void nextRoll() {
    if (_summary!.mine.isEmpty) {
      panel.classList.remove('show');
      overlayVisible = false;
      return;
    }

    _diceAnim?.cancel();

    var roll = -1;
    _diceAnim = Timer.periodic(Duration(milliseconds: 50), (_) {
      int r;
      do {
        r = rng.nextInt(20) + 1;
      } while (r == roll);

      roll = r;
      initiativeDice.textContent = '$r';
    });

    var mv = _summary!.mine.first;
    var prefab = mv.prefab;
    _similar = _summary!.mine.where((other) {
      if (mv is EmptyMovable) {
        return other is EmptyMovable && mv.label == other.label;
      }
      return other.prefab == prefab;
    });

    var name = mv.displayName;
    targetText.innerHTML = "<b>$name</b>'s Initiative".toJS;

    skipTypeButton.textContent = 'Skip ${_similar!.length} Similar Tokens';
    skipTypeButton.classList.toggle('hidden', _similar!.length < 2);

    panel.classList.add('show');
    overlayVisible = true;
    _disableButtons(false);
  }

  void _skipAllOfType() {
    if (_similar != null) {
      _summary!.mine.removeWhere((m) => _similar!.contains(m));
      nextRoll();
    }
  }

  void resetBar() {
    _summary = InitiativeSummary();
    showBar = true;
  }

  void outOfCombat() {
    showBar = false;
    _summary?.entries.forEach((entry) => entry.e.remove());
    _summary = null;
    updateRerollableInitiatives();
    panel.classList.remove('show');
    overlayVisible = false;
  }

  void onNameUpdate(Movable m) {
    if (_summary != null) {
      for (var entry in _summary!.entries) {
        if (entry.movable == m) {
          entry.nameText.textContent = m.displayName;
          return;
        }
      }
    }
  }

  void onUpdatePrefabImage(Prefab p) {
    if (_summary != null) {
      for (var entry in _summary!.entries) {
        if (entry.movable.prefab == p) {
          entry.applyImage();
        }
      }
    }
  }

  void onRemoveID(int mid) {
    if (_summary != null) {
      for (var entry in _summary!.entries.toList()) {
        if (entry.movable.id == mid) {
          return _summary!.removeEntry(entry);
        }
      }
    }
  }

  void onRemove(Movable m) {
    if (_summary != null) {
      for (var entry in _summary!.entries.toList()) {
        if (entry.movable == m) {
          return _summary!.removeEntry(entry);
        }
      }
      updateRerollableInitiatives();
    }
  }

  void onUpdate(Map<String, dynamic> json) {
    int id = json['id'];
    int mod = json['mod'];
    for (var entry in _summary!.entries) {
      if (entry.movable.id == id) {
        var prefab = entry.movable.prefab;
        if (prefab is HasInitiativeMod) {
          (prefab as HasInitiativeMod).mod = mod;
        }

        entry.modifier = mod;
        return _summary!.sort();
      }
    }
  }

  void fromJson(Iterable? jList) {
    callRollsButton.classList.toggle('active', jList != null);
    outOfCombat();
    if (jList != null) {
      resetBar();
      for (var j in jList) {
        addToInBar(j);
      }
      disabled = false;
    }
  }
}

bool canReroll() {
  if (_summary == null) return true;

  var board = user.session!.board;
  for (var m in board.movables) {
    if (!(_summary!.entries.any((e) => e.movable == m))) {
      return true;
    }
  }
  return false;
}

void updateRerollableInitiatives() {
  if (user.session!.isDM) {
    rerollButton.disabled = !canReroll();
  }
}

class InitiativeSummary {
  final List<Movable> mine = [];
  List<InitiativeEntry> entries = [];

  static int _importance(Movable m) {
    var p = m.prefab;
    if (p is CharacterPrefab) return 0;
    if (p is CustomPrefab) return 1;
    if (p is EmptyPrefab) return 2;
    return 3;
  }

  void rollRemaining() {
    var isDm = user.session!.isDM;
    mine.addAll(user.session!.board.movables.where((m) {
      if (entries.any((e) => e.movable == m) || mine.contains(m)) return false;

      var prefab = m.prefab;

      if (isDm) {
        if (prefab is CharacterPrefab) {
          return !prefab.character.hasJoined;
        }
      } else if (!m.accessible) {
        return false;
      }

      if (prefab is CustomPrefab) {
        var controllers = user.session!.characters.where((pc) {
          return pc.hasJoined && prefab.accessIds.contains(pc.id);
        });

        // DM has control unless exactly one player who has access to
        // this token is currently in the session.
        return isDm == (controllers.length != 1);
      }

      return true;
    }));
    mine.sort((a, b) {
      var cmp = _importance(a).compareTo(_importance(b));

      if (cmp == 0) return a.name.compareTo(b.name);

      return cmp;
    });
  }

  void removeEntry(InitiativeEntry entry) {
    entry.e.remove();
    entries.remove(entry);
    updateRerollableInitiatives();
  }

  void registerRoll(Movable movable, int base, bool dmOnly, [int? mod]) {
    var entry = InitiativeEntry(movable, base, dmOnly);
    if (mod != null) entry.modifier = mod;

    entries.add(entry);
    charContainer.appendChild(entry.e);
    sort();
    updateRerollableInitiatives();
  }

  void sort() {
    for (var n = entries.length; n > 1; --n) {
      for (var i = 0; i < n - 1; ++i) {
        var a = entries[i];
        var b = entries[i + 1];

        if (a.total < b.total) {
          charContainer.insertBefore(b.e, a.e);

          entries[i] = b;
          entries[i + 1] = a;
        }
      }
    }
    charContainer.appendChild(rerollButton);
  }
}

class InitiativeEntry {
  final e = web.document.createElement('div') as web.HTMLDivElement;
  final modText = web.document.createElement('span') as web.HTMLSpanElement;
  final totalText = web.document.createElement('span') as web.HTMLSpanElement;
  final nameText = web.document.createElement('span') as web.HTMLSpanElement;
  final imageElement = web.document.createElement('div') as web.HTMLDivElement;
  final Movable movable;
  final int base;

  bool get dmOnly => e.classList.contains('private');
  set dmOnly(bool dmOnly) {
    if (user.session!.isDM) {
      e.classList.toggle('private', dmOnly);
    }
  }

  int get total => base + modifier;

  late int _modifier;
  int get modifier => _modifier;
  set modifier(int modifier) {
    _modifier = modifier;
    modText.textContent = (modifier >= 0 ? '+$modifier' : '$modifier');
    totalText.textContent = '$total';

    var pref = movable.prefab;
    if (pref is HasInitiativeMod) {
      (pref as HasInitiativeMod).mod = modifier;
    }
  }

  InitiativeEntry(this.movable, this.base, bool dmOnly) {
    int? _bufferedModifier;
    applyImage();

    nameText.className = 'compact';
    nameText.textContent = movable.displayName;

    final stepInput = web.document.createElement('span') as web.HTMLSpanElement;
    stepInput.className = 'step-input';
    
    final minusIcon = icon('minus');
    minusIcon.addEventListener('click', (web.Event _) {
      modifier--;
    }.toJS);
    stepInput.appendChild(minusIcon);
    stepInput.appendChild(modText);
    
    final plusIcon = icon('plus');
    plusIcon.addEventListener('click', (web.Event _) {
      modifier++;
    }.toJS);
    stepInput.appendChild(plusIcon);

    imageElement.appendChild(totalText);
    imageElement.addEventListener('mousedown', ((web.Event e) => _onClick(e as web.MouseEvent)).toJS);
    imageElement.addEventListener('contextmenu', ((web.Event e) => _onClick(e as web.MouseEvent)).toJS);

    e.className = 'char';
    e.appendChild(stepInput);
    e.appendChild(imageElement);
    e.appendChild(nameText);
    
    e.addEventListener('mouseenter', (web.Event _) {
      movable.styleHovered = true;
      _bufferedModifier = modifier;
    }.toJS);
    
    e.addEventListener('mouseleave', (web.Event _) {
      movable.styleHovered = false;
      if (modifier != _bufferedModifier) {
        _summary!.sort();
        sendUpdate();
      }
    }.toJS);

    this.dmOnly = dmOnly;
    var pref = movable.prefab;
    if (pref is HasInitiativeMod) {
      modifier = (pref as HasInitiativeMod).mod;
    } else {
      modifier = 0;
    }
  }

  void applyImage() {
    final img = movable.prefab.image?.url ?? '';
    imageElement.style.backgroundImage = 'url($img)';
  }

  void _onClick(web.MouseEvent ev) async {
    ev.preventDefault();

    final menu = ContextMenu();

    final btnGoTo = menu.addButton('Go To', 'location-crosshairs');
    var btnShowHide = -1;
    var btnRemove = -1;

    if (user.session!.isDM) {
      btnShowHide = menu.addButton(
        dmOnly ? 'Show' : 'Hide',
        dmOnly ? 'eye' : 'eye-slash',
      );

      btnRemove = menu.addButton('Remove', 'trash');
    }

    final result = await menu.display(ev, e.queryDom('div'));

    if (result == btnGoTo) {
      // Animate transform to token position
      await user.session!.board.animateTransformToToken(movable);
    } else if (result == btnShowHide) {
      // Change visibility of initiative entry
      dmOnly = !dmOnly;
      sendUpdate();
    } else if (result == btnRemove) {
      // Remove initiative entry
      await socket.sendAction(GAME_REMOVE_INITIATIVE, {'id': movable.id});
      _summary!.removeEntry(this);
    }
  }

  void sendUpdate() {
    if (user.session!.isDM) {
      socket.sendAction(GAME_UPDATE_INITIATIVE, {
        'id': movable.id,
        'mod': modifier,
        'dm': dmOnly,
      });
    }
  }
}
