import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'html_helpers.dart';

web.HTMLElement registerEditImage(
  web.HTMLElement editImg, {
  required Future<String?> Function(web.MouseEvent ev, [web.Blob? initialFile]) upload,
  void Function(String src)? onSuccess,
}) {
  web.HTMLImageElement img = editImg.queryDom('img') as web.HTMLImageElement;

  editImg.addEventListener('dragenter', ((web.Event _) {
    editImg.classList.add('drag');
  }).toJS);
  editImg.addEventListener('dragleave', ((web.Event _) => editImg.classList.remove('drag')).toJS);

  void uploadAndUpdate(web.MouseEvent ev, [web.Blob? initialFile]) async {
    editImg.classList.remove('drag');
    var src = await upload(ev, initialFile);
    if (src != null) {
      img.src = src.startsWith('data')
          ? src
          : '$src?${DateTime.now().millisecondsSinceEpoch}';
      if (onSuccess != null) onSuccess(src);
    }
  }

  editImg.addEventListener('mousedown', ((web.MouseEvent ev) {
    if (ev.button == 0) uploadAndUpdate(ev);
  }).toJS);
  editImg.addEventListener('drop', ((web.DragEvent ev) {
    ev.preventDefault();

    final droppedFiles = ev.dataTransfer?.files;
    if (droppedFiles != null && droppedFiles.length > 0) {
      uploadAndUpdate(ev, droppedFiles.item(0));
    }
  }).toJS);
  
  return editImg;
}
