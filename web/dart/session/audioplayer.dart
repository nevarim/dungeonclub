import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'dart:math';

import 'package:ambience/ambience.dart';
import 'package:ambience/audio_track.dart';
import 'package:ambience/metadata.dart';
import 'package:dungeonclub/actions.dart';
import 'package:dungeonclub/environment.dart';

import '../../main.dart';
import '../communication.dart';
import '../html_helpers.dart';
import '../smooth_slider.dart';
import 'session.dart';

final _root = queryDom('#ambience');

class AudioPlayer {
  late Ambience _ambience;
  late FilterableAudioClipTrack _weather;
  late FilterableAudioClipTrack _crowd;
  late ClipPlaylist<AudioClipTrack> _playlist;
  Tracklist? tracklist;
  late SmoothSlider _sWeather;
  late SmoothSlider _sFilter;
  late SmoothSlider _sCrowd;

  web.HTMLButtonElement get skipButton => queryDom('#audioSkip') as web.HTMLButtonElement;

  num _volumeSfx = 0;
  num get volumeSfx => _volumeSfx;
  set volumeSfx(num volume) {
    _volumeSfx = volume;
    _weather.volume = volume * 0.2;
    _crowd.volume = volume * 0.25;
  }

  num get volumeMusic => _playlist.track.volume;
  set volumeMusic(num volume) => _playlist.track.volume = volume;

  num get filter => _sFilter.goal;
  set filter(num v) {
    _sFilter.goal = v;
    ((_sFilter.input as dynamic).parentElement.querySelector('span') as web.HTMLElement).textContent = _getTooltip(1, v);
  }

  int get weatherIntensity => _sWeather.goal.toInt();
  set weatherIntensity(int v) {
    _sWeather.goal = v;
    _weather.cueClip(v >= 0 ? v.toInt() : null);
    ((_sWeather.input as dynamic).parentElement.querySelector('span') as web.HTMLElement).textContent =
        'Weather: ${_getTooltip(0, v)}';
  }

  int get crowdedness => _sCrowd.goal.toInt();
  set crowdedness(int v) {
    _sCrowd.goal = v;
    _crowd.cueClip(v >= 0 ? v.toInt() : null);
    ((_sCrowd.input as dynamic).parentElement.querySelector('span') as web.HTMLElement).textContent = 'Crowd: ${_getTooltip(2, v)}';
  }

  String _toUrl(String s) => getFile('ambience/sounds/$s.mp3');

  void _setupAmbience() {
    _ambience = Ambience()..volume = 0.5;
    _weather = FilterableAudioClipTrack(_ambience)
      ..addAll(['rain', 'heavy-rain'].map((s) => _toUrl('weather-$s')));

    _crowd = FilterableAudioClipTrack(_ambience)
      ..addAll(['pub', 'market'].map((s) => _toUrl('crowd-$s')));

    _playlist = ClipPlaylist(AudioClipTrack(_ambience));
    _playlist.onClipChange.listen((clip) {
      if (tracklist == null || clip == null) {
        displayTrack(null);
      } else {
        displayTrack(tracklist!.tracks[clip.id]);
      }
    });
  }

  void init(Session session, json) async {
    await requireFirstInteraction;
    _setupAmbience();

    final mediaSession = web.window.navigator.mediaSession;
    (mediaSession as dynamic).setActionHandler('play', () {});
    (mediaSession as dynamic).setActionHandler('pause', () {});
    (mediaSession as dynamic).setActionHandler('stop', () {});
    (mediaSession as dynamic).setActionHandler('seekbackward', () {});
    (mediaSession as dynamic).setActionHandler('seekforward', () {});
    (mediaSession as dynamic).setActionHandler('seekto', () {});

    _input('vMusic', 0.5, (v) => volumeMusic = v);
    _input('vAmbience', 0.5, (v) => volumeSfx = v);

    _sWeather = SmoothSlider(_input(
        'weather', json['weather'], (v) => weatherIntensity = v.toInt(), true));
    _sCrowd = SmoothSlider(
        _input('crowd', json['crowd'], (v) => crowdedness = v.toInt(), true));
    _sFilter = SmoothSlider(
      _input('weatherFilter', json['inside'], (_) {}, true),
      onSmoothChange: (v) => _weather.filter = 20000 - 19800 * pow(v, 0.5),
    );

    var pin = web.window.localStorage.getItem('audioPin');
    (_root as web.HTMLElement).classList.toggle(
        'keep-open', Environment.enableMusic ? pin != 'false' : pin == 'true');

    final button = queryDom('#ambience button') as web.HTMLButtonElement;
    (button as dynamic).addEventListener('click', (web.Event _) {
      web.window.localStorage.setItem('audioPin', '${(_root as web.HTMLElement).classList.toggle('keep-open')}');
    });

    if (session.isDM) {
      (skipButton as dynamic).addEventListener('click', (web.Event _) => _sendSkip());

      final playlistsContainer = queryDom('#playlists') as web.HTMLElement;
      for (var i = 0; i < playlistsContainer.children.length; i++) {
        final pl = playlistsContainer.children.item(i) as web.HTMLElement;
        var id = pl.getAttribute('value');

        if (json != null && json['playlist'] == id) {
          pl.classList.add('active');
        }

        (pl as dynamic).addEventListener('click', (web.Event _) {
           var doSend = !pl.classList.contains('active');
           if (doSend) {
             final activeElements = _root.querySelectorAll('#playlists > .active');
             for (var j = 0; j < activeElements.length; j++) {
               (activeElements.item(j) as web.HTMLElement).classList.remove('active');
             }
           }

           pl.classList.toggle('active', doSend);
           _sendPlaylist(doSend ? id : null);
         });
      }
    } else {
      ambienceFromJson(json);
    }

    onNewTracklist(json);
  }

  web.HTMLInputElement _input(String id, num? init, void Function(num value) onChange,
      [bool sendAmbience = false]) {
    web.HTMLInputElement input = queryDom('#$id') as web.HTMLInputElement;

    final stored = web.window.localStorage.getItem(id) ?? '$init';
    final initial = num.tryParse(stored) ?? input.valueAsNumber;

    input.valueAsNumber = initial;
    scheduleMicrotask(() => onChange(initial));

    if (sendAmbience) {
      (input as dynamic).addEventListener('change', (web.Event _) => _sendAmbience());
    }

    (input as dynamic).addEventListener('input', (web.Event _) {
      if (!sendAmbience) {
        web.window.localStorage.setItem(id, input.value);
      }
      onChange(input.valueAsNumber);
    });
    
    return input;
  }

  void _sendAmbience() {
    if (user.session!.isDM) {
      socket.sendAction(GAME_MUSIC_AMBIENCE, ambienceToJson());
    }
  }

  Map<String, dynamic> ambienceToJson() => {
        'weather': weatherIntensity,
        'inside': filter,
        'crowd': crowdedness,
      };

  void ambienceFromJson(json) {
    weatherIntensity = json['weather'];
    filter = json['inside'];
    crowdedness = json['crowd'];
  }

  void _sendSkip() {
    if (user.session!.isDM) {
      _playlist.skip();
      tracklist!.setTrack(_playlist.index);
      socket.sendAction(GAME_MUSIC_SKIP, tracklist!.toSyncJson());
    }
  }

  void _sendPlaylist(String? id) async {
    if (user.session!.isDM) {
      var json = await socket.request(GAME_MUSIC_PLAYLIST, {'playlist': id});
      onNewTracklist(json);

      if (id == 'Tavern') {
        crowdedness = 0;
        filter = 0.8;
      } else if (id == 'Dungeon') {
        crowdedness = -1;
        filter = 0.8;
      } else if (id != null) {
        crowdedness = -1;
        if (id == 'Overworld') filter = 0;
      }
      _sendAmbience();
    }
  }

  void onNewTracklist(json) {
    tracklist = (json == null || json['tracks'] == null)
        ? null
        : Tracklist.fromJson(json);
    _playlist.fromTracklist(
        tracklist, (t) => getFile('ambience/tracks/${t.id}.mp3'));

    skipButton.disabled = tracklist == null;
    if (tracklist == null) displayTrack(null);
  }

  void syncTracklist(json) {
    if (tracklist != null) {
      tracklist!.fromSyncJson(json);
      _playlist.syncToTracklist(tracklist!);
    }
  }

  void displayTrack(Track? t) {
    var player = queryDom('#player') as web.HTMLElement;

    var children = player.children;
    var title = children.item(0) as web.HTMLElement;
    if (t != null) {
      player.classList.remove('hide');
      title.setAttribute('href', 'https://www.youtube.com/watch?v=${t.id}');
    } else {
      player.classList.add('hide');
      title.removeAttribute('href');
    }

    title.title = t?.title ?? '';

    _changeText(title, t?.title ?? '');
    _changeText(children.item(1) as web.HTMLElement, t?.artist ?? '');
  }

  Future<void> _changeText(web.HTMLElement e, String content) async {
    if ((e.innerHTML as String).trim() != content.trim()) {
      e.classList.add('transition');
      await Future.delayed(Duration(milliseconds: 200));
      if (content != '') {
        e.innerHTML = content.toJS;
        e.classList.remove('transition');
      }
    } else {
      e.classList.remove('transition');
    }
  }

  static String _getTooltip(int tool, num value) {
    switch (tool) {
      case 0:
        switch (value) {
          case -1:
            return 'Clear';
          case 0:
            return 'Light Rain';
          case 1:
            return 'Heavy Rain';
          default:
            return 'Unknown';
        }
      case 1:
        return 'Outside/Inside';
      case 2:
        switch (value) {
          case -1:
            return 'None';
          case 0:
            return 'Tavern';
          case 1:
            return 'Marketplace';
          default:
            return 'Unknown';
        }
    }
    throw RangeError('No tooltip for input value $value');
  }
}
