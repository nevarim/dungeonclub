import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'component.dart';

class PopupPanel extends Component {
  bool _visible = false;
  bool get visible => _visible;
  set visible(bool visible) {
    _visible = visible;
    (htmlRoot).classList.toggle('show', visible);

    if (visible) {
      (htmlRoot).addEventListener('mouseleave', (web.Event _) {
        this.visible = false;
      }.toJS);
    }
  }

  PopupPanel(String rootSelector) : super(rootSelector) {
    visible = false;
  }
}
