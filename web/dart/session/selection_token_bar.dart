import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:dungeonclub/models/token_bar.dart';

import '../html/input_extension.dart';
import '../html/instance_component.dart';
import '../html_helpers.dart';
import 'movable.dart';
import 'selection_token_bar_config.dart';

class SelectionTokenBar extends InstanceComponent {
  static final panel = TokenBarConfigPanel();

  final Movable token;
  final TokenBar data;

  late web.HTMLElement _clickableContainer;
  late web.HTMLElement _iconElement;
  late web.HTMLElement _labelElement;
  late web.HTMLInputElement _valueInput;
  late web.HTMLInputElement _maxInput;

  double _previousValue;
  double _previousMaxValue;

  set styleHighlight(bool value) {
    htmlRoot.classList.toggle('highlight', value);
  }

  SelectionTokenBar(this.token, this.data)
      : _previousValue = data.value,
        _previousMaxValue = data.maxValue,
        super(web.document.createElement('li') as web.HTMLLIElement) {
    htmlRoot.className = 'list-setting';
    
    _clickableContainer = web.document.createElement('span') as web.HTMLSpanElement;
    _iconElement = icon('lock') as web.HTMLElement;
    _labelElement = web.document.createElement('span') as web.HTMLSpanElement;
    _clickableContainer.appendChild(_iconElement);
    _clickableContainer.appendChild(_labelElement);
    htmlRoot.appendChild(_clickableContainer);
    
    _valueInput = web.document.createElement('input') as web.HTMLInputElement;
    _valueInput.type = 'number';
    htmlRoot.appendChild(_valueInput);
    
    final separator = web.document.createElement('span') as web.HTMLSpanElement;
    separator.textContent = '/';
    htmlRoot.appendChild(separator);
    
    _maxInput = web.document.createElement('input') as web.HTMLInputElement;
    _maxInput.type = 'number';
    htmlRoot.appendChild(_maxInput);

    _clickableContainer.className = 'label interactable';
    _clickableContainer.addEventListener('click', (web.Event _) {
      panel.attachTo(this);
    }.toJS);

    _valueInput
      ..placeholder = 'Value...'
      ..step = 'any';
    _maxInput
      ..placeholder = 'Max...'
      ..step = 'any';

    _valueInput.registerSoftLimits(
      getMin: () => 0,
      getMax: () => data.maxValue,
    );

    _valueInput.listenLazyUpdate(
      onChange: (_) => _applyInputsToData(),
      onSubmit: (_) => submitData(),
    );

    _maxInput.listenLazyUpdate(
      onChange: (_) => _applyInputsToData(),
      onSubmit: (_) => submitData(),
    );

    applyDataToInputs();
  }

  void applyVisibilityIcon() {
    final showIcon = data.visibility != TokenBarVisibility.VISIBLE_TO_ALL;

    if (showIcon) {
      final hidden = data.visibility == TokenBarVisibility.HIDDEN;

      applyIconClasses(_iconElement, hidden ? 'user-slash' : 'user-lock');
      _clickableContainer.insertBefore(_iconElement, _clickableContainer.firstChild);
    } else {
      _iconElement.remove();
    }
  }

  void applyDataToInputs() {
    applyVisibilityIcon();
    _labelElement.textContent = data.label;
    _valueInput.valueAsNumber = data.value;
    _maxInput.valueAsNumber = data.maxValue;
  }

  bool _isValidNumber(num? number) {
    if (number == null) return false;

    return number.isFinite;
  }

  void _applyInputsToData() {
    final valueRaw = _valueInput.valueAsNumber;
    final maxRaw = _maxInput.valueAsNumber;

    if (_isValidNumber(valueRaw) && _isValidNumber(maxRaw)) {
      final value = valueRaw.toDouble();
      final max = maxRaw.toDouble();

      final valueDiff = value - _previousValue;
      final maxDiff = max - _previousMaxValue;

      final affectValueInsteadOfMax = valueDiff != 0;

      token.board.modifySelectedTokenBars(data, (token, bar) {
        if (affectValueInsteadOfMax) {
          if (valueDiff.abs() <= 1.0) {
            bar.value += valueDiff;
          } else {
            bar.value = value;
          }
        } else {
          if (maxDiff.abs() <= 1.0) {
            bar.maxValue += maxDiff;
          } else {
            bar.maxValue = max;
          }
        }

        final component = token.getTokenBarComponent(bar);
        component.applyData();
      });

      _previousValue = value;
      _previousMaxValue = max;
    }
  }

  void submitData() {
    token.board.sendSelectedMovablesUpdate();
  }
}
