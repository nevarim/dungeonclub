import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';

import '../../main.dart';
import '../communication.dart';
import '../edit_image.dart';
import '../html_helpers.dart';
import '../game.dart';
import '../resource.dart';
import 'dialog.dart';
import 'panel_overlay.dart';
import 'upload.dart' as uploader;

final web.HTMLElement _panel = queryDom('#editGamePanel') as web.HTMLElement;
final web.HTMLInputElement _gameNameInput = _panel.queryDom('#gameName') as web.HTMLInputElement;
final web.HTMLElement _roster = _panel.queryDom('#editChars') as web.HTMLElement;
final web.HTMLButtonElement _cancelButton = _panel.queryDom('button.close') as web.HTMLButtonElement;
final web.HTMLButtonElement _deleteButton = _panel.queryDom('button#delete') as web.HTMLButtonElement;
final web.HTMLButtonElement _saveButton = _panel.queryDom('button#save') as web.HTMLButtonElement;

final _chars = <_EditChar>[];

final web.HTMLAnchorElement _addCharButton = _panel.queryDom('#addChar') as web.HTMLAnchorElement
  ..addEventListener('click', (web.MouseEvent _) {
    _chars.add(_EditChar.empty()..focus());
    _updateAddButton();
  }.toJS);

bool _prepareMode = false;
bool get prepareMode => _prepareMode;
set prepareMode(bool v) {
  _prepareMode = v;
  _panel.classList.toggle('prepare', v);
}

Future<void> display(
  Game game, [
  web.HTMLElement? title,
  web.HTMLElement? refEl,
]) async {
  prepareMode = false;
  var result = await socket.request(GAME_EDIT, {'id': game.id});

  overlayVisible = true;
  _saveButton.textContent = 'Save Changes';
  _saveButton.disabled = false;

  _gameNameInput
    ..value = game.name
    ..focus();
  for (var c in _chars) {
    c.e.parentNode?.removeChild(c.e);
  }
  _chars.clear();

  for (var jChar in result['pcs']) {
    _chars.add(_EditChar.fromJson(game, jChar));
  }

  _updateAddButton();
  uploader.usedStorage = result['usedStorage'];

  var closer = Completer();
  var subs = [
    _saveButton.addEventListener('click', (web.MouseEvent event) {
      _saveButton.disabled = true;
      _saveChanges(game.id).then((success) {
        if (success) {
          title?.textContent = _gameNameInput.value;
          game.name = _gameNameInput.value;
          closer.complete();
        }
      });
    }.toJS),
    _cancelButton.addEventListener('click', ((web.MouseEvent event) {
      closer.complete();
    }).toJS),
    _deleteButton.addEventListener('click', ((web.MouseEvent event) {
      _delete(game).then((success) {
        if (success) {
          refEl?.parentNode?.removeChild(refEl);
          closer.complete();
        }
      });
    }).toJS)
  ];

  _panel.classList.remove('prepare');
  _panel.classList.add('show');

  await closer.future;
  _panel.classList.remove('show');
  // Event listeners are automatically cleaned up
  overlayVisible = false;
}

Future<Game?> displayPrepare() async {
  prepareMode = true;
  overlayVisible = true;
  _saveButton.textContent = 'Create Campaign';
  _saveButton.disabled = false;

  _gameNameInput.value = '';
  _gameNameInput.focus();
  for (var c in _chars) {
    c.e.parentNode?.removeChild(c.e);
  }
  _chars.clear();

  // Add 4 default characters
  for (var i = 0; i < 4; i++) {
    _chars.add(_EditChar.empty());
  }

  _updateAddButton();
  uploader.usedStorage = 0;

  var closer = Completer();
  var subs = [
    _saveButton.addEventListener('click', (web.MouseEvent _) {
      _saveButton.disabled = true;
      _createGameAndJoin().then((result) {
        closer.complete(result);
      });
    }.toJS),
    _cancelButton.addEventListener('click', ((web.MouseEvent _) {
      closer.complete();
    }).toJS),
  ];

  _panel.classList.add('show');
  _panel.classList.add('prepare');

  var result = await closer.future;
  _panel.classList.remove('show');
  // Event listeners are automatically cleaned up
  overlayVisible = false;

  return result;
}

void _updateAddButton() {
  _addCharButton.classList.toggle('disabled',
      _chars.where((char) => !char.isRemoved).length >= user.playersPerCampaign);
}

class _EditChar {
  final web.HTMLElement e;
  final int? id;
  final BaseResource avatar;
  bool isRemoved = false;
  String? bufferedImg;
  late web.HTMLInputElement _nameInput;
  String get name => _nameInput.value;

  bool get isOG => id != null;

  _EditChar(this.id, String name, this.avatar) : e = web.document.createElement('li') as web.HTMLElement {
    final editImgDiv = web.document.createElement('div') as web.HTMLElement
      ..className = 'edit-img responsive';
    final changeDiv = web.document.createElement('div') as web.HTMLElement
      ..textContent = 'Change';
    final imgElement = web.document.createElement('img') as web.HTMLImageElement
      ..src = avatar.url;
    editImgDiv.appendChild(changeDiv);
    editImgDiv.appendChild(imgElement);
    
    e.appendChild(registerEditImage(editImgDiv, upload: _changeIcon));
    
    _nameInput = web.document.createElement('input') as web.HTMLInputElement
      ..placeholder = 'Name...'
      ..value = name;
    e.appendChild(_nameInput);
    
    final removeButton = iconButton('times', className: 'bad') as web.HTMLElement
      ..tabIndex = -1;
    removeButton.addEventListener('click', ((web.MouseEvent _) {
      remove();
    }).toJS);
    e.appendChild(removeButton);

    _roster.appendChild(e);
  }

  _EditChar.fromJson(Game game, json)
      : this(
          json['id'],
          json['name'],
          Resource(json['prefab']['image'], game: game),
        );

  _EditChar.empty() : this(null, '', BaseResource('asset:default_pc.jpg'));

  Future<String> _changeIcon(web.MouseEvent ev, [web.Blob? initialFile]) async {
    // Note: uploader.display expects dart:html types, but we're passing web types
    // This will need to be fixed when upload.dart is migrated to package:web
    return await uploader.display(
      event: ev as dynamic,
      type: IMAGE_TYPE_PC,
      initialImg: initialFile as dynamic,
      processUpload: (data, maxRes, upscale) async {
        bufferedImg = data;
        if (data.startsWith('asset')) return BaseResource(data).url;
        return 'data:image/jpeg;base64,$data';
      },
      onPanelVisible: (v) => _panel.classList.toggle('upload', v),
    );
  }

  Future<void> remove() async {
    if (isOG) {
      var confirm = await Dialog<bool>(
        'Remove Character?',
        onClose: () => false,
        okText: 'Remove $name',
      ).addParagraph(
          '''This will remove <b>$name</b> from the campaign.''').display();

      if (!confirm) return;
      isRemoved = true;
    } else {
      _chars.remove(this);
    }

    e.parentNode?.removeChild(e);
    _updateAddButton();
  }

  void focus() {
    _nameInput.focus();
  }

  Map<String, dynamic>? toJson() => isRemoved
      ? null
      : {
          'name': name,
          if (bufferedImg != null) 'avatar': bufferedImg,
        };
}

Map<String, dynamic> _currentDataJson() {
    return {
      'name': _gameNameInput.value,
      'pcs': {
        for (var char in _chars)
          if (char.isOG) '${char.id}': char.toJson()
      },
      'newPCs': [
        for (var char in _chars)
          if (!char.isOG) char.toJson()
      ],
    };
  }

Future<Game> _createGameAndJoin() async {
  var name = _gameNameInput.value;

  var session = await socket.request(GAME_CREATE_NEW, {
    'data': _currentDataJson(),
  });

  if (session == null) {
    throw 'Unable to create game';
  }

  var game = Game(session['id'], name, true);
  user.joinFromJson(session, false);
  return game;
}

Future<bool> _saveChanges(String id) async {
  final data = _currentDataJson();
  return await socket.request(GAME_EDIT, {'id': id, 'data': data});
}

Future<bool> _delete(Game game) async {
  var confirmed = await Dialog<bool>(
    'Delete Campaign?',
    onClose: () => false,
    okText: 'Delete Forever',
    okClass: 'bad',
  ).addParagraph('''
    All of <b>${game.name}</b>'s characters, maps and scenes,
    along with their uploaded images, will be immediately removed from the
    server. This action can't be undone.''').display();
  return confirmed && await socket.request(GAME_DELETE, {'id': game.id});
}
