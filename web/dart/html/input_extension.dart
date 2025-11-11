import 'package:web/web.dart' as web;
import 'dart:js_interop';

const _softLimitCooldownMs = 500;

extension InputLimiter on web.HTMLInputElement {
  void listenLazyUpdate({
    required void Function(String s) onChange,
    required void Function(String s) onSubmit,
    void Function()? onFocus,
  }) {
    late String startValue;
    late String typedValue;

    void update() {
      if (startValue != typedValue) {
        startValue = typedValue;
        onChange(typedValue);
        onSubmit(typedValue);
      }
    }

    void onFoc() {
      startValue = value;
      if (onFocus != null) onFocus();
      typedValue = value;
    }

    addEventListener('mousedown', ((web.Event _) {
      // Firefox number inputs can trigger onInput without being focused
      var isFocused = web.document.activeElement == this;
      if (!isFocused) {
        focus();
        onFoc();
      }
    }).toJS);

    addEventListener('focus', ((web.Event _) => onFoc()).toJS);
    addEventListener('change', ((web.Event _) => update()).toJS);
    addEventListener('input', ((web.Event _) {
      onChange(typedValue = value);
    }).toJS);
    addEventListener('blur', ((web.Event _) => update()).toJS);
  }

  void registerSoftLimits({
    required double Function() getMin,
    required double Function() getMax,
  }) {
    int lastInput = 0;
    num? previousValue = valueAsNumber;

    void onStepChange(web.Event event, num previous, num value, int now) {
      final min = getMin();
      final max = getMax();

      final crossingLowerBound = previous >= min && value < min;
      final crossingUpperBound = previous <= max && value > max;

      if (crossingLowerBound || crossingUpperBound) {
        final msSinceInput = now - lastInput;

        if (msSinceInput < _softLimitCooldownMs) {
          // Constrain range
          event.preventDefault();

          if (crossingLowerBound) {
            valueAsNumber = value = min;
          } else if (crossingUpperBound) {
            valueAsNumber = value = max;
          }
        }
      }
    }

    addEventListener('input', ((web.Event event) {
      final value = valueAsNumber;
      final previous = previousValue;

      final now = DateTime.now().millisecondsSinceEpoch;

      if (previous != null) {
        final diff = (value - previous).abs();

        if (diff == 1.0) {
          onStepChange(event, previous, value, now);
        }
      }

      lastInput = now;
      previousValue = valueAsNumber;
    }).toJS);
  }
}
