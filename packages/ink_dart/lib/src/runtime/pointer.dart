// Port of ink's Pointer.cs.

import 'container.dart';
import 'ink_object.dart';
import 'path.dart';

/// A position in the story: a container and an index into its content.
///
/// A struct in the reference, so an immutable value here: where C# mutates a
/// copy, the port builds a new pointer.
class Pointer {
  const Pointer(this.container, this.index);

  static Pointer startOf(Container? container) => Pointer(container, 0);

  static const Pointer nullPointer = Pointer(null, -1);

  final Container? container;
  final int index;

  InkObject? resolve() {
    final c = container;
    if (index < 0) return c;
    if (c == null) return null;
    if (c.content.isEmpty) return c;
    if (index >= c.content.length) return null;
    return c.content[index];
  }

  bool get isNull => container == null;

  Path? get path {
    final c = container;
    if (c == null) return null;
    if (index >= 0) {
      return c.path.pathByAppendingComponent(Component.index(index));
    } else {
      return c.path;
    }
  }

  @override
  String toString() {
    final c = container;
    if (c == null) return 'Ink Pointer (null)';
    return 'Ink Pointer -> ${c.path} -- index $index';
  }

  @override
  bool operator ==(Object other) =>
      other is Pointer &&
      identical(other.container, container) &&
      other.index == index;

  @override
  int get hashCode => Object.hash(identityHashCode(container), index);
}
