import 'package:web/web.dart' as web;

import 'html_helpers.dart';

void showPage(String id) {
  var elements = web.document.querySelectorAll('section.show');
  for (var i = 0; i < elements.length; i++) {
    var element = elements.item(i) as web.HTMLElement?;
    element?.classList.remove('show');
  }
  (queryDom('section#$id') as web.HTMLElement).classList.add('show');
}
