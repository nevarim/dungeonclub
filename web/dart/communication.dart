import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';
import 'package:dungeonclub/comms.dart';
import 'package:dungeonclub/environment.dart';
import 'package:path/path.dart';

import '../main.dart';
import 'action_handler.dart' as handler;
import 'html_helpers.dart';
import 'panels/dialog.dart';
import 'session/measuring.dart';

/// Converts a web.Blob to Uint8List
Future<Uint8List> blobToBytes(web.Blob blob) async {
  final reader = web.FileReader();
  reader.readAsArrayBuffer(blob);
  await reader.onLoadEnd.first;
  final result = reader.result as JSArrayBuffer;
  return result.toDart.asUint8List();
}

final String _serverAddress = _getServerAddress();

final socket = FrontSocket();

bool get isDebugging {
  final webPort = web.window.location.port;
  return !Environment.isCompiled && webPort == '8080';
}

String _getServerAddress() {
  final address = web.window.location.origin;

  if (isDebugging) {
    // Replace address port 8080 with default server port 7070
    return address.substring(0, address.length - 4) + '7070';
  }

  return address;
}

String getFile(String path) {
  path = Uri.encodeFull(path);
  return join(_serverAddress, path);
}

const demoActions = [
  FEEDBACK,
  GAME_MUSIC_PLAYLIST,
];

class FrontSocket extends Socket {
  web.WebSocket? _webSocket;
  final _waitForOpen = Completer();
  Timer? _retryTimer;
  ConstantDialog? _errorDialog;
  bool _manualClose = false;

  Future<void> _requireConnection() async {
    if (_webSocket == null) {
      connect();
    }
    return _waitForOpen.future;
  }

  void connect({bool goHome = true}) {
    _retryTimer?.cancel();
    _webSocket = web.WebSocket(getFile('ws').replaceFirst('http', 'ws'))
      ..addEventListener('open', ((web.Event e) {
        if (_errorDialog != null) {
          web.window.location.href = goHome ? homeUrl : web.window.location.href;
        } else {
          _waitForOpen.complete();
        }
      }).toJS)
      ..addEventListener('close', ((web.Event e) => _handleConnectionClose()).toJS)
      ..addEventListener('error', ((web.Event e) => _handleConnectionError()).toJS);

    listen();
  }

  void close() {
    _manualClose = true;
    _webSocket?.close();
  }

  void _handleConnectionClose() async {
    if (_manualClose) return;

    _errorDialog ??= ConstantDialog('Connection Error')
      ..addParagraph('Your connection to the server was closed unexpectedly.')
      ..addParagraph('Reconnecting...')
      ..append(icon('spinner')..classList.add('spinner'))
      ..display();

    _retryTimer = Timer(Duration(seconds: 1), () => connect(goHome: false));
  }

  void _handleConnectionError() async {
    if (_manualClose) return;

    web.document.title = 'Reconnecting...';
    _errorDialog ??= ConstantDialog('Connection Error')
      ..addParagraph('''The $appName server seems to be offline.
        It's probably under maintenance or loading a cool new feature.
        You may go get a coffee or some bread if you feel like it.''')
      ..addParagraph('''The server should be back up
        in a few minutes or seconds, even.
        As soon as possible, you will be automatically reconnected!''')
      ..append(icon('spinner')..classList.add('spinner'))
      ..display();

    _retryTimer = Timer(Duration(seconds: 10), () => connect());
  }

  bool canSend(String action) {
    if (user.isInDemo && !demoActions.contains(action)) {
      return false;
    }
    return true;
  }

  @override
  Stream get messageStream {
    final controller = StreamController.broadcast();
    _webSocket!.addEventListener('message', ((web.MessageEvent event) {
      controller.add(event.data);
    }).toJS);
    return controller.stream;
  }

  @override
  Future<void> send(data) async {
    if (user.isInDemo && data is! String) return;

    await _requireConnection();
    _webSocket!.send(data);
  }

  @override
  Future<dynamic> request(String action, [Map<String, dynamic>? params]) async {
    if (!canSend(action)) return null;

    await _requireConnection();
    return super.request(action, params);
  }

  @override
  Future<void> sendAction(String action, [Map<String, dynamic>? params]) async {
    if (!canSend(action)) return;

    await _requireConnection();
    return super.sendAction(action, params);
  }

  @override
  Future handleAction(
    String action, [
    Map<String, dynamic>? params,
  ]) =>
      handler.handleAction(action, params ?? {});

  @override
  void handleBinary(data) async {
    if (data is web.Blob) {
      var bytes = await blobToBytes(data);
      var port = bytes.first;

      if (port == measuringPort) {
        handleMeasuringEvent(bytes);
      } else if (port != 99) {
        user.session?.board.mapTab.handleEvent(bytes);
      }
    }
  }
}
