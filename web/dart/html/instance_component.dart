import 'dart:async';
import 'package:web/web.dart' as web;

import 'component.dart';
import 'instance_list.dart';

abstract class InstanceComponent<T extends web.Element> extends Component<T> {
  late List<StreamSubscription> _listeners;

  InstanceComponent(T htmlRoot) : super.element(htmlRoot) {
    _listeners = initializeListeners();
  }

  List<StreamSubscription> initializeListeners() => [];

  void dispose(InstanceList list) {
    htmlRoot.remove();

    for (var listener in _listeners) {
      listener.cancel();
    }
  }
}
