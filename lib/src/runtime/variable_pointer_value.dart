// Port of ink's Value.cs: VariablePointerValue.

import '../system_exception.dart';
import 'ink_object.dart';
import 'value.dart';

class VariablePointerValue extends Value<String> {
  VariablePointerValue(super.variableName, [this.contextIndex = -1]);

  String get variableName => value;
  set variableName(String v) => value = v;

  /// Where the variable is located:
  /// -1 = default, unknown, yet to be determined;
  /// 0 = in global scope;
  /// 1+ = callstack element index + 1 (so that the first doesn't conflict
  /// with special global scope).
  int contextIndex;

  @override
  ValueType get valueType => ValueType.variablePointer;

  @override
  bool get isTruthy => throw SystemException(
    "Shouldn't be checking the truthiness of a variable pointer",
  );

  @override
  AbstractValue cast(ValueType newType) {
    if (newType == valueType) return this;
    throw badCastException(newType);
  }

  @override
  String toString() => 'VariablePointerValue($variableName)';

  @override
  InkObject copy() => VariablePointerValue(variableName, contextIndex);
}
