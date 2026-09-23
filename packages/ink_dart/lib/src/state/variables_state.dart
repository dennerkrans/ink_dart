// Port of ink's VariablesState.cs.

import '../json/json_serialisation.dart';
import '../json/simple_json.dart';
import '../runtime/bool_value.dart';
import '../runtime/float_value.dart';
import '../runtime/ink_object.dart';
import '../runtime/int_value.dart';
import '../runtime/list_definitions_origin.dart';
import '../runtime/list_value.dart';
import '../runtime/value.dart';
import '../runtime/variable_assignment.dart';
import '../runtime/variable_pointer_value.dart';
import '../story_exception.dart';
import '../system_exception.dart';
import 'call_stack.dart';
import 'state_patch.dart';

/// Called when a global variable is assigned, with its new runtime value.
typedef VariableChanged =
    void Function(String variableName, InkObject newValue);

/// Encompasses all the global variables in an ink Story, and
/// allows binding of a VariableChanged event so that that game
/// code can be notified whenever the global variables change.
class VariablesState extends Iterable<String> {
  /// Creates the variables of a story, reading temporaries from [callStack].
  VariablesState(this.callStack, this._listDefsOrigin);

  /// Called on every global assignment; `Story` uses it to notify observers.
  VariableChanged? variableChangedEvent;

  /// Changes made during lookahead, applied later; null when not looking
  /// ahead.
  StatePatch? patch;

  /// Starts batching changed variable names until
  /// [completeVariableObservation].
  void startVariableObservation() {
    _batchObservingVariableChanges = true;
    _changedVariablesForBatchObs = {};
  }

  /// Stops batching and returns each changed variable with its current
  /// value.
  Map<String, InkObject> completeVariableObservation() {
    _batchObservingVariableChanges = false;

    // Finished observing variables in a batch - now send
    // notifications for changed variables all in one go.
    final changedVars = <String, InkObject>{};
    final batch = _changedVariablesForBatchObs;
    if (batch != null) {
      for (final variableName in batch) {
        final currentValue = _globalVariables[variableName];
        if (currentValue == null) {
          throw SystemException(
            "The given key '$variableName' was not present in the dictionary.",
          );
        }
        changedVars[variableName] = currentValue;
      }
    }

    // Patch may still be active - e.g. if we were in the middle of a
    // background save
    final p = patch;
    if (p != null) {
      for (final variableName in p.changedVariables) {
        final patchedVal = p.tryGetGlobal(variableName);
        if (patchedVal != null) changedVars[variableName] = patchedVal;
      }
    }

    _changedVariablesForBatchObs = null;
    return changedVars;
  }

  /// Calls [variableChangedEvent] for each of [changedVars].
  void notifyObservers(Map<String, InkObject> changedVars) {
    final event = variableChangedEvent;
    if (event == null) return;
    for (final varToVal in changedVars.entries) {
      event(varToVal.key, varToVal.value);
    }
  }

  /// Allow StoryState to change the current callstack, e.g. for
  /// temporary function evaluation.
  CallStack callStack;

  /// Get or set the value of a named global ink variable.
  /// The types available are the standard ink types. Certain
  /// types will be implicitly casted when setting.
  /// For example, doubles to floats, longs to ints, and bools
  /// to ints.
  Object? operator [](String variableName) {
    final p = patch;
    InkObject? varContents = p?.tryGetGlobal(variableName);
    if (varContents != null) return (varContents as AbstractValue).valueObject;

    // Search main dictionary first.
    // If it's not found, it might be because the story content has changed,
    // and the original default value hasn't be instantiated.
    // Should really warn somehow, but it's difficult to see how...!
    varContents =
        _globalVariables[variableName] ??
        _defaultGlobalVariables?[variableName];
    if (varContents != null) {
      return (varContents as AbstractValue).valueObject;
    } else {
      return null;
    }
  }

  /// Sets a global variable from the game. [value] is an `int`, `double`
  /// (stored as a 32-bit float), `String`, `bool` or [InkList]; the variable
  /// must be declared in the story, or this throws.
  void operator []=(String variableName, Object? value) {
    if (!(_defaultGlobalVariables?.containsKey(variableName) ?? false)) {
      throw StoryException(
        'Cannot assign to a variable ($variableName) that hasn\'t been '
        'declared in the story',
      );
    }

    final val = AbstractValue.create(value);
    if (val == null) {
      if (value == null) {
        throw SystemException('Cannot pass null to VariableState');
      } else {
        throw SystemException('Invalid value passed to VariableState: $value');
      }
    }

    setGlobal(variableName, val);
  }

  /// Enumerator to allow iteration over all global variables by name.
  @override
  Iterator<String> get iterator => _globalVariables.keys.iterator;

  /// Applies [patch] to the globals and clears it.
  void applyPatch() {
    final p = patch;
    if (p == null) return;

    for (final namedVar in p.globals.entries) {
      _globalVariables[namedVar.key] = namedVar.value;
    }

    final batch = _changedVariablesForBatchObs;
    if (batch != null) {
      for (final name in p.changedVariables) {
        batch.add(name);
      }
    }

    patch = null;
  }

  /// Loads globals from saved state, keeping defaults for any not saved.
  void setJsonToken(Map<String, Object?> jToken) {
    _globalVariables.clear();

    for (final varVal
        in (_defaultGlobalVariables ?? const <String, InkObject>{}).entries) {
      final loadedToken = jToken[varVal.key];
      if (jToken.containsKey(varVal.key)) {
        final obj = JsonSerialisation.jTokenToRuntimeObject(loadedToken);
        if (obj != null) _globalVariables[varVal.key] = obj;
      } else {
        _globalVariables[varVal.key] = varVal.value;
      }
    }
  }

  /// When saving out JSON state, we can skip saving global values that
  /// remain equal to the initial values that were declared in ink.
  /// This makes the save file (potentially) much smaller assuming that
  /// at least a portion of the globals haven't changed. However, it
  /// can also take marginally longer to save in the case that the
  /// majority HAVE changed, since it has to compare all globals.
  /// It may also be useful to turn this off for testing worst case
  /// save timing.
  static bool dontSaveDefaultValues = true;

  /// Writes the globals that differ from their defaults to saved state.
  void writeJson(Writer writer) {
    writer.writeObjectStart();
    for (final keyVal in _globalVariables.entries) {
      final name = keyVal.key;
      final val = keyVal.value;

      if (dontSaveDefaultValues) {
        // Don't write out values that are the same as the default global
        // values
        final defaultVal = _defaultGlobalVariables?[name];
        if (defaultVal != null && runtimeObjectsEqual(val, defaultVal)) {
          continue;
        }
      }

      writer.writePropertyStart(name);
      JsonSerialisation.writeRuntimeObject(writer, val);
      writer.writePropertyEnd();
    }
    writer.writeObjectEnd();
  }

  /// Whether two values are equal for the purpose of skipping unchanged
  /// globals when saving.
  bool runtimeObjectsEqual(InkObject obj1, InkObject obj2) {
    if (obj1.runtimeType != obj2.runtimeType) return false;

    // Perform equality on int/float/bool manually to avoid boxing
    if (obj1 is BoolValue) return obj1.value == (obj2 as BoolValue).value;

    if (obj1 is IntValue) return obj1.value == (obj2 as IntValue).value;

    if (obj1 is FloatValue) return obj1.value == (obj2 as FloatValue).value;

    // Other Value type (using proper Equals: list, string, divert path)
    if (obj1 is AbstractValue && obj2 is AbstractValue) {
      return obj1.valueObject == obj2.valueObject;
    }

    throw SystemException(
      'FastRoughDefinitelyEquals: Unsupported runtime object type: '
      '${obj1.runtimeType}',
    );
  }

  /// The value of the variable [name], following variable pointers; null if
  /// it doesn't exist. [contextIndex] 0 is global, 1 and up a call stack
  /// element, -1 the current one.
  InkObject? getVariableWithName(String? name, [int contextIndex = -1]) {
    var varValue = _getRawVariableWithName(name, contextIndex);

    // Get value from pointer?
    if (varValue is VariablePointerValue) {
      varValue = valueAtVariablePointer(varValue);
    }

    return varValue;
  }

  /// The declared initial value of the global [name], or null.
  InkObject? tryGetDefaultVariableValue(String name) =>
      _defaultGlobalVariables?[name];

  /// Whether [name] is a global variable of the story.
  bool globalVariableExistsWithName(String? name) =>
      _globalVariables.containsKey(name) ||
      _defaultGlobalVariables != null &&
          (_defaultGlobalVariables?.containsKey(name) ?? false);

  InkObject? _getRawVariableWithName(String? name, int contextIndex) {
    InkObject? varValue;

    // 0 context = global
    if (contextIndex == 0 || contextIndex == -1) {
      final p = patch;
      if (p != null) {
        varValue = p.tryGetGlobal(name);
        if (varValue != null) return varValue;
      }

      varValue = _globalVariables[name];
      if (varValue != null) return varValue;

      // Getting variables can actually happen during globals set up since
      // you can do
      //  VAR x = A_LIST_ITEM
      // So _defaultGlobalVariables may be null.
      // We need to do this check though in case a new global is added, so we
      // need to revert to the default globals dictionary since an initial
      // value hasn't yet been set.
      varValue = _defaultGlobalVariables?[name];
      if (varValue != null) return varValue;

      final listItemValue = _listDefsOrigin?.findSingleItemListWithName(name);
      if (listItemValue != null) return listItemValue;
    }

    // Temporary
    varValue = callStack.getTemporaryVariableWithName(name ?? '', contextIndex);

    return varValue;
  }

  /// The value of the variable [pointer] refers to.
  InkObject? valueAtVariablePointer(VariablePointerValue pointer) =>
      getVariableWithName(pointer.variableName, pointer.contextIndex);

  /// Performs the assignment [varAss] of [value], to a global or a temporary.
  void assign(VariableAssignment varAss, InkObject value) {
    var name = varAss.variableName ?? '';
    var contextIndex = -1;

    // Are we assigning to a global variable?
    var setGlobal = false;
    if (varAss.isNewDeclaration) {
      setGlobal = varAss.isGlobal;
    } else {
      setGlobal = globalVariableExistsWithName(name);
    }

    // Constructing new variable pointer reference
    if (varAss.isNewDeclaration) {
      if (value is VariablePointerValue) {
        final fullyResolvedVariablePointer = _resolveVariablePointer(value);
        value = fullyResolvedVariablePointer;
      }
    }
    // Assign to existing variable pointer?
    // Then assign to the variable that the pointer is pointing to by name.
    else {
      // De-reference variable reference to point to
      VariablePointerValue? existingPointer;
      do {
        final raw = _getRawVariableWithName(name, contextIndex);
        existingPointer = raw is VariablePointerValue ? raw : null;
        if (existingPointer != null) {
          name = existingPointer.variableName;
          contextIndex = existingPointer.contextIndex;
          setGlobal = contextIndex == 0;
        }
      } while (existingPointer != null);
    }

    if (setGlobal) {
      this.setGlobal(name, value);
    } else {
      callStack.setTemporaryVariable(
        name,
        value,
        varAss.isNewDeclaration,
        contextIndex,
      );
    }
  }

  /// Records the current globals as their defaults.
  void snapshotDefaultGlobals() {
    _defaultGlobalVariables = {..._globalVariables};
  }

  /// Sets the global [variableName] to [value] and notifies observers.
  void setGlobal(String variableName, InkObject value) {
    InkObject? oldValue;
    final p = patch;
    if (p != null) oldValue = p.tryGetGlobal(variableName);
    if (p == null || oldValue == null) {
      oldValue = _globalVariables[variableName];
    }

    ListValue.retainListOriginsForAssignment(oldValue, value);

    if (p != null) {
      p.setGlobal(variableName, value);
    } else {
      _globalVariables[variableName] = value;
    }

    // Values compare by identity, as Runtime.Object does in the reference,
    // so any assignment counts as a change.
    if (variableChangedEvent != null && !identical(value, oldValue)) {
      if (_batchObservingVariableChanges) {
        if (p != null) {
          p.addChangedVariable(variableName);
        } else {
          _changedVariablesForBatchObs?.add(variableName);
        }
      } else {
        variableChangedEvent?.call(variableName, value);
      }
    }
  }

  /// Given a variable pointer with just the name of the target known, resolve
  /// to a variable pointer that more specifically points to the exact
  /// instance: whether it's global, or the exact position of a temporary on
  /// the callstack.
  VariablePointerValue _resolveVariablePointer(
    VariablePointerValue varPointer,
  ) {
    var contextIndex = varPointer.contextIndex;

    if (contextIndex == -1) {
      contextIndex = _getContextIndexOfVariableNamed(varPointer.variableName);
    }

    final valueOfVariablePointedTo = _getRawVariableWithName(
      varPointer.variableName,
      contextIndex,
    );

    // Extra layer of indirection:
    // When accessing a pointer to a pointer (e.g. when calling nested or
    // recursive functions that take a variable references, ensure we don't
    // create a chain of indirection by just returning the final target.
    if (valueOfVariablePointedTo is VariablePointerValue) {
      return valueOfVariablePointedTo;
    }
    // Make copy of the variable pointer so we're not using the value direct
    // from the runtime. Temporary must be local to the current scope.
    else {
      return VariablePointerValue(varPointer.variableName, contextIndex);
    }
  }

  // 0  if named variable is global
  // 1+ if named variable is a temporary in a particular call stack element
  int _getContextIndexOfVariableNamed(String varName) {
    if (globalVariableExistsWithName(varName)) return 0;

    return callStack.currentElementIndex;
  }

  final Map<String, InkObject> _globalVariables = {};

  Map<String, InkObject>? _defaultGlobalVariables;

  Set<String>? _changedVariablesForBatchObs;
  final ListDefinitionsOrigin? _listDefsOrigin;

  bool _batchObservingVariableChanges = false;
}
