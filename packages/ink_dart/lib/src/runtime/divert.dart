// Port of ink's Divert.cs.

import 'container.dart';
import 'ink_object.dart';
import 'path.dart';
import 'pointer.dart';
import 'push_pop.dart';

class Divert extends InkObject {
  Divert() : pushesToStack = false;

  Divert.pushing(this.stackPushType) : pushesToStack = true;

  Path? get targetPath {
    // Resolve any relative paths to global ones as we come across them
    final tp = _targetPath;
    if (tp != null && tp.isRelative) {
      final targetObj = targetPointer.resolve();
      if (targetObj != null) _targetPath = targetObj.path;
    }
    return _targetPath;
  }

  set targetPath(Path? value) {
    _targetPath = value;
    _targetPointer = Pointer.nullPointer;
  }

  Path? _targetPath;

  Pointer get targetPointer {
    if (_targetPointer.isNull) {
      final tp = _targetPath;
      if (tp == null) return _targetPointer;
      final targetObj = resolvePath(tp).obj;

      final last = tp.lastComponent;
      if (last != null && last.isIndex) {
        final parent = targetObj?.parent;
        _targetPointer = Pointer(
          parent is Container ? parent : null,
          last.index,
        );
      } else {
        _targetPointer = Pointer.startOf(
          targetObj is Container ? targetObj : null,
        );
      }
    }
    return _targetPointer;
  }

  Pointer _targetPointer = Pointer.nullPointer;

  String? get targetPathString {
    final tp = targetPath;
    if (tp == null) return null;
    return compactPathString(tp);
  }

  set targetPathString(String? value) {
    if (value == null) {
      targetPath = null;
    } else {
      targetPath = Path.fromString(value);
    }
  }

  String? variableDivertName;

  bool get hasVariableTarget => variableDivertName != null;

  bool pushesToStack;
  PushPopType stackPushType = PushPopType.tunnel;

  bool isExternal = false;
  int externalArgs = 0;

  bool isConditional = false;

  /// Diverts with the same target are equal, as in the reference. This is
  /// observable: `InkObject.path` finds a child with `indexOf`, so the second
  /// of two identical diverts in a container gets the first one's path.
  @override
  bool operator ==(Object other) {
    if (other is Divert) {
      if (hasVariableTarget == other.hasVariableTarget) {
        if (hasVariableTarget) {
          return variableDivertName == other.variableDivertName;
        } else {
          return targetPath == other.targetPath;
        }
      }
    }
    return false;
  }

  @override
  int get hashCode {
    if (hasVariableTarget) {
      const variableTargetSalt = 12345;
      return variableDivertName.hashCode + variableTargetSalt;
    } else {
      const pathTargetSalt = 54321;
      return targetPath.hashCode + pathTargetSalt;
    }
  }

  @override
  String toString() {
    if (hasVariableTarget) {
      return 'Divert(variable: $variableDivertName)';
    } else if (targetPath == null) {
      return 'Divert(null)';
    } else {
      final sb = StringBuffer();

      var targetStr = targetPath.toString();
      final targetLineNum = debugLineNumberOfPath(targetPath);
      if (targetLineNum != null) targetStr = 'line $targetLineNum';

      sb.write('Divert');

      if (isConditional) sb.write('?');

      if (pushesToStack) {
        if (stackPushType == PushPopType.function) {
          sb.write(' function');
        } else {
          sb.write(' tunnel');
        }
      }

      sb.write(' -> ');
      sb.write(targetPathString);

      sb.write(' (');
      sb.write(targetStr);
      sb.write(')');

      return sb.toString();
    }
  }
}
