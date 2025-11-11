import 'package:web/web.dart' as web;

E queryDom<E extends web.Element>(String selectors) {
  return web.document.querySelector(selectors) as E;
}

extension ElementExtension on web.Element {
  E queryDom<E extends web.Element>(String selectors) {
    return this.querySelector(selectors) as E;
  }
}

web.Element icon(String id, {bool isBrand = false}) {
  final element = web.document.createElement('i');
  applyIconClasses(element, id);

  return element;
}

void applyIconClasses(web.Element element, String iconId, {bool isBrand = false}) {
  element.className = [
    isBrand ? 'fab' : 'fas',
    'fa-$iconId',
  ].join(' ');
}

String iconHtml(String id) {
  return '<i class="fas fa-$id"></i>';
}

web.HTMLButtonElement iconButton(String ico, {String? className, String? label}) {
  final button = web.document.createElement('button') as web.HTMLButtonElement;
  button.className = ['icon', if (className != null) className].join(' ');
  if (label != null) button.textContent = label;
  button.appendChild(icon(ico));
  return button;
}

String formatToHtml(
  String text, {
  String markdown = r'\*',
  String tag = 'b',
  String? tagClass,
}) {
  // Match between markdown char
  var _regex = RegExp(markdown + r'.*?' + markdown, dotAll: true);

  return text.replaceAllMapped(_regex, (match) {
    final matchText = match[0]!;
    final part = matchText.substring(1, matchText.length - 1);
    return wrapAround(part, tag, tagClass);
  });
}

String wrapAround(String content, String tag, [String? className]) {
  return [
    '<$tag',
    if (className != null) ' class="$className"',
    '>$content</$tag>',
  ].join();
}
