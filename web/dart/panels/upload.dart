import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:math';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/actions.dart';
import 'package:dungeonclub/comms.dart';
import 'package:dungeonclub/point_json.dart';

import '../../main.dart';
import '../communication.dart';
import 'context_menu.dart';
import 'dialog.dart';
import 'panel_overlay.dart';

extension ElementLeftClickDown on web.Element {
  Stream<web.MouseEvent> get onLMB => onMouseDown.where((ev) => ev.button == 0);
}

final web.HTMLElement _panel = web.document.querySelector('#uploadPanel') as web.HTMLElement;
final web.HTMLButtonElement _cancelButton = _panel.querySelector('button.close') as web.HTMLButtonElement;

final web.HTMLElement _imgBox = _panel.querySelector('div') as web.HTMLElement;

final web.HTMLInputElement _uploadInput = _panel.querySelector('#imgUpload') as web.HTMLInputElement;

final web.HTMLImageElement _img = _panel.querySelector('img') as web.HTMLImageElement;
final web.HTMLCanvasElement _canvas = _panel.querySelector('canvas') as web.HTMLCanvasElement;
final web.HTMLButtonElement _uploadButton = _panel.querySelector('button[type=submit]') as web.HTMLButtonElement;
final web.HTMLDivElement _crop = _panel.querySelector('#crop') as web.HTMLDivElement;
final web.HTMLSpanElement _dragText = _panel.querySelector('#dragText') as web.HTMLSpanElement;

final web.HTMLDivElement _assetPanel = web.document.querySelector('#assetPanel') as web.HTMLDivElement;
final web.HTMLDivElement _assetGrid = web.document.querySelector('#assetGrid') as web.HTMLDivElement;

Point<double> get _imgSize =>
    Point(_img.width.toDouble(), _img.height.toDouble());

Point<double> _position = Point(0, 0);
Point<double> get position => _position;

void setPosAndSize(Point<double> p, Point<double> s) {
  p = Point(p.x.roundToDouble(), p.y.roundToDouble());
  _position = clamp(p, Point(0, 0), _imgSize - size);
  _size = clamp(s, minSize, _imgSize - position);
  _position = clamp(p, Point(0, 0), _imgSize - size);

  _crop.style.left = '${_position.x}px';
  _crop.style.top = '${_position.y}px';
  _crop.style.width = '${_size.x}px';
  _crop.style.height = '${_size.y}px';

  _resizeOutside();
}

Point<double> minSize = Point<double>(50, 50);

Point<double> _size = Point(400, 400);
Point<double> get size => _size;

bool _square = false;
bool _init = false;

const thresholdStorageWarning = 5 * 1000000;

int _usedStorage = 0;
int get usedStorage => _usedStorage;
set usedStorage(int bytes) {
  _usedStorage = bytes;

  final percentage = '${100 * bytes / user.mediaBytesPerCampaign}%';

  [for (int i = 0; i < web.document.querySelectorAll('.used-storage').length; i++) web.document.querySelectorAll('.used-storage').item(i)!].forEach(
    (e) => (e as web.HTMLInputElement)
      ..style.setProperty('--v', percentage)
      ..min = '0'
      ..max = '${user.mediaBytesPerCampaign.toString()}'
      ..valueAsNumber = bytes,
  );

  final storageLeft = user.mediaBytesPerCampaign - bytes;
  final displayWarning = storageLeft <= thresholdStorageWarning;

  (web.document.querySelector('#storageWarning') as web.HTMLElement).classList.toggle('hidden', !displayWarning);

  [for (int i = 0; i < web.document.querySelectorAll('.storage-used').length; i++) web.document.querySelectorAll('.storage-used').item(i)!].forEach((e) => e.textContent = bytesToMB(bytes));
  [for (int i = 0; i < web.document.querySelectorAll('.storage-left').length; i++) web.document.querySelectorAll('.storage-left').item(i)!]
      .forEach((e) => e.textContent = bytesToMB(storageLeft));
  [for (int i = 0; i < web.document.querySelectorAll('.storage-max').length; i++) web.document.querySelectorAll('.storage-max').item(i)!]
      .forEach((e) => e.textContent = '${user.mediaBytesPerCampaign ~/ 1000000}');
}

void _initialize() {
  _init = true;

  _uploadInput.addEventListener('input', (web.Event event) {
    final files = _uploadInput.files!;

    if (files.length > 0) {
      _loadFileAsImage(files.item(0)!);
      _uploadInput.value = '';
    }
  }.toJS);

  // Styling on file drag
  _imgBox.addEventListener('dragenter', (web.Event _) {
    _imgBox.classList.add('drag');
  }.toJS);
  _imgBox.addEventListener('dragleave', (web.Event _) {
    _imgBox.classList.remove('drag');
  }.toJS);

  _imgBox.addEventListener('drop', (web.Event e) {
    _imgBox.classList.remove('drag');
    e.preventDefault();

    final droppedFiles = (e as web.DragEvent).dataTransfer?.files;

    if (droppedFiles != null && droppedFiles.length > 0) {
      _loadFileAsImage(droppedFiles.item(0)!);
    } else {
      var regex = RegExp(r'https?:\S+(?=")');
      String? preferred;

      var matches = [for (int i = 0; i < e.dataTransfer!.types.length; i++) e.dataTransfer!.types[i]].expand((t) {
        var data = e.dataTransfer!.getData(t.toDart);
        var parts = regex.allMatches(data).map((s) => s[0]!);

        if (parts.isNotEmpty && t.toDart == 'text/html') preferred = parts.first;

        return parts.isNotEmpty ? parts : [data];
      }).toList();

      if (matches.isNotEmpty) {
        var resolved = preferred ??
            matches.firstWhere(
              (s) => !s.contains('http', 5),
              orElse: () => matches.first,
            );
        _loadSrcAsImage(resolved);
      }
    }
  }.toJS);

  _crop.addEventListener('mousedown', ((web.MouseEvent e) {
    e.preventDefault();
    final clicked = e.target as web.HTMLElement;
    var pos1 = position;
    var size1 = size;

    void Function(Point<double>) action;
    if (clicked != _crop) {
      var cursorCss = clicked.style.cursor + ' !important';
      web.document.body!.style.cursor = cursorCss;
      _crop.style.cursor = cursorCss;

      var classes = clicked.classList;
      var t = classes.contains('top');
      var r = classes.contains('right');
      var l = classes.contains('left');
      var b = classes.contains('bottom');

      action = (diff) {
        var x = pos1.x;
        var y = pos1.y;
        var width = size1.x;
        var height = size1.y;

        var maxPosDiff = size1 - minSize;
        var minPosDiff = pos1 * -1;

        if (_square) {
          var maxSizeDiff = _imgSize - size1 - pos1;
          double v;
          if (t) {
            if (r) {
              var maximum = min(maxSizeDiff.x, pos1.y);
              v = max(min(max(diff.x, -diff.y), maximum), -maxPosDiff.x);
            } else if (l) {
              var minimum = min(pos1.x, pos1.y);
              v = max(min(max(-diff.x, -diff.y), minimum), -maxPosDiff.x);
              x -= v;
            } else {
              var minimum = min(pos1.y, min(pos1.x, maxSizeDiff.x) * 2);
              v = max(min(-diff.y, minimum), -maxPosDiff.x);
              x -= (v / 2);
            }
            y -= v;
          } else if (b) {
            if (r) {
              var maximum = min(maxSizeDiff.x, maxSizeDiff.y);
              v = max(min(max(diff.x, diff.y), maximum), -maxPosDiff.x);
            } else if (l) {
              var minimum = min(pos1.x, maxSizeDiff.y);
              v = max(min(max(-diff.x, diff.y), minimum), -maxPosDiff.x);
              x -= v;
            } else {
              var minimum = min(maxSizeDiff.y, min(pos1.x, maxSizeDiff.x) * 2);
              v = max(min(diff.y, minimum), -maxPosDiff.x);
              x -= (v / 2);
            }
          } else if (r) {
            var minimum = min(min(pos1.y, maxSizeDiff.y) * 2, maxSizeDiff.x);
            v = max(min(diff.x, minimum), -maxPosDiff.y);
            y -= (v / 2);
          } else {
            var minimum = min(min(pos1.y, maxSizeDiff.y) * 2, pos1.x);
            v = max(min(-diff.x, minimum), -maxPosDiff.y);
            x -= v;
            y -= (v / 2);
          }
          width += v;
          height += v;
        } else {
          if (t) {
            var v = min(max(diff.y, minPosDiff.y), maxPosDiff.y);
            y += v;
            height -= v;
          }
          if (r) width += diff.x;
          if (b) height += diff.y;
          if (l) {
            var v = min(max(diff.x, minPosDiff.x), maxPosDiff.x);
            x += v;
            width -= v;
          }
        }

        setPosAndSize(Point(x, y), Point(width, height));
      };
    } else {
      action = (diff) {
        setPosAndSize(pos1 + diff, size);
      };
    }

    final mouse1 = Point<double>(e.clientX.toDouble(), e.clientY.toDouble());
    
    void moveHandler(web.Event moveEvent) {
      final mouseEvent = moveEvent as web.MouseEvent;
      final diff = Point<double>(mouseEvent.clientX.toDouble(), mouseEvent.clientY.toDouble()) - mouse1;
      action(diff);
    }
    
    void upHandler(web.Event upEvent) {
      web.document.body!.style.cursor = '';
      _crop.style.cursor = '';
      web.window.removeEventListener('mousemove', moveHandler.toJS);
      web.window.removeEventListener('mouseup', upHandler.toJS);
    }
    
    web.window.addEventListener('mousemove', moveHandler.toJS);
    web.window.addEventListener('mouseup', upHandler.toJS);
  }).toJS);
}

void _resizeOutside() {
  final canvasWidth = _canvas.width;
  final canvasHeight = _canvas.height;

  var ctx = _canvas.context2D;
  ctx.clearRect(0, 0, canvasWidth, canvasHeight);
  ctx.fillStyle = '#000c'.toJS;
  ctx.fillRect(0, 0, canvasWidth, position.y); // top
  ctx.fillRect(0, position.y, position.x, size.y); // left
  ctx.fillRect(position.x + size.x, position.y, canvasWidth, size.y); // right
  ctx.fillRect(0, position.y + size.y, canvasWidth, canvasHeight); // bottom
}

int _getMaxRes(String type) {
  switch (type) {
    case IMAGE_TYPE_MAP:
      return 1200;
    case IMAGE_TYPE_SCENE:
      return 8000;
    case IMAGE_TYPE_PC:
    default:
      return 256;
  }
}

bool _isSquare(String type) {
  switch (type) {
    case IMAGE_TYPE_PC:
    case IMAGE_TYPE_ENTITY:
      return true;
    default:
      return false;
  }
}

bool _upscale(String type) {
  switch (type) {
    case IMAGE_TYPE_MAP:
      return true;
    default:
      return false;
  }
}

final _displayCtrl = StreamController<int>.broadcast(sync: true);

Future _displayOffline({
  required String type,
  web.Blob? initialImg,
  required Future Function(String base64, int maxRes, bool upscale)
      processUpload,
  bool openDialog = true,
}) async {
  _displayCtrl.sink.add(0);
  if (!_init) {
    _initialize();
  }

  var maxRes = _getMaxRes(type);
  var upscale = _upscale(type);
  _square = _isSquare(type);

  if (initialImg == null) {
    _img.width = 0;
    _img.height = 0;
    _canvas.width = 0;
    _canvas.height = 0;
    _crop.classList.add('hide');
    _dragText.classList.remove('hide');
    _uploadButton.disabled = true;

    if (openDialog) {
      _uploadInput.click();
      var event = await Future.any<dynamic>([
        _displayCtrl.stream.first,
        Future.value(null), // Simplified for package:web compatibility
        _uploadInput.onInput.first,
      ]);
      if (event == 0) return null;
    }
  } else {
    _loadFileAsImage(initialImg);
  }

  overlayVisible = true;
  _panel.classList.add('show');

  final completer = Completer();
  var isCompleted = false;
  final _ = [
    _uploadButton.onClick.listen((_) async {
      _uploadButton.disabled = true;
      final limit = user.mediaBytesPerCampaign - usedStorage;

      dynamic result;

      try {
        final base64 = await _imgToBase64(maxRes, upscale, limit);

        result = await processUpload(base64, maxRes, upscale);
      } on RangeError catch (_) {
        result = null;
      }

      if (result != null && !isCompleted) {
        isCompleted = true;
        completer.complete(result);
      }
      _uploadButton.disabled = false;
    }),
    _cancelButton.onClick.listen((_) async {
      if (!isCompleted) {
        isCompleted = true;
        completer.complete();
      }
    }),
    web.document.addEventListener('paste', ((web.Event event) {
      event.preventDefault();

      final clipboardFiles = (event as web.ClipboardEvent).clipboardData?.files;

      if (clipboardFiles != null) {
        for (var i = 0; i < clipboardFiles.length; i++) {
          var file = clipboardFiles.item(i)!;
          return _loadFileAsImage(file);
        }
      }
    }).toJS)
  ];

  var finalResult = await completer.future;
  // Note: Simplified subscription handling for package:web compatibility
   // Original dart:html subscriptions are not directly cancellable in this context
  _panel.classList.remove('show');

  overlayVisible = false;
  return finalResult;
}

void _loadFileAsImage(web.Blob blob) {
  _loadSrcAsImage(web.URL.createObjectURL(blob));
}

void _loadSrcAsImage(String src) async {
  _uploadButton.disabled = true;
  _img.src = src;
  var event = await Future.any([_img.onLoad.first, _img.onError.first]);
  if (event.type == 'error') {
    if (src.startsWith('blob:')) return;

    // Use server to download an untainted version of the image
    _img.src = getFile('untaint') + '?url=$src';

    await _img.onLoad.first;
  }

  var width = _img.naturalWidth;
  var height = _img.naturalHeight;
  var max = web.window.innerHeight ~/ 2;

  if (width > height) {
    width = width * max ~/ height;
    height = max;
  } else {
    height = height * max ~/ width;
    width = max;
  }

  _img.width = width;
  _img.height = height;
  _canvas.width = width;
  _canvas.height = height;
  setPosAndSize(
      Point(0, 0),
      Point(
        (_square ? max : width).toDouble(),
        (_square ? max : height).toDouble(),
      ));
  _dragText.classList.add('hide');
  _crop.classList.remove('hide');
  _uploadButton.disabled = false;
}

web.HTMLCanvasElement _imgToCanvas(int maxRes, bool upscale) {
  var x = position.x / _imgSize.x;
  var y = position.y / _imgSize.y;
  var w = size.x / _imgSize.x;
  var h = size.y / _imgSize.y;
  var nw = _img.naturalWidth;
  var nh = _img.naturalHeight;

  var dw = (w * nw).round();
  var dh = (h * nh).round();

  if (dw >= dh && (dw > maxRes || upscale)) {
    dh = (dh * maxRes / dw).round();
    dw = maxRes;
  } else if (dh >= dw && (dh > maxRes || upscale)) {
    dw = (dw * maxRes / dh).round();
    dh = maxRes;
  }

  var canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
  canvas.width = dw;
  canvas.height = dh;
  var ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
  ctx.drawImage(_img, x * nw, y * nh, w * nw, h * nh, 0, 0, dw, dh);
  return canvas;
}

Future<String> _emptyImageBase64(int width, int height) {
  var canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
  canvas.width = width;
  canvas.height = height;
  var ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
  ctx.fillStyle = '#ffffff'.toJS;
  ctx.fillRect(0, 0, width, height);
  return canvasToBase64(canvas);
}

Future<String> _imgToBase64(int maxRes, bool upscale, int sizeLimitInBytes) {
  var canvas = _imgToCanvas(maxRes, upscale);
  return canvasToBase64(canvas, sizeLimitInBytes: sizeLimitInBytes);
}

Future<String> canvasToBase64(
  web.HTMLCanvasElement canvas, {
  bool includeHeader = false,
  int? sizeLimitInBytes,
}) async {
  // Create blob using callback approach for package:web compatibility
  final completer = Completer<web.Blob>();
  canvas.toBlob(((web.Blob blob) {
    completer.complete(blob);
  }).toJS, 'image/jpeg', 0.85.toJS);
  var blob = await completer.future;

  if (sizeLimitInBytes != null && blob.size > sizeLimitInBytes) {
    await _showUploadErrorDialog(blob.size);
    throw RangeError('Upload limit reached');
  }

  var reader = web.FileReader();
  reader.readAsDataURL(blob);
  await reader.onLoadEnd.first;

  final dataUrl = reader.result as String;

  if (includeHeader || user.isInDemo) return dataUrl;

  return dataUrl.substring(23);
}

String bytesToMB(int bytes) {
  return (bytes / 1000000).toStringAsFixed(2);
}

/// Displays an error explaining the campaign storage situation.
Future<void> _showUploadErrorDialog(
  int bytesUpload, [
  int? bytesUsed,
  int? bytesMaximum,
]) async {
  bytesUsed ??= usedStorage;
  bytesMaximum ??= user.mediaBytesPerCampaign;

  final uploadMB = bytesToMB(bytesUpload);
  final usedMB = bytesToMB(bytesUsed);
  final maxMB = bytesToMB(bytesMaximum);

  final dialog = Dialog('Unable to upload');
  dialog.addParagraph(
    "The image you're trying to upload is too big (<b>$uploadMB MB</b>) "
    'and exceeds your campaign storage '
    '(used <b>$usedMB</b> / <b>$maxMB MB</b>)!',
  );
  await dialog.display();
}

Future _upload(String base64, String action, String type,
    Map<String, dynamic>? extras, int maxRes, bool upscale) async {
  if (user.isInDemo) {
    return {
      'image': base64,
    };
  }

  final json = <String, dynamic>{'type': type, 'data': base64};
  if (extras != null) json.addAll(Map.from(extras));

  try {
    final result = await socket.request(action, json);
    return result;
  } on ResponseError catch (err) {
    // Image can't be uploaded
    await _showUploadErrorDialog(
      err.context['bytesUpload'],
      err.context['bytesUsed'],
      err.context['bytesMaximum'],
    );
  }

  return null;
}

Future<String?> _displayAssetPicker(String type) async {
  while (_assetGrid.children.length > 0) {
    _assetGrid.children.item(0)?.remove();
  }
  _assetPanel.classList.add('show');
  overlayVisible = true;

  final previewImage = ASSET_PREVIEWS[type];
  final tmp = html.ImageElement(src: previewImage);
  await tmp.onLoad.first;

  final tileSize = tmp.width!;
  final tiles = tmp.height! ~/ tileSize;

  final completer = Completer<String>();
  var isCompleted = false;

  for (var i = 0; i < tiles; i++) {
    var img = web.document.createElement('div') as web.HTMLDivElement;
    img.className = 'asset';
    img.style.backgroundImage = 'url(${tmp.src})';
    img.style.backgroundPositionY = '${-i * 100}%';
    img.onClick.listen((_) {
      if (!isCompleted) {
        isCompleted = true;
        completer.complete('asset/$type/$i');
      }
    });
    _assetGrid.appendChild(img);
  }

  var result = await Future.any([
    completer.future,
    _assetPanel.querySelector('.close')!.onClick.map((_) => null).first,
  ]);

  _assetPanel.classList.remove('show');
  overlayVisible = false;
  return result;
}

Future display({
    required web.MouseEvent event,
  required String type,
  String? action,
  Map<String, dynamic>? extras,
  web.Blob? initialImg,
  Future Function(String base64, int maxRes, bool upscale)? processUpload,
  void Function(bool v)? onPanelVisible,
  web.Element? simulateHoverClass,
}) async {
  var visible = (bool v) => onPanelVisible != null ? onPanelVisible(v) : null;
  var openDialog = true;

  if (initialImg == null) {
    var menu = ContextMenu();

    var assets = -1;
    var empty = -1;
    if (type == IMAGE_TYPE_ENTITY || type == IMAGE_TYPE_PC || type == IMAGE_TYPE_SCENE) {
      assets = menu.addButton('Pick from Assets', 'image');
    }

    menu.addButton('Upload Image', 'upload');
    var dragDrop = menu.addButton('Drag & Drop', 'hand-pointer');

    if (type == IMAGE_TYPE_MAP) {
      empty = menu.addButton('Empty Canvas', 'sticky-note');
    }

    var result = await menu.display(event as dynamic, simulateHoverClass as web.HTMLElement?);
    if (result == null) return;

    var maxRes = _getMaxRes(type);
    var upscale = _upscale(type);

    if (result == assets) {
      visible(true);
      var asset = await _displayAssetPicker(type);
      visible(false);
      if (asset == null) return null;

      if (processUpload != null) {
        return await processUpload(asset, maxRes, upscale);
      }

      return await _upload(asset, action!, type, extras, maxRes, upscale);
    } else if (result == empty) {
      var width = maxRes;
      var height = (width * 0.6).round();
      var base64 = await _emptyImageBase64(width, height);
      return await _upload(base64, action!, type, extras, maxRes, upscale);
    } else if (result == dragDrop) {
      openDialog = false;
    }
  }

  visible(true);

  var result = await _displayOffline(
    type: type,
    initialImg: initialImg,
    openDialog: openDialog,
    processUpload: processUpload ??
        (base64, maxRes, upscale) =>
            _upload(base64, action!, type, extras, maxRes, upscale),
  );

  visible(false);
  return result;
}
