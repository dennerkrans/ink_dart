// Port of ink's StoryState.cs (inkjs StoryState.ts).

import '../json/json_serialisation.dart';
import '../json/simple_json.dart';
import '../prng.dart';
import '../runtime/choice.dart';
import '../runtime/container.dart';
import '../runtime/control_command.dart';
import '../runtime/divert_target_value.dart';
import '../runtime/glue.dart';
import '../runtime/ink_list.dart';
import '../runtime/ink_object.dart';
import '../runtime/list_value.dart';
import '../runtime/path.dart';
import '../runtime/pointer.dart';
import '../runtime/push_pop.dart';
import '../runtime/string_value.dart';
import '../runtime/tag.dart';
import '../runtime/value.dart';
import '../runtime/void.dart';
import '../story.dart';
import '../system_exception.dart';
import 'call_stack.dart';
import 'flow.dart';
import 'state_patch.dart';
import 'variables_state.dart';

/// All story state information is included in the StoryState class,
/// including global variables, read counts, the pointer to the current
/// point in the story, the call stack (for tunnels, functions, etc),
/// and a few other smaller bits and pieces. You can save the current
/// state using the json serialisation functions ToJson and LoadJson.
class StoryState {
  /// The current version of the state save file JSON-based format.
  //
  // Backward compatible changes since v8:
  // v10: dynamic tags
  // v9:  multi-flows
  static const kInkSaveStateVersion = 10;

  /// The oldest save format version [loadJson] accepts.
  static const kMinCompatibleLoadVersion = 8;

  /// Callback for when a state is loaded
  void Function()? onDidLoadState;

  /// Exports the current state to json format, in order to save the game.
  String toJson() {
    final writer = Writer();
    _writeJson(writer);
    return writer.toString();
  }

  /// Loads a previously saved state in JSON format.
  void loadJson(String json) {
    final jObject = SimpleJson.textToDictionary(json);
    _loadJsonObj(jObject);
    onDidLoadState?.call();
  }

  /// Gets the visit/read count of a particular Container at the given path.
  /// For a knot or stitch, that path string will be in the form:
  ///
  ///     knot
  ///     knot.stitch
  int visitCountAtPathString(String pathString) {
    final p = _patch;
    if (p != null) {
      final container = story
          .contentAtPath(Path.fromString(pathString))
          .container;
      if (container == null) {
        throw SystemException('Content at path not found: $pathString');
      }

      final visitCountOut = p.tryGetVisitCount(container);
      if (visitCountOut != null) return visitCountOut;
    }

    return _visitCounts[pathString] ?? 0;
  }

  /// How many times [container] has been visited. Reports an error when the
  /// container doesn't count visits.
  int visitCountForContainer(Container? container) {
    if (container == null || !container.visitsShouldBeCounted) {
      story.error(
        'Read count for target (${container?.name} - on '
        '${container?.debugMetadata ?? ''}) unknown.',
      );
    }

    final patched = _patch?.tryGetVisitCount(container);
    if (patched != null) return patched;

    final containerPathStr = container.path.toString();
    return _visitCounts[containerPathStr] ?? 0;
  }

  /// Adds one to [container]'s visit count.
  void incrementVisitCountForContainer(Container container) {
    final p = _patch;
    if (p != null) {
      var currCount = visitCountForContainer(container);
      currCount++;
      p.setVisitCount(container, currCount);
      return;
    }

    final containerPathStr = container.path.toString();
    var count = _visitCounts[containerPathStr] ?? 0;
    count++;
    _visitCounts[containerPathStr] = count;
  }

  /// Records that [container] was visited on the current turn.
  void recordTurnIndexVisitToContainer(Container container) {
    final p = _patch;
    if (p != null) {
      p.setTurnIndex(container, currentTurnIndex);
      return;
    }

    final containerPathStr = container.path.toString();
    _turnIndices[containerPathStr] = currentTurnIndex;
  }

  /// Turns since [container] was last visited (`TURNS_SINCE`), or -1 if it
  /// never was.
  int turnsSinceForContainer(Container container) {
    if (!container.turnIndexShouldBeCounted) {
      story.error(
        'TURNS_SINCE() for target (${container.name} - on '
        '${container.debugMetadata ?? ''}) unknown.',
      );
    }

    final patched = _patch?.tryGetTurnIndex(container);
    if (patched != null) return currentTurnIndex - patched;

    final containerPathStr = container.path.toString();
    final index = _turnIndices[containerPathStr];
    if (index != null) {
      return currentTurnIndex - index;
    } else {
      return -1;
    }
  }

  /// The number of elements on the current thread's call stack.
  int get callstackDepth => callStack.depth;

  // REMEMBER! REMEMBER! REMEMBER!
  // When adding state, update the Copy method, and serialisation.
  // REMEMBER! REMEMBER! REMEMBER!

  /// The content generated so far for the current line, before text and tags
  /// are separated.
  List<InkObject> get outputStream => _currentFlow.outputStream;

  /// The choices available now, including invisible defaults; empty while the
  /// story can still continue.
  List<Choice> get currentChoices {
    // If we can continue generating text content rather than choices,
    // then we reflect the choice list as being empty, since choices
    // should always come at the end.
    if (canContinue) return [];
    return _currentFlow.currentChoices;
  }

  /// The choices generated so far, whether or not the story can continue.
  List<Choice> get generatedChoices => _currentFlow.currentChoices;

  // TODO: Consider removing currentErrors / currentWarnings altogether
  // and relying on client error handler code immediately handling
  // StoryExceptions etc
  // Or is there a specific reason we need to collect potentially multiple
  // errors before throwing/exiting?
  /// Errors from the last continue that haven't been reported yet, or null.
  List<String>? currentErrors;

  /// Warnings from the last continue that haven't been reported yet, or null.
  List<String>? currentWarnings;

  /// The story's global variables.
  late VariablesState variablesState;

  /// The current flow's call stack of threads, tunnels and functions.
  CallStack get callStack => _currentFlow.callStack;

  /// The stack of values used while evaluating expressions.
  List<InkObject> evaluationStack = [];

  /// Where the next step diverts to, or the null pointer for none.
  Pointer divertedPointer = Pointer.nullPointer;

  /// The number of choices made so far, minus one; -1 before the first.
  int currentTurnIndex = -1;

  /// The seed for `RANDOM` and shuffles. Set it before continuing to get a
  /// repeatable story.
  int storySeed = 0;

  /// The last value drawn for `RANDOM` or `LIST_RANDOM`; combined with
  /// [storySeed] to seed the next draw.
  int previousRandom = 0;

  /// Whether the flow ended through `-> DONE` or `-> END` rather than by
  /// running out of content.
  bool didSafeExit = false;

  /// The story this state belongs to.
  Story story;

  /// String representation of the location where the story currently is.
  String? get currentPathString {
    final pointer = currentPointer;
    if (pointer.isNull) {
      return null;
    } else {
      return pointer.path.toString();
    }
  }

  /// The path of the previously evaluated content, or null.
  String? get previousPathString {
    final pointer = previousPointer;
    if (pointer.isNull) {
      return null;
    } else {
      return pointer.path.toString();
    }
  }

  /// The position of the next content to evaluate.
  Pointer get currentPointer => callStack.currentElement.currentPointer;

  /// Moves the position of the next content to evaluate.
  set currentPointer(Pointer value) =>
      callStack.currentElement.currentPointer = value;

  /// The position of the previously evaluated content.
  Pointer get previousPointer => callStack.currentThread.previousPointer;

  /// Sets the position of the previously evaluated content.
  set previousPointer(Pointer value) =>
      callStack.currentThread.previousPointer = value;

  /// Whether there is more content to evaluate and no error has stopped it.
  bool get canContinue => !currentPointer.isNull && !hasError;

  /// Whether [currentErrors] holds any errors.
  bool get hasError {
    final e = currentErrors;
    return e != null && e.isNotEmpty;
  }

  /// Whether [currentWarnings] holds any warnings.
  bool get hasWarning {
    final w = currentWarnings;
    return w != null && w.isNotEmpty;
  }

  /// The text of the output stream, without tags, with whitespace cleaned as
  /// ink does.
  String get currentText {
    if (_outputStreamTextDirty) {
      final sb = StringBuffer();

      var inTag = false;
      for (final outputObj in outputStream) {
        if (!inTag && outputObj is StringValue) {
          sb.write(outputObj.value);
        } else if (outputObj is ControlCommand) {
          if (outputObj.commandType == CommandType.beginTag) {
            inTag = true;
          } else if (outputObj.commandType == CommandType.endTag) {
            inTag = false;
          }
        }
      }

      _currentText = cleanOutputWhitespace(sb.toString());

      _outputStreamTextDirty = false;
    }

    return _currentText;
  }

  String _currentText = '';

  /// Cleans inline whitespace in the following way:
  ///  - Removes all whitespace from the start and end of line (including
  ///    just before a \n)
  ///  - Turns all consecutive space and tab runs into single spaces (HTML
  ///    style)
  String cleanOutputWhitespace(String str) {
    final sb = StringBuffer();

    var currentWhitespaceStart = -1;
    var startOfLine = 0;

    for (var i = 0; i < str.length; i++) {
      final c = str[i];

      final isInlineWhitespace = c == ' ' || c == '\t';

      if (isInlineWhitespace && currentWhitespaceStart == -1) {
        currentWhitespaceStart = i;
      }

      if (!isInlineWhitespace) {
        if (c != '\n' &&
            currentWhitespaceStart > 0 &&
            currentWhitespaceStart != startOfLine) {
          sb.write(' ');
        }
        currentWhitespaceStart = -1;
      }

      if (c == '\n') startOfLine = i + 1;

      if (!isInlineWhitespace) sb.write(c);
    }

    return sb.toString();
  }

  /// The tags in the output stream, in order.
  List<String> get currentTags {
    if (_outputStreamTagsDirty) {
      final tags = <String>[];
      _currentTags = tags;

      var inTag = false;
      final sb = StringBuffer();

      for (final outputObj in outputStream) {
        if (outputObj is ControlCommand) {
          if (outputObj.commandType == CommandType.beginTag) {
            if (inTag && sb.isNotEmpty) {
              tags.add(cleanOutputWhitespace(sb.toString()));
              sb.clear();
            }
            inTag = true;
          } else if (outputObj.commandType == CommandType.endTag) {
            if (sb.isNotEmpty) {
              tags.add(cleanOutputWhitespace(sb.toString()));
              sb.clear();
            }
            inTag = false;
          }
        } else if (inTag) {
          if (outputObj is StringValue) sb.write(outputObj.value);
        } else {
          if (outputObj is Tag && outputObj.text.isNotEmpty) {
            tags.add(outputObj.text); // tag.text has whitespae already cleaned
          }
        }
      }

      if (sb.isNotEmpty) {
        tags.add(cleanOutputWhitespace(sb.toString()));
        sb.clear();
      }

      _outputStreamTagsDirty = false;
    }

    return _currentTags;
  }

  List<String> _currentTags = [];

  /// The name of the current flow; `DEFAULT_FLOW` unless using multi-flow.
  String get currentFlowName => _currentFlow.name;

  /// Whether the default flow is current.
  bool get currentFlowIsDefaultFlow => _currentFlow.name == kDefaultFlowName;

  /// The names of the flows that exist, not counting the default flow.
  List<String> get aliveFlowNames {
    if (_aliveFlowNamesDirty) {
      final names = <String>[];
      final named = _namedFlows;
      if (named != null) {
        for (final flowName in named.keys) {
          if (flowName != kDefaultFlowName) names.add(flowName);
        }
      }
      _aliveFlowNames = names;
      _aliveFlowNamesDirty = false;
    }
    return _aliveFlowNames;
  }

  List<String> _aliveFlowNames = [];

  /// Whether the current call stack element is evaluating an expression.
  bool get inExpressionEvaluation =>
      callStack.currentElement.inExpressionEvaluation;

  /// Sets whether the current call stack element is evaluating an expression.
  set inExpressionEvaluation(bool value) =>
      callStack.currentElement.inExpressionEvaluation = value;

  /// Creates the start state of [story], with a clock-based [storySeed].
  StoryState(this.story) : _currentFlow = Flow(kDefaultFlowName, story) {
    _outputStreamDirty();
    _aliveFlowNamesDirty = true;

    evaluationStack = [];

    variablesState = VariablesState(callStack, story.listDefinitions);

    _visitCounts = {};
    _turnIndices = {};

    currentTurnIndex = -1;

    // Seed the shuffle random numbers
    final timeSeed = DateTime.now().toUtc().millisecond;
    storySeed = PRNG(timeSeed).next() % 100;
    previousRandom = 0;

    goToStart();
  }

  /// Points the current flow at the start of the story.
  void goToStart() {
    callStack.currentElement.currentPointer = Pointer.startOf(
      story.mainContentContainer,
    );
  }

  /// Makes [flowName] the current flow, creating it if needed; use
  /// `Story.switchFlow`. `SwitchFlow_Internal` in C#.
  void switchFlowInternal(String? flowName) {
    if (flowName == null) {
      throw SystemException('Must pass a non-null string to Story.SwitchFlow');
    }

    final named = _namedFlows ??= {kDefaultFlowName: _currentFlow};

    if (flowName == _currentFlow.name) return;

    var flow = named[flowName];
    if (flow == null) {
      flow = Flow(flowName, story);
      named[flowName] = flow;
      _aliveFlowNamesDirty = true;
    }

    _currentFlow = flow;
    variablesState.callStack = _currentFlow.callStack;

    // Cause text to be regenerated from output stream if necessary
    _outputStreamDirty();
  }

  /// Makes the default flow current; use `Story.switchToDefaultFlow`.
  void switchToDefaultFlowInternal() {
    if (_namedFlows == null) return;
    switchFlowInternal(kDefaultFlowName);
  }

  /// Removes the flow [flowName]; use `Story.removeFlow`.
  void removeFlowInternal(String? flowName) {
    if (flowName == null) {
      throw SystemException('Must pass a non-null string to Story.DestroyFlow');
    }
    if (flowName == kDefaultFlowName) {
      throw SystemException('Cannot destroy default flow');
    }

    // If we're currently in the flow that's being removed, switch back to
    // default
    if (_currentFlow.name == flowName) switchToDefaultFlowInternal();

    _namedFlows?.remove(flowName);
    _aliveFlowNamesDirty = true;
  }

  /// Warning: Any Runtime.Object content referenced within the StoryState
  /// will be re-referenced rather than cloned. This is generally okay though
  /// since Runtime.Objects are treated as immutable after they've been set
  /// up. (e.g. we don't edit a Runtime.StringValue after it's been created an
  /// added.) I wonder if there's a sensible way to enforce that..??
  StoryState copyAndStartPatching({required bool forBackgroundSave}) {
    final copy = StoryState(story);

    copy._patch = StatePatch(_patch);

    // Hijack the new default flow to become a copy of our current one
    // If the patch is applied, then this new flow will replace the old one
    // in _namedFlows
    copy._currentFlow.name = _currentFlow.name;
    copy._currentFlow.callStack = CallStack.copyOf(_currentFlow.callStack);
    copy._currentFlow.outputStream.addAll(_currentFlow.outputStream);
    copy._outputStreamDirty();

    // When background saving we need to make copies of choices since they
    // each have a snapshot of the thread at the time of generation since the
    // game could progress significantly and threads modified during the save
    // process. However, when doing internal saving and restoring of
    // snapshots this isn't an issue, and we can simply ref-copy the choices
    // with their existing threads.
    if (forBackgroundSave) {
      for (final choice in _currentFlow.currentChoices) {
        copy._currentFlow.currentChoices.add(choice.clone());
      }
    } else {
      copy._currentFlow.currentChoices.addAll(_currentFlow.currentChoices);
    }

    // The copy of the state has its own copy of the named flows dictionary,
    // except with the current flow replaced with the copy above
    // (Assuming we're in multi-flow mode at all. If we're not then
    // the above copy is simply the default flow copy and we're done)
    final named = _namedFlows;
    if (named != null) {
      final copyNamed = <String, Flow>{...named};
      copyNamed[_currentFlow.name] = copy._currentFlow;
      copy._namedFlows = copyNamed;
      copy._aliveFlowNamesDirty = true;
    }

    if (hasError) copy.currentErrors = [...?currentErrors];
    if (hasWarning) copy.currentWarnings = [...?currentWarnings];

    // ref copy - exactly the same variables state!
    // we're expecting not to read it only while in patch mode
    // (though the callstack will be modified)
    copy.variablesState = variablesState;
    copy.variablesState.callStack = copy.callStack;
    copy.variablesState.patch = copy._patch;

    copy.evaluationStack.addAll(evaluationStack);

    if (!divertedPointer.isNull) copy.divertedPointer = divertedPointer;

    copy.previousPointer = previousPointer;

    // visit counts and turn indicies will be read only, not modified
    // while in patch mode
    copy._visitCounts = _visitCounts;
    copy._turnIndices = _turnIndices;

    copy.currentTurnIndex = currentTurnIndex;
    copy.storySeed = storySeed;
    copy.previousRandom = previousRandom;

    copy.didSafeExit = didSafeExit;

    return copy;
  }

  /// Gives the variables state back its own call stack and patch after a
  /// lookahead copy borrowed it.
  void restoreAfterPatch() {
    // VariablesState was being borrowed by the patched
    // state, so restore it with our own callstack.
    // _patch will be null normally, but if you're in the
    // middle of a save, it may contain a _patch for save purpsoes.
    variablesState.callStack = callStack;
    variablesState.patch = _patch; // usually null
  }

  /// Applies changes made during lookahead to the variables and counts.
  void applyAnyPatch() {
    final p = _patch;
    if (p == null) return;

    variablesState.applyPatch();

    for (final pathToCount in p.visitCounts.entries) {
      _applyCountChanges(pathToCount.key, pathToCount.value, isVisit: true);
    }

    for (final pathToIndex in p.turnIndices.entries) {
      _applyCountChanges(pathToIndex.key, pathToIndex.value, isVisit: false);
    }

    _patch = null;
  }

  void _applyCountChanges(
    Container container,
    int newCount, {
    required bool isVisit,
  }) {
    final counts = isVisit ? _visitCounts : _turnIndices;
    counts[container.path.toString()] = newCount;
  }

  void _writeJson(Writer writer) {
    writer.writeObjectStart();

    // Flows
    writer.writePropertyStart('flows');
    writer.writeObjectStart();

    final named = _namedFlows;
    // Multi-flow
    if (named != null) {
      for (final namedFlow in named.entries) {
        writer.writePropertyWith(namedFlow.key, namedFlow.value.writeJson);
      }
    }
    // Single flow
    else {
      writer.writePropertyWith(_currentFlow.name, _currentFlow.writeJson);
    }

    writer.writeObjectEnd();
    writer.writePropertyEnd(); // end of flows

    writer.writeProperty('currentFlowName', _currentFlow.name);

    writer.writePropertyWith('variablesState', variablesState.writeJson);

    writer.writePropertyWith(
      'evalStack',
      (w) => JsonSerialisation.writeListRuntimeObjs(w, evaluationStack),
    );

    if (!divertedPointer.isNull) {
      writer.writeProperty(
        'currentDivertTarget',
        divertedPointer.path?.componentsString,
      );
    }

    writer.writePropertyWith(
      'visitCounts',
      (w) => JsonSerialisation.writeIntDictionary(w, _visitCounts),
    );
    writer.writePropertyWith(
      'turnIndices',
      (w) => JsonSerialisation.writeIntDictionary(w, _turnIndices),
    );

    writer.writeIntProperty('turnIdx', currentTurnIndex);
    writer.writeIntProperty('storySeed', storySeed);
    writer.writeIntProperty('previousRandom', previousRandom);

    writer.writeIntProperty('inkSaveVersion', kInkSaveStateVersion);

    // Not using this right now, but could do in future.
    writer.writeIntProperty('inkFormatVersion', Story.inkVersionCurrent);

    writer.writeObjectEnd();
  }

  void _loadJsonObj(Map<String, Object?> jObject) {
    final jSaveVersion = jObject['inkSaveVersion'];
    if (jSaveVersion == null) {
      throw SystemException("ink save format incorrect, can't load.");
    } else if ((jSaveVersion as int) < kMinCompatibleLoadVersion) {
      throw SystemException(
        "Ink save format isn't compatible with the current version (saw "
        "'$jSaveVersion', but minimum is $kMinCompatibleLoadVersion), so "
        "can't load.",
      );
    }

    // Flows: Always exists in latest format (even if there's just one
    // default) but this dictionary doesn't exist in prev format
    final flowsObj = jObject['flows'];
    if (flowsObj != null) {
      final flowsObjDict = flowsObj as Map<String, Object?>;

      // Single default flow
      if (flowsObjDict.length == 1) {
        _namedFlows = null;
      }
      // Multi-flow, need to create flows dict
      else if (_namedFlows == null) {
        _namedFlows = {};
      }
      // Multi-flow, already have a flows dict
      else {
        _namedFlows?.clear();
      }

      // Load up each flow (there may only be one)
      for (final namedFlowObj in flowsObjDict.entries) {
        final name = namedFlowObj.key;
        final flowObj = namedFlowObj.value as Map<String, Object?>;

        // Load up this flow using JSON data
        final flow = Flow.fromJson(name, story, flowObj);

        if (flowsObjDict.length == 1) {
          _currentFlow = Flow.fromJson(name, story, flowObj);
        } else {
          _namedFlows?[name] = flow;
        }
      }

      final named = _namedFlows;
      if (named != null && named.length > 1) {
        final currFlowName = jObject['currentFlowName'] as String;
        final flow = named[currFlowName];
        if (flow == null) {
          throw SystemException(
            "The given key '$currFlowName' was not present in the dictionary.",
          );
        }
        _currentFlow = flow;
      }
    }
    // Old format: individually load up callstack, output stream, choices in
    // current/default flow
    else {
      _namedFlows = null;
      _currentFlow.name = kDefaultFlowName;
      _currentFlow.callStack.setJsonToken(
        jObject['callstackThreads'] as Map<String, Object?>,
        story,
      );
      _currentFlow.outputStream = JsonSerialisation.jArrayToRuntimeObjList(
        jObject['outputStream'] as List<Object?>,
      );
      _currentFlow.currentChoices =
          JsonSerialisation.jArrayToRuntimeObjList<Choice>(
            jObject['currentChoices'] as List<Object?>,
          );

      final jChoiceThreadsObj = jObject['choiceThreads'];
      _currentFlow.loadFlowChoiceThreads(
        jChoiceThreadsObj as Map<String, Object?>?,
        story,
      );
    }

    _outputStreamDirty();
    _aliveFlowNamesDirty = true;

    variablesState.setJsonToken(
      jObject['variablesState'] as Map<String, Object?>,
    );
    variablesState.callStack = _currentFlow.callStack;

    evaluationStack = JsonSerialisation.jArrayToRuntimeObjList(
      jObject['evalStack'] as List<Object?>,
    );

    final currentDivertTargetPath = jObject['currentDivertTarget'];
    if (currentDivertTargetPath != null) {
      final divertPath = Path.fromString(currentDivertTargetPath.toString());
      divertedPointer = story.pointerAtPath(divertPath);
    }

    _visitCounts = JsonSerialisation.jObjectToIntDictionary(
      jObject['visitCounts'] as Map<String, Object?>,
    );
    _turnIndices = JsonSerialisation.jObjectToIntDictionary(
      jObject['turnIndices'] as Map<String, Object?>,
    );

    currentTurnIndex = jObject['turnIdx'] as int;
    storySeed = jObject['storySeed'] as int;

    // Not optional, but bug in inkjs means it's actually missing in inkjs
    // saves
    final previousRandomObj = jObject['previousRandom'];
    previousRandom = previousRandomObj == null ? 0 : previousRandomObj as int;
  }

  /// Clears [currentErrors] and [currentWarnings].
  void resetErrors() {
    currentErrors = null;
    currentWarnings = null;
  }

  /// Clears the output stream, optionally replacing it with [objs].
  void resetOutput([List<InkObject>? objs]) {
    outputStream.clear();
    if (objs != null) outputStream.addAll(objs);
    _outputStreamDirty();
  }

  /// Push to output stream, but split out newlines in text for consistency
  /// in dealing with them later.
  void pushToOutputStream(InkObject obj) {
    if (obj is StringValue) {
      final listText = _trySplittingHeadTailWhitespace(obj);
      if (listText != null) {
        for (final textObj in listText) {
          _pushToOutputStreamIndividual(textObj);
        }
        _outputStreamDirty();
        return;
      }
    }

    _pushToOutputStreamIndividual(obj);

    _outputStreamDirty();
  }

  /// Removes the last [count] objects from the output stream.
  void popFromOutputStream(int count) {
    outputStream.removeRange(outputStream.length - count, outputStream.length);
    _outputStreamDirty();
  }

  // At both the start and the end of the string, split out the new lines
  // like so:
  //
  //  "   \n  \n     \n  the string \n is awesome \n     \n     "
  //      ^-----------^                           ^-------^
  //
  // Excess newlines are converted into single newlines, and spaces
  // discarded. Outside spaces are significant and retained. "Interior"
  // newlines within the main string are ignored, since this is for the
  // purpose of gluing only.
  //
  //  - If no splitting is necessary, null is returned.
  //  - A newline on its own is returned in a list for consistency.
  List<StringValue>? _trySplittingHeadTailWhitespace(StringValue single) {
    final str = single.value;

    var headFirstNewlineIdx = -1;
    var headLastNewlineIdx = -1;
    for (var i = 0; i < str.length; i++) {
      final c = str[i];
      if (c == '\n') {
        if (headFirstNewlineIdx == -1) headFirstNewlineIdx = i;
        headLastNewlineIdx = i;
      } else if (c == ' ' || c == '\t') {
        continue;
      } else {
        break;
      }
    }

    var tailLastNewlineIdx = -1;
    var tailFirstNewlineIdx = -1;
    for (var i = str.length - 1; i >= 0; i--) {
      final c = str[i];
      if (c == '\n') {
        if (tailLastNewlineIdx == -1) tailLastNewlineIdx = i;
        tailFirstNewlineIdx = i;
      } else if (c == ' ' || c == '\t') {
        continue;
      } else {
        break;
      }
    }

    // No splitting to be done?
    if (headFirstNewlineIdx == -1 && tailLastNewlineIdx == -1) return null;

    final listTexts = <StringValue>[];
    var innerStrStart = 0;
    var innerStrEnd = str.length;

    if (headFirstNewlineIdx != -1) {
      if (headFirstNewlineIdx > 0) {
        final leadingSpaces = StringValue(
          str.substring(0, headFirstNewlineIdx),
        );
        listTexts.add(leadingSpaces);
      }
      listTexts.add(StringValue('\n'));
      innerStrStart = headLastNewlineIdx + 1;
    }

    if (tailLastNewlineIdx != -1) innerStrEnd = tailFirstNewlineIdx;

    if (innerStrEnd > innerStrStart) {
      final innerStrText = str.substring(innerStrStart, innerStrEnd);
      listTexts.add(StringValue(innerStrText));
    }

    if (tailLastNewlineIdx != -1 && tailFirstNewlineIdx > headLastNewlineIdx) {
      listTexts.add(StringValue('\n'));
      if (tailLastNewlineIdx < str.length - 1) {
        final numSpaces = (str.length - tailLastNewlineIdx) - 1;
        final trailingSpaces = StringValue(
          str.substring(
            tailLastNewlineIdx + 1,
            tailLastNewlineIdx + 1 + numSpaces,
          ),
        );
        listTexts.add(trailingSpaces);
      }
    }

    return listTexts;
  }

  void _pushToOutputStreamIndividual(InkObject obj) {
    var includeInOutput = true;

    // New glue, so chomp away any whitespace from the end of the stream
    if (obj is Glue) {
      _trimNewlinesFromOutputStream();
      includeInOutput = true;
    }
    // New text: do we really want to append it, if it's whitespace?
    // Two different reasons for whitespace to be thrown away:
    //   - Function start/end trimming
    //   - User defined glue: <>
    // We also need to know when to stop trimming, when there's
    // non-whitespace.
    else if (obj is StringValue) {
      final text = obj;

      // Where does the current function call begin?
      var functionTrimIndex = -1;
      final currEl = callStack.currentElement;
      if (currEl.type == PushPopType.function) {
        functionTrimIndex = currEl.functionStartInOuputStream;
      }

      // Do 2 things:
      //  - Find latest glue
      //  - Check whether we're in the middle of string evaluation
      // If we're in string eval within the current function, we
      // don't want to trim back further than the length of the current
      // string.
      var glueTrimIndex = -1;
      for (var i = outputStream.length - 1; i >= 0; i--) {
        final o = outputStream[i];

        // Find latest glue
        if (o is Glue) {
          glueTrimIndex = i;
          break;
        }
        // Don't function-trim past the start of a string evaluation section
        else if (o is ControlCommand &&
            o.commandType == CommandType.beginString) {
          if (i >= functionTrimIndex) functionTrimIndex = -1;
          break;
        }
      }

      // Where is the most agressive (earliest) trim point?
      var trimIndex = -1;
      if (glueTrimIndex != -1 && functionTrimIndex != -1) {
        trimIndex = functionTrimIndex < glueTrimIndex
            ? functionTrimIndex
            : glueTrimIndex;
      } else if (glueTrimIndex != -1) {
        trimIndex = glueTrimIndex;
      } else {
        trimIndex = functionTrimIndex;
      }

      // So, are we trimming then?
      if (trimIndex != -1) {
        // While trimming, we want to throw all newlines away,
        // whether due to glue or the start of a function
        if (text.isNewline) {
          includeInOutput = false;
        }
        // Able to completely reset when normal text is pushed
        else if (text.isNonWhitespace) {
          if (glueTrimIndex > -1) _removeExistingGlue();

          // Tell all functions in callstack that we have seen proper text,
          // so trimming whitespace at the start is done.
          if (functionTrimIndex > -1) {
            final callstackElements = callStack.elements;
            for (var i = callstackElements.length - 1; i >= 0; i--) {
              final el = callstackElements[i];
              if (el.type == PushPopType.function) {
                el.functionStartInOuputStream = -1;
              } else {
                break;
              }
            }
          }
        }
      }
      // De-duplicate newlines, and don't ever lead with a newline
      else if (text.isNewline) {
        if (outputStreamEndsInNewline || !outputStreamContainsContent) {
          includeInOutput = false;
        }
      }
    }

    if (includeInOutput) {
      outputStream.add(obj);
      _outputStreamDirty();
    }
  }

  void _trimNewlinesFromOutputStream() {
    var removeWhitespaceFrom = -1;

    // Work back from the end, and try to find the point where
    // we need to start removing content.
    //  - Simply work backwards to find the first newline in a string of
    //    whitespace
    // e.g. This is the content   \n   \n\n
    //                            ^---------^ whitespace to remove
    //                        ^--- first while loop stops here
    var i = outputStream.length - 1;
    while (i >= 0) {
      final obj = outputStream[i];
      if (obj is ControlCommand ||
          (obj is StringValue && obj.isNonWhitespace)) {
        break;
      } else if (obj is StringValue && obj.isNewline) {
        removeWhitespaceFrom = i;
      }
      i--;
    }

    // Remove the whitespace
    if (removeWhitespaceFrom >= 0) {
      i = removeWhitespaceFrom;
      while (i < outputStream.length) {
        if (outputStream[i] is StringValue) {
          outputStream.removeAt(i);
        } else {
          i++;
        }
      }
    }

    _outputStreamDirty();
  }

  // Only called when non-whitespace is appended
  void _removeExistingGlue() {
    for (var i = outputStream.length - 1; i >= 0; i--) {
      final c = outputStream[i];
      if (c is Glue) {
        outputStream.removeAt(i);
      } else if (c is ControlCommand) {
        // e.g. BeginString
        break;
      }
    }

    _outputStreamDirty();
  }

  /// Whether the output stream ends in a newline.
  bool get outputStreamEndsInNewline {
    if (outputStream.isNotEmpty) {
      for (var i = outputStream.length - 1; i >= 0; i--) {
        final obj = outputStream[i];
        if (obj is ControlCommand) break; // e.g. BeginString
        if (obj is StringValue) {
          if (obj.isNewline) {
            return true;
          } else if (obj.isNonWhitespace) {
            break;
          }
        }
      }
    }

    return false;
  }

  /// Whether the output stream holds any text.
  bool get outputStreamContainsContent {
    for (final content in outputStream) {
      if (content is StringValue) return true;
    }
    return false;
  }

  /// Whether a string is being built for an expression (for example choice
  /// text).
  bool get inStringEvaluation {
    for (var i = outputStream.length - 1; i >= 0; i--) {
      final cmd = outputStream[i];
      if (cmd is ControlCommand && cmd.commandType == CommandType.beginString) {
        return true;
      }
    }

    return false;
  }

  /// Pushes [obj] onto the evaluation stack; list values get their origins
  /// resolved first.
  void pushEvaluationStack(InkObject? obj) {
    // Include metadata about the origin List for list values when
    // they're used, so that lower level functions can make use
    // of the origin list to get related items, or make comparisons
    // with the integer values etc.
    if (obj is ListValue) {
      // Update origin when list is has something to indicate the list origin
      final rawList = obj.value;
      final originNames = rawList.originNames;
      if (originNames != null) {
        final origins = rawList.origins ??= [];
        origins.clear();

        for (final n in originNames) {
          final def = story.listDefinitions?.tryListGetDefinition(n);
          if (def != null && !origins.contains(def)) origins.add(def);
        }
      }
    }

    if (obj == null) {
      throw SystemException(
        'Object reference not set to an instance of an object.',
      );
    }
    evaluationStack.add(obj);
  }

  /// Removes and returns the top of the evaluation stack.
  InkObject popEvaluationStack() {
    _checkEvaluationStackNotEmpty();
    return evaluationStack.removeLast();
  }

  /// The top of the evaluation stack.
  InkObject peekEvaluationStack() {
    _checkEvaluationStackNotEmpty();
    return evaluationStack.last;
  }

  /// The reference indexes `evaluationStack[Count - 1]`, so an empty stack
  /// fails with .NET's list message rather than a Dart `RangeError`.
  void _checkEvaluationStackNotEmpty() {
    if (evaluationStack.isEmpty) {
      throw SystemException(
        'Index was out of range. Must be non-negative and less than the size '
        "of the collection. (Parameter 'index')",
      );
    }
  }

  /// Removes and returns the top [numberOfObjects] values, oldest first.
  /// `PopEvaluationStack(int)` in C#.
  List<InkObject> popEvaluationStackCount(int numberOfObjects) {
    if (numberOfObjects > evaluationStack.length) {
      throw SystemException('trying to pop too many objects');
    }

    final start = evaluationStack.length - numberOfObjects;
    final popped = evaluationStack.sublist(start);
    evaluationStack.removeRange(start, evaluationStack.length);
    return popped;
  }

  /// Ends the current ink flow, unwrapping the callstack but without
  /// affecting any variables. Useful if the ink is (say) in the middle
  /// a nested tunnel, and you want it to reset so that you can divert
  /// elsewhere using ChoosePathString(). Otherwise, after finishing
  /// the content you diverted to, it would continue where it left off.
  /// Calling this is equivalent to calling -> END in ink.
  void forceEnd() {
    callStack.reset();

    _currentFlow.currentChoices.clear();

    currentPointer = Pointer.nullPointer;
    previousPointer = Pointer.nullPointer;

    didSafeExit = true;
  }

  // Add the end of a function call, trim any whitespace from the end.
  // We always trim the start and end of the text that a function produces.
  // The start whitespace is discard as it is generated, and the end
  // whitespace is trimmed in one go here when we pop the function.
  void _trimWhitespaceFromFunctionEnd() {
    var functionStartPoint =
        callStack.currentElement.functionStartInOuputStream;

    // If the start point has become -1, it means that some non-whitespace
    // text has been pushed, so it's safe to go as far back as we're able.
    if (functionStartPoint == -1) functionStartPoint = 0;

    // Trim whitespace from END of function call
    for (var i = outputStream.length - 1; i >= functionStartPoint; i--) {
      final obj = outputStream[i];
      if (obj is! StringValue) continue;

      if (obj.isNewline || obj.isInlineWhitespace) {
        outputStream.removeAt(i);
        _outputStreamDirty();
      } else {
        break;
      }
    }
  }

  /// Pops the call stack, trimming trailing whitespace when leaving a
  /// function. Throws if the top isn't of [popType].
  void popCallstack([PushPopType? popType]) {
    // Add the end of a function call, trim any whitespace from the end.
    if (callStack.currentElement.type == PushPopType.function) {
      _trimWhitespaceFromFunctionEnd();
    }

    callStack.pop(popType);
  }

  // Don't make public since the method need to be wrapped in Story for visit
  // counting
  /// Moves the story to [path] and clears the choices, optionally counting a
  /// new turn.
  void setChosenPath(Path path, {required bool incrementingTurnIndex}) {
    // Changing direction, assume we need to clear current set of choices
    _currentFlow.currentChoices.clear();

    var newPointer = story.pointerAtPath(path);
    if (!newPointer.isNull && newPointer.index == -1) {
      newPointer = Pointer(newPointer.container, 0);
    }

    currentPointer = newPointer;

    if (incrementingTurnIndex) currentTurnIndex++;
  }

  /// Starts evaluating [funcContainer] as a function called from the game,
  /// with [arguments] on the evaluation stack.
  void startFunctionEvaluationFromGame(
    Container funcContainer,
    List<Object?>? arguments,
  ) {
    callStack.push(
      PushPopType.functionEvaluationFromGame,
      externalEvaluationStackHeight: evaluationStack.length,
    );
    callStack.currentElement.currentPointer = Pointer.startOf(funcContainer);

    passArgumentsToEvaluationStack(arguments);
  }

  /// Pushes game-side [arguments] (`int`, `double`, `String`, `bool` or
  /// [InkList]) onto the evaluation stack.
  void passArgumentsToEvaluationStack(List<Object?>? arguments) {
    // Pass arguments onto the evaluation stack
    if (arguments != null) {
      for (var i = 0; i < arguments.length; i++) {
        final a = arguments[i];
        if (!(a is int ||
            a is double ||
            a is String ||
            a is bool ||
            a is InkList)) {
          throw ArgumentError(
            'ink arguments when calling EvaluateFunction / '
            'ChoosePathStringWithParameters must be int, float, string, bool '
            'or InkList. Argument was '
            '${a == null ? 'null' : a.runtimeType}',
          );
        }

        pushEvaluationStack(AbstractValue.create(a));
      }
    }
  }

  /// Ends a function evaluation started from the game, if one is current;
  /// returns whether it was.
  bool tryExitFunctionEvaluationFromGame() {
    if (callStack.currentElement.type ==
        PushPopType.functionEvaluationFromGame) {
      currentPointer = Pointer.nullPointer;
      didSafeExit = true;
      return true;
    }

    return false;
  }

  /// Finishes a function evaluation started from the game and returns its
  /// result: an `int`, `double`, `String`, `bool`, [InkList], a divert
  /// target's path as a string, or null.
  Object? completeFunctionEvaluationFromGame() {
    if (callStack.currentElement.type !=
        PushPopType.functionEvaluationFromGame) {
      throw SystemException(
        'Expected external function evaluation to be complete. Stack trace: '
        '${callStack.callStackTrace}',
      );
    }

    final originalEvaluationStackHeight =
        callStack.currentElement.evaluationStackHeightWhenPushed;

    // Do we have a returned value?
    // Potentially pop multiple values off the stack, in case we need
    // to clean up after ourselves (e.g. caller of EvaluateFunction may
    // have passed too many arguments, and we currently have no way to check
    // for that)
    InkObject? returnedObj;
    while (evaluationStack.length > originalEvaluationStackHeight) {
      final poppedObj = popEvaluationStack();
      returnedObj ??= poppedObj;
    }

    // Finally, pop the external function evaluation
    popCallstack(PushPopType.functionEvaluationFromGame);

    // What did we get back?
    if (returnedObj != null) {
      if (returnedObj is Void) return null;

      // Some kind of value, if not void
      final returnVal = returnedObj as AbstractValue;

      // DivertTargets get returned as the string of components
      // (rather than a Path, which isn't public)
      if (returnVal is DivertTargetValue) {
        return returnVal.valueObject.toString();
      }

      // Other types can just have their exact object type:
      // int, float, string. VariablePointers get returned as strings.
      return returnVal.valueObject;
    }

    return null;
  }

  /// Adds [message] to [currentErrors] or, with [isWarning], to
  /// [currentWarnings].
  void addError(String message, {required bool isWarning}) {
    if (!isWarning) {
      (currentErrors ??= []).add(message);
    } else {
      (currentWarnings ??= []).add(message);
    }
  }

  void _outputStreamDirty() {
    _outputStreamTextDirty = true;
    _outputStreamTagsDirty = true;
  }

  // REMEMBER! REMEMBER! REMEMBER!
  // When adding state, update the Copy method and serialisation
  // REMEMBER! REMEMBER! REMEMBER!

  Map<String, int> _visitCounts = {};
  Map<String, int> _turnIndices = {};

  bool _outputStreamTextDirty = true;
  bool _outputStreamTagsDirty = true;

  StatePatch? _patch;

  Flow _currentFlow;
  Map<String, Flow>? _namedFlows;

  /// The name of the flow a story starts in.
  static const kDefaultFlowName = 'DEFAULT_FLOW';
  bool _aliveFlowNamesDirty = true;
}
