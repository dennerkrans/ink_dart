// Port of ink's Value.cs: BoolValue.

import 'float_value.dart';
import 'int_value.dart';
import 'string_value.dart';
import 'value.dart';

class BoolValue extends Value<bool> {
  BoolValue(super.value);

  @override
  ValueType get valueType => ValueType.bool_;

  @override
  bool get isTruthy => value;

  @override
  AbstractValue cast(ValueType newType) {
    if (newType == valueType) return this;

    if (newType == ValueType.int_) return IntValue(value ? 1 : 0);

    if (newType == ValueType.float) return FloatValue(value ? 1.0 : 0.0);

    if (newType == ValueType.string) {
      return StringValue(value ? 'true' : 'false');
    }

    throw badCastException(newType);
  }

  // Instead of C# "True" / "False"
  @override
  String toString() => value ? 'true' : 'false';
}
