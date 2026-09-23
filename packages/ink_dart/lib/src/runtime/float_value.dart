// Port of ink's Value.cs: FloatValue.

import '../float32.dart';
import 'bool_value.dart';
import 'int_value.dart';
import 'string_value.dart';
import 'value.dart';

/// A 32-bit float, as in the reference (`Value<float>`). [value] always
/// holds a double that is exactly representable as a float.
class FloatValue extends Value<double> {
  FloatValue(super.value);

  @override
  ValueType get valueType => ValueType.float;

  @override
  bool get isTruthy => value != 0.0;

  @override
  AbstractValue cast(ValueType newType) {
    if (newType == valueType) return this;

    if (newType == ValueType.bool_) return BoolValue(value != 0.0);

    if (newType == ValueType.int_) return IntValue(floatToInt32(value));

    if (newType == ValueType.string) return StringValue(formatFloat32(value));

    throw badCastException(newType);
  }

  @override
  String toString() => formatFloat32(value);
}

/// C#'s `(int)f` on .NET 10: truncates toward zero, saturates out-of-range
/// values, and maps NaN to 0.
int floatToInt32(double f) {
  if (f.isNaN) return 0;
  if (f >= 2147483647.0) return 2147483647;
  if (f <= -2147483648.0) return -2147483648;
  return f.truncate();
}
