import 'package:web/web.dart' as web;

import '../html_helpers.dart';

class Component<T extends web.Element> {
  final T htmlRoot;

  Component.element(this.htmlRoot);

  Component(String rootSelector) : htmlRoot = queryDom(rootSelector);
}
