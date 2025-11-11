import 'package:web/web.dart' as web;

import 'package:dungeonclub/reactive/list.dart';

import 'instance_component.dart';

class InstanceList<E extends InstanceComponent> extends ReactiveList<E> {
  final web.Element itemContainer;

  InstanceList(this.itemContainer);

  @override
  void add(E value) {
    itemContainer.append(value.htmlRoot);
    super.add(value);
  }

  @override
  void remove(E value) {
    value.dispose(this);
    super.remove(value);
  }

  @override
  void clear() {
    for (final instance in this) {
      instance.dispose(this);
    }
    super.clear();
  }
}
