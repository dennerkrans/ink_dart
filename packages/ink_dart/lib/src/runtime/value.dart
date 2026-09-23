// Port of ink's Value.cs (inkjs Value.ts): the abstract value classes and
// ValueType. The concrete values live in their own files.

import '../float32.dart';
import '../story_exception.dart';
import 'bool_value.dart';
import 'divert_target_value.dart';
import 'float_value.dart';
import 'ink_list.dart';
import 'ink_object.dart';
import 'int_value.dart';
import 'list_value.dart';
import 'path.dart';
import 'string_value.dart';

/// Order is significant for type coercion: if types aren't directly
/// compatible for an operation, they're coerced to the same type, downward.
/// Higher value types "infect" an operation.
enum ValueType {
  // Bool is new addition, keep enum values the same, with Int==0, Float==1
  // etc, but for coersion rules, we want to keep bool with a lower value
  // than Int so that it converts in the right direction
  bool_(-1, 'Bool'),
  int_(0, 'Int'),
  float(1, 'Float'),
  list(2, 'List'),
  string(3, 'String'),

  // Not used for coersion described above
  divertTarget(4, 'DivertTarget'),
  variablePointer(5, 'VariablePointer');

  const ValueType(this.code, this.csName);

  /// The C# enum value, used for coercion order.
  final int code;

  /// The C# enum member name, as the reference prints it.
  final String csName;

  @override
  String toString() => csName;
}

abstract class AbstractValue extends InkObject {
  ValueType get valueType;
  bool get isTruthy;

  /// Returns null where the reference does (a string that doesn't parse).
  AbstractValue? cast(ValueType newType);

  Object? get valueObject;

  /// Builds a value from a game-side object: `bool`, `int`, `double`
  /// (stored as a 32-bit float), `String`, [Path] or [InkList].
  static AbstractValue? create(Object? val) {
    if (val is bool) {
      return BoolValue(val);
    } else if (val is int) {
      return IntValue(val.toSigned(32));
    } else if (val is double) {
      // Implicitly lose precision from any doubles we get passed in
      return FloatValue(toFloat32(val));
    } else if (val is String) {
      return StringValue(val);
    } else if (val is Path) {
      return DivertTargetValue(val);
    } else if (val is InkList) {
      return ListValue.fromList(val);
    }
    return null;
  }

  @override
  InkObject copy() {
    final c = create(valueObject);
    if (c == null) throw StateError('Failed to copy $this');
    return c;
  }

  StoryException badCastException(ValueType targetType) {
    return StoryException(
      "Can't cast ${csObjectToString(valueObject)} from $valueType to "
      '$targetType',
    );
  }
}

abstract class Value<T extends Object> extends AbstractValue {
  Value(this.value);

  T value;

  @override
  Object? get valueObject => value;

  @override
  String toString() => csObjectToString(value);
}

/// C#'s `object.ToString()` for the objects a value can hold: bools print
/// `True`/`False`, floats print in .NET's shortest round-trip form.
String csObjectToString(Object? o) {
  if (o == null) return '';
  if (o is bool) return o ? 'True' : 'False';
  if (o is double) return formatFloat32(o);
  return o.toString();
}
