// Port of ink's VariableReference.cs.

import 'container.dart';
import 'ink_object.dart';
import 'path.dart';

class VariableReference extends InkObject {
  VariableReference([this.name]);

  /// Normal named variable
  String? name;

  /// Variable reference is actually a path for a visit (read) count
  Path? pathForCount;

  Container? get containerForCount {
    final p = pathForCount;
    return p == null ? null : resolvePath(p).container;
  }

  String? get pathStringForCount {
    final p = pathForCount;
    if (p == null) return null;
    return compactPathString(p);
  }

  set pathStringForCount(String? value) {
    pathForCount = value == null ? null : Path.fromString(value);
  }

  @override
  String toString() {
    if (name != null) {
      return 'var($name)';
    } else {
      return 'read_count($pathStringForCount)';
    }
  }
}
