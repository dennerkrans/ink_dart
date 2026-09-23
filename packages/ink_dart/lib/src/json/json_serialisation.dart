// Port of ink's JsonSerialisation.cs (class `Json` in C#).
//
// JSON ENCODING SCHEME
//
// Glue:           "<>", "G<", "G>"
//
// ControlCommand: "ev", "out", "/ev", "du" "pop", "->->", "~ret", "str",
//                 "/str", "nop", "choiceCnt", "turns", "visit", "seq",
//                 "thread", "done", "end"
//
// NativeFunction: "+", "-", "/", "*", "%" "~", "==", ">", "<", ">=", "<=",
//                 "!=", "!"... etc
//
// Void:           "void"
//
// Value:          "^string value", "^^string value beginning with ^"
//                 5, 5.2
//                 {"^->": "path.target"}
//                 {"^var": "varname", "ci": 0}
//
// Container:      [...]
//                 [...,
//                     {
//                         "subContainerName": ...,
//                         "#f": 5,                    // flags
//                         "#n": "containerOwnName"    // only if not redundant
//                     }
//                 ]
//
// Divert:         {"->": "path.target", "c": true }
//                 {"->": "path.target", "var": true}
//                 {"f()": "path.func"}
//                 {"->t->": "path.tunnel"}
//                 {"x()": "externalFuncName", "exArgs": 5}
//
// Var Assign:     {"VAR=": "varName", "re": true}   // reassignment
//                 {"temp=": "varName"}
//
// Var ref:        {"VAR?": "varName"}
//                 {"CNT?": "stitch name"}
//
// ChoicePoint:    {"*": pathString,
//                  "flg": 18 }
//
// Choice:         Nothing too clever, it's only used in the save state,
//                 there's not likely to be many of them.
//
// Tag:            {"#": "the tag text"}

import '../float32.dart';
import '../runtime/bool_value.dart';
import '../runtime/choice.dart';
import '../runtime/choice_point.dart';
import '../runtime/container.dart';
import '../runtime/control_command.dart';
import '../runtime/divert.dart';
import '../runtime/divert_target_value.dart';
import '../runtime/float_value.dart';
import '../runtime/glue.dart';
import '../runtime/ink_list.dart';
import '../runtime/ink_list_item.dart';
import '../runtime/ink_object.dart';
import '../runtime/int_value.dart';
import '../runtime/list_definition.dart';
import '../runtime/list_definitions_origin.dart';
import '../runtime/list_value.dart';
import '../runtime/native_function_call.dart';
import '../runtime/path.dart';
import '../runtime/push_pop.dart';
import '../runtime/string_value.dart';
import '../runtime/tag.dart';
import '../runtime/variable_assignment.dart';
import '../runtime/variable_pointer_value.dart';
import '../runtime/variable_reference.dart';
import '../runtime/void.dart';
import '../system_exception.dart';
import 'simple_json.dart';

abstract final class JsonSerialisation {
  static List<T> jArrayToRuntimeObjList<T extends InkObject>(
    List<Object?> jArray, {
    bool skipLast = false,
  }) {
    var count = jArray.length;
    if (skipLast) count--;

    final list = <T>[];

    for (var i = 0; i < count; i++) {
      final jTok = jArray[i];
      final runtimeObj = jTokenToRuntimeObject(jTok);
      list.add(runtimeObj as T);
    }

    return list;
  }

  static void writeDictionaryRuntimeObjs(
    Writer writer,
    Map<String, InkObject> dictionary,
  ) {
    writer.writeObjectStart();
    for (final keyVal in dictionary.entries) {
      writer.writePropertyStart(keyVal.key);
      writeRuntimeObject(writer, keyVal.value);
      writer.writePropertyEnd();
    }
    writer.writeObjectEnd();
  }

  static void writeListRuntimeObjs(Writer writer, List<InkObject> list) {
    writer.writeArrayStart();
    for (final val in list) {
      writeRuntimeObject(writer, val);
    }
    writer.writeArrayEnd();
  }

  static void writeIntDictionary(Writer writer, Map<String, int> dict) {
    writer.writeObjectStart();
    for (final keyVal in dict.entries) {
      writer.writeIntProperty(keyVal.key, keyVal.value);
    }
    writer.writeObjectEnd();
  }

  static void writeRuntimeObject(Writer writer, InkObject obj) {
    if (obj is Container) {
      writeRuntimeContainer(writer, obj);
      return;
    }

    if (obj is Divert) {
      var divTypeKey = '->';
      if (obj.isExternal) {
        divTypeKey = 'x()';
      } else if (obj.pushesToStack) {
        if (obj.stackPushType == PushPopType.function) {
          divTypeKey = 'f()';
        } else if (obj.stackPushType == PushPopType.tunnel) {
          divTypeKey = '->t->';
        }
      }

      String? targetStr;
      if (obj.hasVariableTarget) {
        targetStr = obj.variableDivertName;
      } else {
        targetStr = obj.targetPathString;
      }

      writer.writeObjectStart();

      writer.writeProperty(divTypeKey, targetStr);

      if (obj.hasVariableTarget) writer.writeBoolProperty('var', true);

      if (obj.isConditional) writer.writeBoolProperty('c', true);

      if (obj.externalArgs > 0) {
        writer.writeIntProperty('exArgs', obj.externalArgs);
      }

      writer.writeObjectEnd();
      return;
    }

    if (obj is ChoicePoint) {
      writer.writeObjectStart();
      writer.writeProperty('*', obj.pathStringOnChoice);
      writer.writeIntProperty('flg', obj.flags);
      writer.writeObjectEnd();
      return;
    }

    if (obj is BoolValue) {
      writer.writeBool(obj.value);
      return;
    }

    if (obj is IntValue) {
      writer.writeInt(obj.value);
      return;
    }

    if (obj is FloatValue) {
      writer.writeFloat(obj.value);
      return;
    }

    if (obj is StringValue) {
      if (obj.isNewline) {
        writer.write('\\n', escape: false);
      } else {
        writer.writeStringStart();
        writer.writeStringInner('^');
        writer.writeStringInner(obj.value);
        writer.writeStringEnd();
      }
      return;
    }

    if (obj is ListValue) {
      _writeInkList(writer, obj);
      return;
    }

    if (obj is DivertTargetValue) {
      writer.writeObjectStart();
      writer.writeProperty('^->', obj.value.componentsString);
      writer.writeObjectEnd();
      return;
    }

    if (obj is VariablePointerValue) {
      writer.writeObjectStart();
      writer.writeProperty('^var', obj.value);
      writer.writeIntProperty('ci', obj.contextIndex);
      writer.writeObjectEnd();
      return;
    }

    if (obj is Glue) {
      writer.write('<>');
      return;
    }

    if (obj is ControlCommand) {
      writer.write(_controlCommandNames[obj.commandType]);
      return;
    }

    if (obj is NativeFunctionCall) {
      var name = obj.name;

      // Avoid collision with ^ used to indicate a string
      if (name == '^') name = 'L^';

      writer.write(name);
      return;
    }

    // Variable reference
    if (obj is VariableReference) {
      writer.writeObjectStart();

      final readCountPath = obj.pathStringForCount;
      if (readCountPath != null) {
        writer.writeProperty('CNT?', readCountPath);
      } else {
        writer.writeProperty('VAR?', obj.name);
      }

      writer.writeObjectEnd();
      return;
    }

    // Variable assignment
    if (obj is VariableAssignment) {
      writer.writeObjectStart();

      final key = obj.isGlobal ? 'VAR=' : 'temp=';
      writer.writeProperty(key, obj.variableName);

      // Reassignment?
      if (!obj.isNewDeclaration) writer.writeBoolProperty('re', true);

      writer.writeObjectEnd();

      return;
    }

    // Void
    if (obj is Void) {
      writer.write('void');
      return;
    }

    // Legacy tag
    if (obj is Tag) {
      writer.writeObjectStart();
      writer.writeProperty('#', obj.text);
      writer.writeObjectEnd();
      return;
    }

    // Used when serialising save state only
    if (obj is Choice) {
      writeChoice(writer, obj);
      return;
    }

    throw SystemException('Failed to write runtime object to JSON: $obj');
  }

  static Map<String, InkObject> jObjectToDictionaryRuntimeObjs(
    Map<String, Object?> jObject,
  ) {
    final dict = <String, InkObject>{};

    for (final keyVal in jObject.entries) {
      final obj = jTokenToRuntimeObject(keyVal.value);
      if (obj == null) {
        throw SystemException('Failed to convert token: ${keyVal.value}');
      }
      dict[keyVal.key] = obj;
    }

    return dict;
  }

  static Map<String, int> jObjectToIntDictionary(Map<String, Object?> jObject) {
    final dict = <String, int>{};
    for (final keyVal in jObject.entries) {
      dict[keyVal.key] = keyVal.value as int;
    }
    return dict;
  }

  static InkObject? jTokenToRuntimeObject(Object? token) {
    if (token is int) return IntValue(token);
    if (token is JsonFloat) return FloatValue(token.value);
    // A plain double comes from a map decoded with `jsonDecode`.
    if (token is double) return FloatValue(toFloat32(token));
    if (token is bool) return BoolValue(token);

    if (token is String) {
      var str = token;

      // String value
      final firstChar = str[0];
      if (firstChar == '^') {
        return StringValue(str.substring(1));
      } else if (firstChar == '\n' && str.length == 1) {
        return StringValue('\n');
      }

      // Glue
      if (str == '<>') return Glue();

      // Control commands (would looking up in a hash set be faster?)
      final cmd = _controlCommandsByName[str];
      if (cmd != null) return ControlCommand(cmd);

      // Native functions
      // "^" conflicts with the way to identify strings, so now
      // we know it's not a string, we can convert back to the proper
      // symbol for the operator.
      if (str == 'L^') str = '^';
      if (NativeFunctionCall.callExistsWithName(str)) {
        return NativeFunctionCall.callWithName(str);
      }

      // Pop
      if (str == '->->') {
        return ControlCommand.popTunnel();
      } else if (str == '~ret') {
        return ControlCommand.popFunction();
      }

      // Void
      if (str == 'void') return Void();
    }

    if (token is Map<String, Object?>) {
      final obj = token;
      Object? propValue;

      // Divert target value to path
      propValue = obj['^->'];
      if (propValue != null) {
        return DivertTargetValue(Path.fromString(propValue as String));
      }

      // VariablePointerValue
      propValue = obj['^var'];
      if (propValue != null) {
        final varPtr = VariablePointerValue(propValue as String);
        final ci = obj['ci'];
        if (ci != null) varPtr.contextIndex = ci as int;
        return varPtr;
      }

      // Divert
      var isDivert = false;
      var pushesToStack = false;
      var divPushType = PushPopType.function;
      var external = false;
      if ((propValue = obj['->']) != null) {
        isDivert = true;
      } else if ((propValue = obj['f()']) != null) {
        isDivert = true;
        pushesToStack = true;
        divPushType = PushPopType.function;
      } else if ((propValue = obj['->t->']) != null) {
        isDivert = true;
        pushesToStack = true;
        divPushType = PushPopType.tunnel;
      } else if ((propValue = obj['x()']) != null) {
        isDivert = true;
        external = true;
        pushesToStack = false;
        divPushType = PushPopType.function;
      }
      if (isDivert) {
        final divert = Divert()
          ..pushesToStack = pushesToStack
          ..stackPushType = divPushType
          ..isExternal = external;

        final target = propValue.toString();

        if (obj.containsKey('var')) {
          divert.variableDivertName = target;
        } else {
          divert.targetPathString = target;
        }

        divert.isConditional = obj.containsKey('c');

        if (external) {
          final exArgs = obj['exArgs'];
          if (exArgs != null) divert.externalArgs = exArgs as int;
        }

        return divert;
      }

      // Choice
      propValue = obj['*'];
      if (propValue != null) {
        final choice = ChoicePoint();
        choice.pathStringOnChoice = propValue.toString();

        final flg = obj['flg'];
        if (flg != null) choice.flags = flg as int;

        return choice;
      }

      // Variable reference
      propValue = obj['VAR?'];
      if (propValue != null) {
        return VariableReference(propValue.toString());
      }
      propValue = obj['CNT?'];
      if (propValue != null) {
        final readCountVarRef = VariableReference();
        readCountVarRef.pathStringForCount = propValue.toString();
        return readCountVarRef;
      }

      // Variable assignment
      var isVarAss = false;
      var isGlobalVar = false;
      if ((propValue = obj['VAR=']) != null) {
        isVarAss = true;
        isGlobalVar = true;
      } else if ((propValue = obj['temp=']) != null) {
        isVarAss = true;
        isGlobalVar = false;
      }
      if (isVarAss) {
        final varName = propValue.toString();
        final isNewDecl = !obj.containsKey('re');
        final varAss = VariableAssignment(varName, isNewDecl)
          ..isGlobal = isGlobalVar;
        return varAss;
      }

      // Legacy Tag with text
      propValue = obj['#'];
      if (propValue != null) return Tag(propValue as String);

      // List value
      propValue = obj['list'];
      if (propValue != null) {
        final listContent = propValue as Map<String, Object?>;
        final rawList = InkList();
        final origins = obj['origins'];
        if (origins != null) {
          rawList.setInitialOriginNames((origins as List).cast<String>());
        }
        for (final nameToVal in listContent.entries) {
          final item = InkListItem.fromFullName(nameToVal.key);
          final val = nameToVal.value as int;
          rawList.add(item, val);
        }
        return ListValue.fromList(rawList);
      }

      // Used when serialising save state only
      if (!obj.containsKey('originalChoicePath')) {
        throw SystemException(
          "The given key 'originalChoicePath' was not present in the "
          'dictionary.',
        );
      }
      if (obj['originalChoicePath'] != null) return _jObjectToChoice(obj);
    }

    // Array is always a Runtime.Container
    if (token is List<Object?>) return _jArrayToContainer(token);

    if (token == null) return null;

    throw SystemException('Failed to convert token to runtime object: $token');
  }

  static void writeRuntimeContainer(
    Writer writer,
    Container container, {
    bool withoutName = false,
  }) {
    writer.writeArrayStart();

    for (final c in container.content) {
      writeRuntimeObject(writer, c);
    }

    // Container is always an array [...]
    // But the final element is always either:
    //  - a dictionary containing the named content, as well as possibly
    //    the key "#" with the count flags
    //  - null, if neither of the above
    final namedOnlyContent = container.namedOnlyContent;
    final countFlags = container.countFlags;
    final hasNameProperty = container.name != null && !withoutName;

    final hasTerminator =
        namedOnlyContent != null || countFlags > 0 || hasNameProperty;

    if (hasTerminator) writer.writeObjectStart();

    if (namedOnlyContent != null) {
      for (final namedContent in namedOnlyContent.entries) {
        final name = namedContent.key;
        final namedContainer = namedContent.value as Container;
        writer.writePropertyStart(name);
        writeRuntimeContainer(writer, namedContainer, withoutName: true);
        writer.writePropertyEnd();
      }
    }

    if (countFlags > 0) writer.writeIntProperty('#f', countFlags);

    if (hasNameProperty) writer.writeProperty('#n', container.name);

    if (hasTerminator) {
      writer.writeObjectEnd();
    } else {
      writer.writeNull();
    }

    writer.writeArrayEnd();
  }

  static Container _jArrayToContainer(List<Object?> jArray) {
    final container = Container();
    container.content = jArrayToRuntimeObjList(jArray, skipLast: true);

    // Final object in the array is always a combination of
    //  - named content
    //  - a "#f" key with the countFlags
    // (if either exists at all, otherwise null)
    final terminatingObj = jArray[jArray.length - 1];
    if (terminatingObj is Map<String, Object?>) {
      final namedOnlyContent = <String, InkObject>{};

      for (final keyVal in terminatingObj.entries) {
        if (keyVal.key == '#f') {
          container.countFlags = keyVal.value as int;
        } else if (keyVal.key == '#n') {
          container.name = keyVal.value.toString();
        } else {
          final namedContentItem = jTokenToRuntimeObject(keyVal.value);
          if (namedContentItem is Container) {
            namedContentItem.name = keyVal.key;
          }
          if (namedContentItem != null) {
            namedOnlyContent[keyVal.key] = namedContentItem;
          }
        }
      }

      container.namedOnlyContent = namedOnlyContent;
    }

    return container;
  }

  static Choice _jObjectToChoice(Map<String, Object?> jObj) {
    final choice = Choice()
      ..text = jObj['text'].toString()
      ..index = jObj['index'] as int
      ..sourcePath = jObj['originalChoicePath'].toString()
      ..originalThreadIndex = jObj['originalThreadIndex'] as int
      ..pathStringOnChoice = jObj['targetPath'].toString();
    choice.tags = _jArrayToTags(jObj);
    return choice;
  }

  static List<String>? _jArrayToTags(Map<String, Object?> jObj) {
    final jArray = jObj['tags'];
    if (jArray == null) return null;

    return [for (final stringValue in jArray as List) stringValue.toString()];
  }

  static void writeChoice(Writer writer, Choice choice) {
    writer.writeObjectStart();
    writer.writeProperty('text', choice.text);
    writer.writeIntProperty('index', choice.index);
    writer.writeProperty('originalChoicePath', choice.sourcePath);
    writer.writeIntProperty('originalThreadIndex', choice.originalThreadIndex);
    writer.writeProperty('targetPath', choice.pathStringOnChoice);
    _writeChoiceTags(writer, choice);
    writer.writeObjectEnd();
  }

  static void _writeChoiceTags(Writer writer, Choice choice) {
    final tags = choice.tags;
    if (tags == null || tags.isEmpty) return;
    writer.writePropertyStart('tags');
    writer.writeArrayStart();
    for (final tag in tags) {
      writer.write(tag);
    }
    writer.writeArrayEnd();
    writer.writePropertyEnd();
  }

  static void _writeInkList(Writer writer, ListValue listVal) {
    final rawList = listVal.value;

    writer.writeObjectStart();

    writer.writePropertyStart('list');

    writer.writeObjectStart();

    for (final itemAndValue in rawList.entries) {
      final item = itemAndValue.key;
      final itemVal = itemAndValue.value;

      writer.writePropertyNameStart();
      writer.writePropertyNameInner(item.originName ?? '?');
      writer.writePropertyNameInner('.');
      writer.writePropertyNameInner(item.itemName ?? '');
      writer.writePropertyNameEnd();

      writer.writeInt(itemVal);

      writer.writePropertyEnd();
    }

    writer.writeObjectEnd();

    writer.writePropertyEnd();

    final originNames = rawList.originNames;
    if (rawList.count == 0 && originNames != null && originNames.isNotEmpty) {
      writer.writePropertyStart('origins');
      writer.writeArrayStart();
      for (final name in originNames) {
        writer.write(name);
      }
      writer.writeArrayEnd();
      writer.writePropertyEnd();
    }

    writer.writeObjectEnd();
  }

  static ListDefinitionsOrigin jTokenToListDefinitions(Object? obj) {
    final defsObj = obj as Map<String, Object?>;

    final allDefs = <ListDefinition>[];

    for (final kv in defsObj.entries) {
      final name = kv.key;
      final listDefJson = kv.value as Map<String, Object?>;

      // Cast (string, object) to (string, int) for items
      final items = <String, int>{};
      for (final nameValue in listDefJson.entries) {
        items[nameValue.key] = nameValue.value as int;
      }

      allDefs.add(ListDefinition(name, items));
    }

    return ListDefinitionsOrigin(allDefs);
  }

  static const Map<CommandType, String> _controlCommandNames = {
    CommandType.evalStart: 'ev',
    CommandType.evalOutput: 'out',
    CommandType.evalEnd: '/ev',
    CommandType.duplicate: 'du',
    CommandType.popEvaluatedValue: 'pop',
    CommandType.popFunction: '~ret',
    CommandType.popTunnel: '->->',
    CommandType.beginString: 'str',
    CommandType.endString: '/str',
    CommandType.noOp: 'nop',
    CommandType.choiceCount: 'choiceCnt',
    CommandType.turns: 'turn',
    CommandType.turnsSince: 'turns',
    CommandType.readCount: 'readc',
    CommandType.random: 'rnd',
    CommandType.seedRandom: 'srnd',
    CommandType.visitIndex: 'visit',
    CommandType.sequenceShuffleIndex: 'seq',
    CommandType.startThread: 'thread',
    CommandType.done: 'done',
    CommandType.end: 'end',
    CommandType.listFromInt: 'listInt',
    CommandType.listRange: 'range',
    CommandType.listRandom: 'lrnd',
    CommandType.beginTag: '#',
    CommandType.endTag: '/#',
  };

  static final Map<String, CommandType> _controlCommandsByName = {
    for (final e in _controlCommandNames.entries) e.value: e.key,
  };
}
