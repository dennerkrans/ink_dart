// Port of ink's Value.cs: ListValue.

import '../float32.dart';
import 'float_value.dart';
import 'ink_list.dart';
import 'ink_list_item.dart';
import 'ink_object.dart';
import 'int_value.dart';
import 'string_value.dart';
import 'value.dart';

class ListValue extends Value<InkList> {
  ListValue() : super(InkList());

  ListValue.fromList(InkList list) : super(InkList.from(list));

  ListValue.single(InkListItem singleItem, int singleValue)
    : super(InkList()..add(singleItem, singleValue));

  @override
  ValueType get valueType => ValueType.list;

  // Truthy if it is non-empty
  @override
  bool get isTruthy => value.count > 0;

  @override
  AbstractValue cast(ValueType newType) {
    if (newType == ValueType.int_) {
      final max = value.maxItem;
      if (max.key.isNull) {
        return IntValue(0);
      } else {
        return IntValue(max.value);
      }
    } else if (newType == ValueType.float) {
      final max = value.maxItem;
      if (max.key.isNull) {
        return FloatValue(0.0);
      } else {
        return FloatValue(toFloat32(max.value.toDouble()));
      }
    } else if (newType == ValueType.string) {
      final max = value.maxItem;
      if (max.key.isNull) {
        return StringValue('');
      } else {
        return StringValue(max.key.toString());
      }
    }

    if (newType == valueType) return this;

    throw badCastException(newType);
  }

  static void retainListOriginsForAssignment(
    InkObject? oldValue,
    InkObject newValue,
  ) {
    // When assigning the empty list, try to retain any initial origin names
    if (oldValue is ListValue &&
        newValue is ListValue &&
        newValue.value.count == 0) {
      newValue.value.setInitialOriginNames(oldValue.value.originNames);
    }
  }
}
