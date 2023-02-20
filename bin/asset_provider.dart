import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;

import 'controlled_resource.dart';

final _dirAssets = <String, List<FileSystemEntity>>{};

Future<void> resizeAll(String dirPath, {int size = 2000}) async {
  var directory = Directory(dirPath);

  for (var f in await directory.list().toList()) {
    var ext = p.extension(f.path).toLowerCase();
    if (ext == '.png' || ext == '.jpg') {
      File file = f;
      var img = image.decodeImage(await file.readAsBytes());
      if (img.width != size && img.height != size) {
        print('Resizing ${f.path}');
        var useWidth = img.width >= img.height;

        img = image.copyResize(img,
            width: useWidth ? size : null,
            height: useWidth ? null : size,
            interpolation: image.Interpolation.average);

        await file.writeAsBytes(image.encodeJpg(img, quality: 90));
      }
    }
  }
  print('Resized images in $dirPath');
}

Future<void> createAssetPreview(
  String dirPath, {
  int tileSize = 192,
  bool usePng = false,
  bool zoomIn = false,
}) async {
  var file = File(dirPath + '-preview');
  var directory = Directory(dirPath);

  if (await file.exists() || !await directory.exists()) return;

  print('Writing asset preview ${file.path}...');

  var sources = await directory.list().where((f) {
    var ext = p.extension(f.path).toLowerCase();
    return ext == '.png' || ext == '.jpg';
  }).toList()
    ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

  if (sources.isEmpty) return null;

  var img = image.Image(tileSize, sources.length * tileSize);

  for (var i = 0; i < sources.length; i++) {
    File src = sources[i];
    var srcImg = image.decodeImage(await src.readAsBytes());

    if (zoomIn) {
      var cx = srcImg.width ~/ 2;
      var cy = srcImg.height ~/ 2;
      var size = (srcImg.height * 0.6).round();
      var inset = size ~/ 2;

      srcImg = image.copyCrop(srcImg, cx - inset, cy - inset, size, size);
      srcImg = image.copyResize(srcImg,
          width: tileSize,
          height: tileSize,
          interpolation: image.Interpolation.average);
    } else {
      srcImg = image.copyResizeCropSquare(srcImg, tileSize);
    }

    img = image.copyInto(img, srcImg, dstY: tileSize * i);
  }

  var bytes = usePng ? image.encodePng(img) : image.encodeJpg(img, quality: 90);

  await file.writeAsBytes(bytes);
  print('Wrote ${bytes.length ~/ 1000} KB!');
}

Future<AssetFile> getAssetFile(String assetPath) async {
  var type = assetPath.substring(14, assetPath.indexOf('/', 14));
  var dir = 'web/images/assets/$type/';

  if (_dirAssets[dir] == null) {
    _dirAssets[dir] = await Directory(dir).list().toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  }

  var assetIndex = int.parse(p.basename(assetPath));

  // Only a single battle map asset is included in the repo.
  // In the demo, asset 15 gets requested by default, which throws an error.
  // As a workaround, respond with the first map if (and only if)
  // it's the only available one.
  if (assetIndex == 15 && _dirAssets[dir].length == 1) {
    assetIndex = 0;
  }
  return AssetFile.fromFile(_dirAssets[dir][assetIndex]);
}
