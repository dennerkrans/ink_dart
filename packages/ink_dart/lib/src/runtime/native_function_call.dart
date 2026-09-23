// Port of ink's NativeFunctionCall.cs.
//
// Arithmetic follows the C# runtime: ints are 32-bit and wrap, floats are
// 32-bit (every result is rounded with toFloat32), and POW on ints returns a
// float.

import 'dart:math' as math;

import '../float32.dart';
import '../story_exception.dart';
import '../system_exception.dart';
import 'bool_value.dart';
import 'float_value.dart';
import 'ink_list.dart';
import 'ink_object.dart';
import 'int_value.dart';
import 'list_definition.dart';
import 'list_value.dart';
import 'path.dart';
import 'string_value.dart';
import 'value.dart';
import 'void.dart';

typedef _BinaryOp = AbstractValue Function(Object left, Object right);
typedef _UnaryOp = AbstractValue Function(Object val);

class NativeFunctionCall extends InkObject {
  static const add = '+';
  static const subtract = '-';
  static const divide = '/';
  static const multiply = '*';
  static const mod = '%';
  static const negate = '_'; // distinguish from "-" for subtraction

  static const equal = '==';
  static const greater = '>';
  static const less = '<';
  static const greaterThanOrEquals = '>=';
  static const lessThanOrEquals = '<=';
  static const notEquals = '!=';
  static const not = '!';

  static const and = '&&';
  static const or = '||';

  static const min = 'MIN';
  static const max = 'MAX';

  static const pow = 'POW';
  static const floor = 'FLOOR';
  static const ceiling = 'CEILING';
  static const int_ = 'INT';
  static const float = 'FLOAT';

  static const has = '?';
  static const hasnt = '!?';
  static const intersect = '^';

  static const listMin = 'LIST_MIN';
  static const listMax = 'LIST_MAX';
  static const all = 'LIST_ALL';
  static const count = 'LIST_COUNT';
  static const valueOfList = 'LIST_VALUE';
  static const invert = 'LIST_INVERT';

  static NativeFunctionCall callWithName(String functionName) =>
      NativeFunctionCall(functionName);

  static bool callExistsWithName(String functionName) {
    _generateNativeFunctionsIfNecessary();
    return _nativeFunctions.containsKey(functionName);
  }

  NativeFunctionCall(String name) {
    _generateNativeFunctionsIfNecessary();
    this.name = name;
  }

  // Only called internally to generate prototypes
  NativeFunctionCall._prototype(String name, int numberOfParameters)
    : _isPrototype = true {
    this.name = name;
    this.numberOfParameters = numberOfParameters;
  }

  String get name => _name;

  set name(String value) {
    _name = value;
    if (!_isPrototype) _prototype = _nativeFunctions[_name];
  }

  String _name = '';

  int get numberOfParameters {
    final p = _prototype;
    return p != null ? p.numberOfParameters : _numberOfParameters;
  }

  set numberOfParameters(int value) => _numberOfParameters = value;

  int _numberOfParameters = 0;

  InkObject? call(List<InkObject> parameters) {
    final prototype = _prototype;
    if (prototype != null) return prototype.call(parameters);

    if (numberOfParameters != parameters.length) {
      throw SystemException('Unexpected number of parameters');
    }

    var hasList = false;
    for (final p in parameters) {
      if (p is Void) {
        throw StoryException(
          'Attempting to perform $name on a void value. Did you forget to '
          "'return' a value from a function you called here?",
        );
      }
      if (p is ListValue) hasList = true;
    }

    // Binary operations on lists are treated outside of the standard
    // coerscion rules
    if (parameters.length == 2 && hasList) {
      return _callBinaryListOperation(parameters);
    }

    final coercedParams = _coerceValuesToSingleType(parameters);
    final coercedType = coercedParams[0].valueType;

    if (coercedType == ValueType.int_ ||
        coercedType == ValueType.float ||
        coercedType == ValueType.string ||
        coercedType == ValueType.divertTarget ||
        coercedType == ValueType.list) {
      return _callType(coercedParams);
    }

    return null;
  }

  AbstractValue _callType(List<AbstractValue> parametersOfSingleType) {
    final param1 = parametersOfSingleType[0];
    final valType = param1.valueType;

    final paramCount = parametersOfSingleType.length;

    if (paramCount == 2 || paramCount == 1) {
      final opForTypeObj = _operationFuncs?[valType];
      if (opForTypeObj == null) {
        throw StoryException("Cannot perform operation '$name' on $valType");
      }

      final val1 = _raw(param1);

      // Binary
      if (paramCount == 2) {
        final val2 = _raw(parametersOfSingleType[1]);
        return (opForTypeObj as _BinaryOp)(val1, val2);
      }
      // Unary
      else {
        return (opForTypeObj as _UnaryOp)(val1);
      }
    } else {
      throw SystemException(
        'Unexpected number of parameters to NativeFunctionCall: '
        '${parametersOfSingleType.length}',
      );
    }
  }

  static Object _raw(AbstractValue v) {
    final o = v.valueObject;
    if (o == null) throw SystemException('Value has no value: $v');
    return o;
  }

  AbstractValue _callBinaryListOperation(List<InkObject> parameters) {
    // List-Int addition/subtraction returns a List (e.g. "alpha" + 1 = "beta")
    if ((name == '+' || name == '-') &&
        parameters[0] is ListValue &&
        parameters[1] is IntValue) {
      return _callListIncrementOperation(parameters);
    }

    final v1 = parameters[0] as AbstractValue;
    final v2 = parameters[1] as AbstractValue;

    // And/or with any other type requires coerscion to bool (int)
    if ((name == '&&' || name == '||') &&
        (v1.valueType != ValueType.list || v2.valueType != ValueType.list)) {
      final op = _operationFuncs?[ValueType.int_] as _BinaryOp;
      final result = op(v1.isTruthy ? 1 : 0, v2.isTruthy ? 1 : 0);
      return BoolValue((result as BoolValue).value);
    }

    // Normal (list • list) operation
    if (v1.valueType == ValueType.list && v2.valueType == ValueType.list) {
      return _callType([v1, v2]);
    }

    throw StoryException(
      "Can not call use '$name' operation on ${v1.valueType} and "
      '${v2.valueType}',
    );
  }

  AbstractValue _callListIncrementOperation(List<InkObject> listIntParams) {
    final listVal = listIntParams[0] as ListValue;
    final intVal = listIntParams[1] as IntValue;

    final resultRawList = InkList();

    for (final listItemWithValue in listVal.value.entries) {
      final listItem = listItemWithValue.key;
      final listItemValue = listItemWithValue.value;

      // Find + or - operation
      final intOp = _operationFuncs?[ValueType.int_] as _BinaryOp;

      // Return value unknown until it's evaluated
      final targetInt = (intOp(listItemValue, intVal.value) as IntValue).value;

      // Find this item's origin (linear search should be ok, should be short haha)
      ListDefinition? itemOrigin;
      for (final origin in listVal.value.origins ?? const <ListDefinition>[]) {
        if (origin.name == listItem.originName) {
          itemOrigin = origin;
          break;
        }
      }
      if (itemOrigin != null) {
        final incrementedItem = itemOrigin.tryGetItemWithValue(targetInt);
        if (incrementedItem != null) {
          resultRawList.add(incrementedItem, targetInt);
        }
      }
    }

    return ListValue.fromList(resultRawList);
  }

  List<AbstractValue> _coerceValuesToSingleType(List<InkObject> parametersIn) {
    var valType = ValueType.int_;

    ListValue? specialCaseList;

    // Find out what the output type is
    // "higher level" types infect both so that binary operations
    // use the same type on both sides. e.g. binary operation of
    // int and float causes the int to be casted to a float.
    for (final obj in parametersIn) {
      final val = obj as AbstractValue;
      if (val.valueType.code > valType.code) valType = val.valueType;

      if (val.valueType == ValueType.list) specialCaseList = val as ListValue;
    }

    // Coerce to this chosen type
    final parametersOut = <AbstractValue>[];

    // Special case: Coercing to Ints to Lists
    // We have to do it early when we have both parameters
    // to hand - so that we can make use of the List's origin
    if (valType == ValueType.list) {
      for (final obj in parametersIn) {
        final val = obj as AbstractValue;
        if (val.valueType == ValueType.list) {
          parametersOut.add(val);
        } else if (val.valueType == ValueType.int_) {
          final intVal = (val as IntValue).value;
          final list = specialCaseList?.value.originOfMaxItem;
          if (list == null) {
            throw SystemException(
              'Object reference not set to an instance of an object.',
            );
          }

          final item = list.tryGetItemWithValue(intVal);
          if (item != null) {
            parametersOut.add(ListValue.single(item, intVal));
          } else {
            throw StoryException(
              'Could not find List item with the value $intVal in '
              '${list.name}',
            );
          }
        } else {
          throw StoryException(
            'Cannot mix Lists and ${val.valueType} values in this operation',
          );
        }
      }
    }
    // Normal Coercing (with standard casting)
    else {
      for (final obj in parametersIn) {
        final castedValue = (obj as AbstractValue).cast(valType);
        if (castedValue == null) {
          throw SystemException(
            'Object reference not set to an instance of an object.',
          );
        }
        parametersOut.add(castedValue);
      }
    }

    return parametersOut;
  }

  static int _wrap(int x) => x.toSigned(32);

  static void _checkDivisor(int x, int y) {
    if (y == 0) throw SystemException('Attempted to divide by zero.');
    if (x == -0x80000000 && y == -1) {
      throw SystemException('Arithmetic operation resulted in an overflow.');
    }
  }

  static double _f(double x) => toFloat32(x);

  static void _generateNativeFunctionsIfNecessary() {
    if (_nativeFunctions.isNotEmpty) return;

    // Why no bool operations?
    // Before evaluation, all bools are coerced to ints in
    // CoerceValuesToSingleType (see default value for valType at top).
    // So, no operations are ever directly done in bools themselves.
    // This also means that 1 == true works, since true is always converted
    // to 1 first.
    // However, many operations return a "native" bool (equals, etc).

    // Int operations
    _addIntBinaryOp(add, (x, y) => IntValue(_wrap(x + y)));
    _addIntBinaryOp(subtract, (x, y) => IntValue(_wrap(x - y)));
    _addIntBinaryOp(multiply, (x, y) => IntValue(_wrap(x * y)));
    _addIntBinaryOp(divide, (x, y) {
      _checkDivisor(x, y);
      return IntValue(x ~/ y);
    });
    _addIntBinaryOp(mod, (x, y) {
      _checkDivisor(x, y);
      return IntValue(x.remainder(y));
    });
    _addIntUnaryOp(negate, (x) => IntValue(_wrap(-x)));

    _addIntBinaryOp(equal, (x, y) => BoolValue(x == y));
    _addIntBinaryOp(greater, (x, y) => BoolValue(x > y));
    _addIntBinaryOp(less, (x, y) => BoolValue(x < y));
    _addIntBinaryOp(greaterThanOrEquals, (x, y) => BoolValue(x >= y));
    _addIntBinaryOp(lessThanOrEquals, (x, y) => BoolValue(x <= y));
    _addIntBinaryOp(notEquals, (x, y) => BoolValue(x != y));
    _addIntUnaryOp(not, (x) => BoolValue(x == 0));

    _addIntBinaryOp(and, (x, y) => BoolValue(x != 0 && y != 0));
    _addIntBinaryOp(or, (x, y) => BoolValue(x != 0 || y != 0));

    _addIntBinaryOp(max, (x, y) => IntValue(math.max(x, y)));
    _addIntBinaryOp(min, (x, y) => IntValue(math.min(x, y)));

    // Have to cast to float since you could do POW(2, -1)
    _addIntBinaryOp(
      pow,
      (x, y) => FloatValue(_f(math.pow(x.toDouble(), y.toDouble()).toDouble())),
    );
    _addIntUnaryOp(floor, IntValue.new);
    _addIntUnaryOp(ceiling, IntValue.new);
    _addIntUnaryOp(int_, IntValue.new);
    _addIntUnaryOp(float, (x) => FloatValue(_f(x.toDouble())));

    // Float operations
    _addFloatBinaryOp(add, (x, y) => FloatValue(_f(x + y)));
    _addFloatBinaryOp(subtract, (x, y) => FloatValue(_f(x - y)));
    _addFloatBinaryOp(multiply, (x, y) => FloatValue(_f(x * y)));
    _addFloatBinaryOp(divide, (x, y) => FloatValue(_f(x / y)));
    // TODO: Is this the operation we want for floats?
    _addFloatBinaryOp(mod, (x, y) => FloatValue(_f(x.remainder(y))));
    _addFloatUnaryOp(negate, (x) => FloatValue(-x));

    _addFloatBinaryOp(equal, (x, y) => BoolValue(x == y));
    _addFloatBinaryOp(greater, (x, y) => BoolValue(x > y));
    _addFloatBinaryOp(less, (x, y) => BoolValue(x < y));
    _addFloatBinaryOp(greaterThanOrEquals, (x, y) => BoolValue(x >= y));
    _addFloatBinaryOp(lessThanOrEquals, (x, y) => BoolValue(x <= y));
    _addFloatBinaryOp(notEquals, (x, y) => BoolValue(x != y));
    _addFloatUnaryOp(not, (x) => BoolValue(x == 0.0));

    _addFloatBinaryOp(and, (x, y) => BoolValue(x != 0.0 && y != 0.0));
    _addFloatBinaryOp(or, (x, y) => BoolValue(x != 0.0 || y != 0.0));

    _addFloatBinaryOp(max, (x, y) => FloatValue(math.max(x, y)));
    _addFloatBinaryOp(min, (x, y) => FloatValue(math.min(x, y)));

    _addFloatBinaryOp(pow, (x, y) => FloatValue(_f(math.pow(x, y).toDouble())));
    _addFloatUnaryOp(floor, (x) => FloatValue(_f(x.floorToDouble())));
    _addFloatUnaryOp(ceiling, (x) => FloatValue(_f(x.ceilToDouble())));
    _addFloatUnaryOp(int_, (x) => IntValue(floatToInt32(x)));
    _addFloatUnaryOp(float, FloatValue.new);

    // String operations
    _addStringBinaryOp(add, (x, y) => StringValue(x + y)); // concat
    _addStringBinaryOp(equal, (x, y) => BoolValue(x == y));
    _addStringBinaryOp(notEquals, (x, y) => BoolValue(x != y));
    _addStringBinaryOp(has, (x, y) => BoolValue(x.contains(y)));
    _addStringBinaryOp(hasnt, (x, y) => BoolValue(!x.contains(y)));

    // List operations
    _addListBinaryOp(add, (x, y) => ListValue.fromList(x.union(y)));
    _addListBinaryOp(subtract, (x, y) => ListValue.fromList(x.without(y)));
    _addListBinaryOp(has, (x, y) => BoolValue(x.contains(y)));
    _addListBinaryOp(hasnt, (x, y) => BoolValue(!x.contains(y)));
    _addListBinaryOp(intersect, (x, y) => ListValue.fromList(x.intersect(y)));

    _addListBinaryOp(equal, (x, y) => BoolValue(x == y));
    _addListBinaryOp(greater, (x, y) => BoolValue(x.greaterThan(y)));
    _addListBinaryOp(less, (x, y) => BoolValue(x.lessThan(y)));
    _addListBinaryOp(
      greaterThanOrEquals,
      (x, y) => BoolValue(x.greaterThanOrEquals(y)),
    );
    _addListBinaryOp(
      lessThanOrEquals,
      (x, y) => BoolValue(x.lessThanOrEquals(y)),
    );
    _addListBinaryOp(notEquals, (x, y) => BoolValue(x != y));

    _addListBinaryOp(and, (x, y) => BoolValue(x.count > 0 && y.count > 0));
    _addListBinaryOp(or, (x, y) => BoolValue(x.count > 0 || y.count > 0));

    _addListUnaryOp(not, (x) => IntValue(x.count == 0 ? 1 : 0));

    // Placeholders to ensure that these special case functions can exist,
    // since these function is never actually run, and is special cased in Call
    _addListUnaryOp(invert, (x) => ListValue.fromList(x.inverse));
    _addListUnaryOp(all, (x) => ListValue.fromList(x.all));
    _addListUnaryOp(listMin, (x) => ListValue.fromList(x.minAsList()));
    _addListUnaryOp(listMax, (x) => ListValue.fromList(x.maxAsList()));
    _addListUnaryOp(count, (x) => IntValue(x.count));
    _addListUnaryOp(valueOfList, (x) => IntValue(x.maxItem.value));

    // Special case: The only operations you can do on divert target values
    _addOpToNativeFunc(
      equal,
      2,
      ValueType.divertTarget,
      (Object d1, Object d2) => BoolValue((d1 as Path) == (d2 as Path)),
    );
    _addOpToNativeFunc(
      notEquals,
      2,
      ValueType.divertTarget,
      (Object d1, Object d2) => BoolValue((d1 as Path) != (d2 as Path)),
    );
  }

  void _addOpFuncForType(ValueType valType, Function op) {
    (_operationFuncs ??= {})[valType] = op;
  }

  static void _addOpToNativeFunc(
    String name,
    int args,
    ValueType valType,
    Function op,
  ) {
    final nativeFunc = _nativeFunctions.putIfAbsent(
      name,
      () => NativeFunctionCall._prototype(name, args),
    );
    nativeFunc._addOpFuncForType(valType, op);
  }

  static void _addIntBinaryOp(
    String name,
    AbstractValue Function(int, int) op,
  ) {
    _addOpToNativeFunc(
      name,
      2,
      ValueType.int_,
      (Object x, Object y) => op(x as int, y as int),
    );
  }

  static void _addIntUnaryOp(String name, AbstractValue Function(int) op) {
    _addOpToNativeFunc(name, 1, ValueType.int_, (Object x) => op(x as int));
  }

  static void _addFloatBinaryOp(
    String name,
    AbstractValue Function(double, double) op,
  ) {
    _addOpToNativeFunc(
      name,
      2,
      ValueType.float,
      (Object x, Object y) => op(x as double, y as double),
    );
  }

  static void _addFloatUnaryOp(String name, AbstractValue Function(double) op) {
    _addOpToNativeFunc(name, 1, ValueType.float, (Object x) => op(x as double));
  }

  static void _addStringBinaryOp(
    String name,
    AbstractValue Function(String, String) op,
  ) {
    _addOpToNativeFunc(
      name,
      2,
      ValueType.string,
      (Object x, Object y) => op(x as String, y as String),
    );
  }

  static void _addListBinaryOp(
    String name,
    AbstractValue Function(InkList, InkList) op,
  ) {
    _addOpToNativeFunc(
      name,
      2,
      ValueType.list,
      (Object x, Object y) => op(x as InkList, y as InkList),
    );
  }

  static void _addListUnaryOp(String name, AbstractValue Function(InkList) op) {
    _addOpToNativeFunc(name, 1, ValueType.list, (Object x) => op(x as InkList));
  }

  @override
  String toString() => "Native '$name'";

  NativeFunctionCall? _prototype;
  bool _isPrototype = false;

  // Operations for each data type, for a single operation (e.g. "+")
  Map<ValueType, Function>? _operationFuncs;

  static final Map<String, NativeFunctionCall> _nativeFunctions = {};
}
