import 'dart:async';
import 'package:web/web.dart' as web;

import 'package:dungeonclub/models/token_bar.dart';

import '../html/instance_component.dart';
import 'movable.dart';

class TokenBarComponent extends InstanceComponent {
  final Movable token;
  final TokenBar data;
  late web.HTMLSpanElement _labelElement;
  late web.HTMLSpanElement _valueElement;

  set _highlight(bool value) {
    htmlRoot.classList.toggle('active', value);
  }

  TokenBarComponent(this.token, this.data) : super(web.document.createElement('li') as web.HTMLLIElement) {
    htmlRoot
      ..className = 'token-bar'
      ..appendChild(web.document.createElement('div')..className = 'bar-fill')
      ..appendChild(_labelElement = web.document.createElement('span') as web.HTMLSpanElement..className = 'token-bar-label')
      ..appendChild(_valueElement = web.document.createElement('span') as web.HTMLSpanElement..className = 'token-bar-value');

    applyData();
  }

  @override
  List<StreamSubscription> initializeListeners() => [
        token.board.selected.onSetActive
            .listen((event) => updateHighlight(event.active)),
      ];

  void updateHighlight(Movable? activeToken) {
    final isDM = token.board.session.isDM;
    final isTokenSelected = token.board.selected.contains(token);

    if (!isDM || activeToken == null || !isTokenSelected) {
      _highlight = false;
      return;
    }

    _highlight = activeToken.bars.any(
      (activeBar) => activeBar.label == data.label,
    );
  }

  void applyData() {
    double progress;
    String valueText;

    if (data.maxValue == 0) {
      progress = 1;
      valueText = '${data.value}';
    } else {
      progress = data.value / data.maxValue;
      valueText = '${data.value} / ${data.maxValue}';
    }

    (htmlRoot as web.HTMLElement).style.setProperty('--progress', '$progress');
    (htmlRoot as web.HTMLElement).style.setProperty('--color', '${data.color}');
    _labelElement.textContent = data.label;
    _valueElement.textContent = valueText;
  }
}
