import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';

import '../../main.dart';
import '../communication.dart';
import '../html_helpers.dart';
import '../panels/upload.dart' as upload;
import '../resource.dart';

final web.HTMLElement _scenesContainer = queryDom('#scenes') as web.HTMLElement;
final web.HTMLButtonElement _addScene = queryDom('#addScene') as web.HTMLButtonElement;

void _handleAddSceneClick(web.Event ev) async {
  var json = await upload.display(
    event: ev as dynamic,
    action: GAME_SCENE_ADD,
    type: IMAGE_TYPE_SCENE,
    simulateHoverClass: queryDom('#sceneSelector'),
  );

  if (json != null) {
    final session = user.session!;
    if (session.scenes.length == 1) {
      session.scenes.first.enableRemove = true;
    }

    final resource = Resource(json['image']);
    final scene = Scene(json['id'], resource);
    session.scenes.add(scene);
    Scene.updateAddSceneButton();
    await scene.enterEdit(json);
  }
}

// Initialize the add scene button event listener
final _ = _addScene.addEventListener('mousedown', _handleAddSceneClick as web.EventListener);

class Scene {
  final web.HTMLElement e;
  final Resource background;
  final int id;
  late web.HTMLElement _bg;
  late web.HTMLButtonElement _remove;

  bool get isPlaying => user.session!.playingScene == this;
  bool get isEditing => user.session!.board.refScene == this;

  set enableRemove(bool enable) => _remove.disabled = !enable;

  Scene(this.id, this.background)
      : e = web.document.createElement('div') as web.HTMLElement..className = 'scene-preview' {
    e
      ..append(_bg = web.document.createElement('div') as web.HTMLElement)
      ..append(web.document.createElement('span') as web.HTMLElement);
    
    final editButton = iconButton('wrench', label: 'Edit');
     (editButton as dynamic).addEventListener('click', (web.Event _) {
       enterEdit();
     });
     _bg.append(editButton as web.Node);
     
     final spanElement = e.children.item(1) as web.HTMLElement;
     final playButton = iconButton('play', className: 'play', label: 'Play');
     (playButton as dynamic).addEventListener('click', (web.Event _) {
       enterPlay();
     });
     spanElement.append(playButton as web.Node);
     
     _remove = iconButton('trash', className: 'bad');
     (_remove as dynamic).addEventListener('click', (web.Event _) {
       sendRemove();
     });
     spanElement.append(_remove);
    applyBackground();
    _scenesContainer.insertBefore(e as web.Node, _addScene as web.Node);
  }

  Scene.fromJson(Map<String, dynamic> json)
      : this(json['id'], Resource(json['image']));

  void applyBackground() {
    final src = background.url;
    _bg.style.backgroundImage = 'url("$src")';
  }

  void applyEditPlayState() {
    _bg.classList.toggle('playing', isPlaying);
    _bg.classList.toggle('editing', isEditing);
  }

  void sendRemove() {
    socket.sendAction(GAME_SCENE_REMOVE, {'id': id});

    user.session!.scenes.remove(this);
    e.remove();

    updateAddSceneButton();
  }

  void enterPlay() {
    if (isPlaying) return;

    user.session!.playingScene = this;
    user.session!.applySceneEditPlayStates();
    socket.sendAction(GAME_SCENE_PLAY, {'id': id});
  }

  Future<void> enterEdit([Map<String, dynamic>? json]) async {
    if (isEditing) return;

    json = json ?? await socket.request(GAME_SCENE_GET, {'id': id});
    user.session!.board.fromJson(json!, setAsPlaying: false);
  }

  static void updateAddSceneButton() {
    final scenes = user.session!.scenes;
    final reachedLimit = scenes.length >= user.scenesPerCampaign;

    _addScene.disabled = reachedLimit;
    _addScene.title = reachedLimit
        ? "You can't have more than ${user.scenesPerCampaign} scenes at a time."
        : '';

    scenes.first.enableRemove = scenes.length != 1;
  }
}
