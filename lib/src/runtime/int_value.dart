// Port of ink's Value.cs: IntValue.

import '../float32.dart';
import 'bool_value.dart';
import 'float_value.dart';
import 'string_value.dart';
import 'value.dart';

/// A 32-bit integer, as in the reference.
class IntValue extends Value<int> {
  IntValue(super.value);

  @override
  ValueType get valueType => ValueType.int_;

  @override
  bool get isTruthy => value != 0;

  @override
  AbstractValue cast(ValueType newType) {
    if (newType == valueType) return this;

    if (newType == ValueType.bool_) return BoolValue(value != 0);

    if (newType == ValueType.float) {
      return FloatValue(toFloat32(value.toDouble()));
    }

    if (newType == ValueType.string) return StringValue('$value');

    throw badCastException(newType);
  }
}
