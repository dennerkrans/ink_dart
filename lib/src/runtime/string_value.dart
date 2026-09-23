// Port of ink's Value.cs: StringValue.

import '../float32.dart';
import 'float_value.dart';
import 'int_value.dart';
import 'path.dart';
import 'value.dart';

class StringValue extends Value<String> {
  StringValue(super.value)
    : isNewline = value == '\n',
      isInlineWhitespace = _isAllInlineWhitespace(value);

  final bool isNewline;
  final bool isInlineWhitespace;

  bool get isNonWhitespace => !isNewline && !isInlineWhitespace;

  @override
  ValueType get valueType => ValueType.string;

  @override
  bool get isTruthy => value.isNotEmpty;

  @override
  AbstractValue? cast(ValueType newType) {
    if (newType == valueType) return this;

    if (newType == ValueType.int_) {
      final parsedInt = tryParseInt32(value);
      return parsedInt == null ? null : IntValue(parsedInt);
    }

    if (newType == ValueType.float) {
      final parsedFloat = parseFloat32(value);
      return parsedFloat == null ? null : FloatValue(parsedFloat);
    }

    throw badCastException(newType);
  }

  @override
  String toString() => value;

  static bool _isAllInlineWhitespace(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c != ' ' && c != '\t') return false;
    }
    return true;
  }
}
