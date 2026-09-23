// Port of ink's Value.cs: DivertTargetValue.

import '../system_exception.dart';
import 'path.dart';
import 'value.dart';

class DivertTargetValue extends Value<Path> {
  DivertTargetValue(super.value);

  Path get targetPath => value;
  set targetPath(Path v) => value = v;

  @override
  ValueType get valueType => ValueType.divertTarget;

  @override
  bool get isTruthy => throw SystemException(
    "Shouldn't be checking the truthiness of a divert target",
  );

  @override
  AbstractValue cast(ValueType newType) {
    if (newType == valueType) return this;
    throw badCastException(newType);
  }

  @override
  String toString() => 'DivertTargetValue($targetPath)';
}
