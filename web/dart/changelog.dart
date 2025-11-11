import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'package:ambience/ambience.dart';
import 'package:intl/intl.dart';

import 'communication.dart';
import 'html_helpers.dart';

final changelog = Changelog().._init();

class Changelog {
  web.HTMLElement get button => queryDom('#changelogButton') as web.HTMLElement;
  web.HTMLElement get root => queryDom('#changelog') as web.HTMLElement;
  late int? lastChangeCount;
  late int currentChangeCount;

  void _init() {
    button.addEventListener('click', ((web.MouseEvent ev) {
      var btnClick = ev.target == button;
      bool show;
      if (btnClick) {
        button.classList.toggle('active');
        show = button.classList.contains('active');
      } else {
        button.classList.add('active');
        show = true;
      }

      if (show) {
        button.classList.remove('new');
        _updateLastKnown();
      }
    }).toJS);
    
    button.addEventListener('mouseleave', ((web.Event _) => button.classList.remove('active')).toJS);

    var saved = web.window.localStorage.getItem('changelog');
    if (saved != null) {
      lastChangeCount = int.parse(saved);
    } else {
      lastChangeCount = null;
    }
  }

  void _updateLastKnown() {
    lastChangeCount = currentChangeCount;
    web.window.localStorage.setItem('changelog', '$lastChangeCount');
  }

  Future<void> fetch() async {
    var uri = Uri.parse(getFile('CHANGELOG.md'));
    var content = await httpClient.read(uri);
    _applyContent(content);
  }

  void _applyContent(String s) {
    _applyLog(_parseContent(s));
  }

  void _applyLog(List<LoggedChange> changes) {
    var elements = root.querySelectorAll('li');
    for (var i = 0; i < elements.length; i++) {
      var element = elements.item(i);
      if (element != null) {
        element.parentNode?.removeChild(element);
      }
    }

    currentChangeCount = changes.length;
    if (lastChangeCount == null) _updateLastKnown();

    var diff = currentChangeCount - lastChangeCount!;
    if (diff > 0) button.classList.add('new');

    for (var change in changes) {
      var isNew = diff-- > 0;

      var li = web.document.createElement('li') as web.HTMLLIElement;
      li.innerHTML = change.title.toJS;
      if (isNew) li.classList.add('new');
      
      for (var changeText in change.changes) {
        var subLi = web.document.createElement('li') as web.HTMLLIElement;
        subLi.innerHTML = changeText.toJS;
        li.appendChild(subLi);
      }
      
      root.appendChild(li);
    }
  }

  List<LoggedChange> _parseContent(String s) {
    var changes = <LoggedChange>[];
    var versions = s.split('##').where((e) => e.trim().isNotEmpty);
    for (var v in versions) {
      var change = _parseChange(v);
      changes.add(change);
    }

    return changes;
  }

  LoggedChange _parseChange(String s) {
    var lines = s.split('\n').map((l) => l.trim()).toList();

    return LoggedChange(
        lines[0],
        lines.skip(1).where((line) => line.isNotEmpty).map((e) {
          return formatToHtml(formatToHtml(e.substring(2), tag: 'i'),
                  markdown: '`')
              .replaceAll('[', '<span>')
              .replaceAll(']', '</span>');
        }));
  }
}

class LoggedChange {
  final DateTime date;
  final Iterable<String> changes;
  late String title;

  LoggedChange(String header, this.changes) : date = parseDate(header) {
    var outputFormat = DateFormat('MMM d, yyyy');
    title = outputFormat.format(date);

    var nameStart = header.indexOf(' ');
    if (nameStart >= 0) {
      var name = header.substring(nameStart + 1).trim();
      title += ' ' + wrapAround(name, 'i');
    }
  }

  static DateTime parseDate(String s) {
    var inputFormat = DateFormat('d-M-y');
    return inputFormat.parse(s, true);
  }
}
