// Port of ink's Story.cs (inkjs Story.ts).

import 'error.dart';
import 'float32.dart';
import 'json/json_serialisation.dart';
import 'json/simple_json.dart';
import 'prng.dart';
import 'profiler.dart';
import 'runtime/choice.dart';
import 'runtime/choice_point.dart';
import 'runtime/container.dart';
import 'runtime/control_command.dart';
import 'runtime/debug_metadata.dart';
import 'runtime/divert.dart';
import 'runtime/divert_target_value.dart';
import 'runtime/float_value.dart';
import 'runtime/ink_list.dart';
import 'runtime/ink_object.dart';
import 'runtime/int_value.dart';
import 'runtime/list_definition.dart';
import 'runtime/list_definitions_origin.dart';
import 'runtime/list_value.dart';
import 'runtime/native_function_call.dart';
import 'runtime/path.dart';
import 'runtime/pointer.dart';
import 'runtime/push_pop.dart';
import 'runtime/search_result.dart';
import 'runtime/string_value.dart';
import 'runtime/tag.dart';
import 'runtime/value.dart';
import 'runtime/variable_assignment.dart';
import 'runtime/variable_pointer_value.dart';
import 'runtime/variable_reference.dart';
import 'runtime/void.dart';
import 'state/story_state.dart';
import 'state/variables_state.dart';
import 'story_exception.dart';
import 'system_exception.dart';

/// A game-side function callable from ink; receives the ink arguments in
/// order.
typedef ExternalFunction = Object? Function(List<Object?> args);

/// Receives a global variable's new value (`int`, `double`, `String`,
/// `bool` or [InkList]).
typedef VariableObserver = void Function(String variableName, Object? newValue);

class _ExternalFunctionDef {
  _ExternalFunctionDef(this.function, this.lookaheadSafe);
  final ExternalFunction function;
  final bool lookaheadSafe;
}

enum _OutputStateChange { noChange, extendedBeyondNewline, newlineRemoved }

/// A Story is the core class that represents a complete Ink narrative, and
/// manages the evaluation and state of it.
///
/// {@category Getting started}
///
/// {@category Game functions and variables}
///
/// {@category Saving and loading}
///
/// {@category Flows}
///
/// {@category Matching Unity and Inky}
class Story extends InkObject {
  /// The current version of the ink story file format.
  static const inkVersionCurrent = 21;

  // Version numbers are for engine itself and story file, rather
  // than the story state save format
  //  -- old engine, new format: always fail
  //  -- new engine, old format: possibly cope, based on this number
  // When incrementing the version number above, the question you
  // should ask yourself is:
  //  -- Will the engine be able to load an old story file from
  //     before I made these changes to the engine?
  //     If possible, you should support it, though it's not as
  //     critical as loading old save games, since it's an
  //     in-development problem only.

  /// The minimum legacy version of ink that can be loaded by the current
  /// version of the code.
  static const inkVersionMinimumCompatible = 18;

  /// The list of Choice objects available at the current point in
  /// the Story. This list will be populated as the Story is stepped
  /// through with the Continue() method. Once canContinue becomes
  /// false, this list will be populated, and is usually
  /// (but not always) on the final Continue() step.
  List<Choice> get currentChoices {
    // Don't include invisible choices for external usage.
    final choices = <Choice>[];
    for (final c in _state.currentChoices) {
      if (!c.isInvisibleDefault) {
        c.index = choices.length;
        choices.add(c);
      }
    }
    return choices;
  }

  /// The latest line of text to be generated from a Continue() call.
  String get currentText {
    _ifAsyncWeCant("call currentText since it's a work in progress");
    return state.currentText;
  }

  /// Gets a list of tags as defined with '#' in source that were seen
  /// during the latest Continue() call.
  List<String> get currentTags {
    _ifAsyncWeCant("call currentTags since it's a work in progress");
    return state.currentTags;
  }

  /// Any errors generated during evaluation of the Story.
  List<String>? get currentErrors => state.currentErrors;

  /// Any warnings generated during evaluation of the Story.
  List<String>? get currentWarnings => state.currentWarnings;

  /// The current flow name if using multi-flow functionality - see
  /// SwitchFlow
  String get currentFlowName => state.currentFlowName;

  /// Is the default flow currently active? By definition, will also return
  /// true if not using multi-flow functionality - see SwitchFlow
  bool get currentFlowIsDefaultFlow => state.currentFlowIsDefaultFlow;

  /// Names of currently alive flows (not including the default flow)
  List<String> get aliveFlowNames => state.aliveFlowNames;

  /// Whether the currentErrors list contains any errors.
  bool get hasError => state.hasError;

  /// Whether the currentWarnings list contains any warnings.
  bool get hasWarning => state.hasWarning;

  /// The VariablesState object contains all the global variables in the
  /// story. However, note that there's more to the state of a Story than
  /// just the global variables. This is a convenience accessor to the full
  /// state object.
  VariablesState get variablesState => state.variablesState;

  /// The story's list definitions, or null if it declares no lists.
  ListDefinitionsOrigin? get listDefinitions => _listDefinitions;

  /// The entire current state of the story including (but not limited to):
  ///
  ///  * Global variables
  ///  * Temporary variables
  ///  * Read/visit and turn counts
  ///  * The callstack and evaluation stacks
  ///  * The current threads
  StoryState get state => _state;

  /// Error handler for all runtime errors in ink - i.e. problems
  /// with the source ink itself that are only discovered when playing
  /// the story.
  /// It's strongly recommended that you assign an error handler to your
  /// story instance to avoid getting exceptions for ink errors.
  ErrorHandler? onError;

  /// Callback for when ContinueInternal is complete
  void Function()? onDidContinue;

  /// Callback for when a choice is about to be executed
  void Function(Choice)? onMakeChoice;

  /// Callback for when a function is about to be evaluated
  void Function(String, List<Object?>?)? onEvaluateFunction;

  /// Callback for when a function has been evaluated
  /// This is necessary because evaluating a function can cause continuing
  void Function(String, List<Object?>?, String, Object?)?
  onCompleteEvaluateFunction;

  /// Callback for when a path string is chosen
  void Function(String, List<Object?>?)? onChoosePathString;

  /// Start recording ink profiling information during calls to Continue on
  /// Story. Return a Profiler instance that you can request a report from
  /// when you're finished.
  Profiler startProfiling() {
    _ifAsyncWeCant('start profiling');
    return _profiler = Profiler();
  }

  /// Stop recording ink profiling information during calls to Continue on
  /// Story. To generate a report from the profiler, call
  /// `profiler.report()` on the Profiler that [startProfiling] returned.
  void endProfiling() => _profiler = null;

  /// Warning: When creating a Story using this constructor, you need to
  /// call ResetState on it before use. Intended for compiler use only.
  /// For normal use, use the constructor that takes a json string.
  Story.fromContainer(
    Container? contentContainer, [
    List<ListDefinition>? lists,
  ]) : _mainContentContainer = contentContainer {
    if (lists != null) _listDefinitions = ListDefinitionsOrigin(lists);
  }

  /// Construct a Story object using a JSON string compiled through inklecate.
  factory Story.fromJson(String jsonString) =>
      Story(SimpleJson.textToDictionary(jsonString));

  /// Construct a Story object from the decoded compiled JSON.
  ///
  /// [Story.fromJson] is exact on every platform. A map from `jsonDecode`
  /// works on the Dart VM and AOT, where `3.0` decodes as a double, but not
  /// on the web, where `3` and `3.0` decode alike and a float literal loses
  /// its type.
  Story(Map<String, Object?> rootObject) : _mainContentContainer = null {
    final versionObj = rootObject['inkVersion'];
    if (versionObj == null) {
      throw SystemException(
        "ink version number not found. Are you sure it's a valid .ink.json "
        'file?',
      );
    }

    final formatFromFile = versionObj as int;
    if (formatFromFile > inkVersionCurrent) {
      throw SystemException(
        'Version of ink used to build story was newer than the current '
        'version of the engine',
      );
    } else if (formatFromFile < inkVersionMinimumCompatible) {
      throw SystemException(
        'Version of ink used to build story is too old to be loaded by this '
        'version of the engine',
      );
    }

    final rootToken = rootObject['root'];
    if (rootToken == null) {
      throw SystemException(
        "Root node for ink not found. Are you sure it's a valid .ink.json "
        'file?',
      );
    }

    final listDefsObj = rootObject['listDefs'];
    if (listDefsObj != null) {
      _listDefinitions = JsonSerialisation.jTokenToListDefinitions(listDefsObj);
    }

    _mainContentContainer =
        JsonSerialisation.jTokenToRuntimeObject(rootToken) as Container?;

    resetState();
  }

  /// The Story itself in JSON representation.
  String toJson() {
    final writer = Writer();
    _toJson(writer);
    return writer.toString();
  }

  void _toJson(Writer writer) {
    writer.writeObjectStart();

    writer.writeIntProperty('inkVersion', inkVersionCurrent);

    // Main container content
    writer.writePropertyWith(
      'root',
      (w) => JsonSerialisation.writeRuntimeContainer(w, _root),
    );

    // List definitions
    final defs = _listDefinitions;
    if (defs != null) {
      writer.writePropertyStart('listDefs');
      writer.writeObjectStart();

      for (final def in defs.lists) {
        writer.writePropertyStart(def.name);
        writer.writeObjectStart();

        for (final itemToVal in def.items.entries) {
          writer.writeIntProperty(
            itemToVal.key.itemName ?? '',
            itemToVal.value,
          );
        }

        writer.writeObjectEnd();
        writer.writePropertyEnd();
      }

      writer.writeObjectEnd();
      writer.writePropertyEnd();
    }

    writer.writeObjectEnd();
  }

  /// Reset the Story back to its initial state as it was when it was
  /// first constructed.
  void resetState() {
    // TODO: Could make this possible
    _ifAsyncWeCant('ResetState');

    _state = StoryState(this);
    _state.variablesState.variableChangedEvent = _variableStateDidChangeEvent;

    _resetGlobals();
  }

  void _resetErrors() => _state.resetErrors();

  /// Unwinds the callstack. Useful to reset the Story's evaluation
  /// without actually changing any meaningful state, for example if
  /// you want to exit a section of story prematurely and tell it to
  /// go elsewhere with a call to ChoosePathString(...).
  /// Doing so without calling ResetCallstack() could cause unexpected
  /// issues if, for example, the Story was in a tunnel already.
  void resetCallstack() {
    _ifAsyncWeCant('ResetCallstack');

    _state.forceEnd();
  }

  void _resetGlobals() {
    if (_root.namedContent.containsKey('global decl')) {
      final originalPointer = state.currentPointer;

      choosePath(Path.fromString('global decl'), incrementingTurnIndex: false);

      // Continue, but without validating external bindings,
      // since we may be doing this reset at initialisation time.
      _continueInternal();

      state.currentPointer = originalPointer;
    }

    state.variablesState.snapshotDefaultGlobals();
  }

  /// Switches to the flow [flowName], creating it if needed (experimental).
  /// Each flow has its own position, call stack, output and choices; globals
  /// are shared.
  void switchFlow(String flowName) {
    _ifAsyncWeCant('switch flow');
    if (_asyncSaving) {
      throw SystemException(
        "Story is already in background saving mode, can't switch flow to "
        '$flowName',
      );
    }

    state.switchFlowInternal(flowName);
  }

  /// Removes the flow [flowName], switching to the default flow if it was
  /// current (experimental).
  void removeFlow(String flowName) => state.removeFlowInternal(flowName);

  /// Switches back to the default flow (experimental).
  void switchToDefaultFlow() => state.switchToDefaultFlowInternal();

  /// Continue the story for one line of content, if possible.
  /// If you're not sure if there's more content available, for example if
  /// you want to check whether you're at a choice point or at the end of
  /// the story, you should call `canContinue` before calling this function.
  ///
  /// `Continue` in the reference; `continue` is reserved in Dart.
  String continueStory() {
    continueAsync(0);
    return currentText;
  }

  /// Check whether more content is available if you were to call Continue()
  /// - i.e. are we mid story rather than at a choice point or at the end.
  bool get canContinue => state.canContinue;

  /// If ContinueAsync was called (with milliseconds limit > 0) then this
  /// property will return false if the ink evaluation isn't yet finished,
  /// and you need to call it again in order for the Continue to fully
  /// complete.
  bool get asyncContinueComplete => !_asyncContinueActive;

  /// An "asnychronous" version of Continue that only partially evaluates
  /// the ink, with a budget of a certain time limit. It will exit ink
  /// evaluation early if the evaluation isn't complete within the time
  /// limit, with the asyncContinueComplete property being false.
  void continueAsync(double millisecsLimitAsync) {
    if (!_hasValidatedExternals) validateExternalBindings();

    _continueInternal(millisecsLimitAsync);
  }

  void _continueInternal([double millisecsLimitAsync = 0]) {
    _profiler?.preContinue();

    final isAsyncTimeLimited = millisecsLimitAsync > 0;

    _recursiveContinueCount++;

    // Doing either:
    //  - full run through non-async (so not active and don't want to be)
    //  - Starting async run-through
    if (!_asyncContinueActive) {
      _asyncContinueActive = isAsyncTimeLimited;

      if (!canContinue) {
        throw SystemException(
          "Can't continue - should check canContinue before calling Continue",
        );
      }

      _state.didSafeExit = false;

      _state.resetOutput();

      // It's possible for ink to call game to call ink to call game etc
      // In this case, we only want to batch observe variable changes
      // for the outermost call.
      if (_recursiveContinueCount == 1) {
        _state.variablesState.startVariableObservation();
      }
    }
    // Continuing an existing async run-through?
    // If it's now complete, we need to exit async mode
    else if (_asyncContinueActive && !isAsyncTimeLimited) {
      _asyncContinueActive = false;
    }

    // Start timing
    final durationStopwatch = Stopwatch()..start();

    var outputStreamEndsInNewline = false;
    _sawLookaheadUnsafeFunctionAfterNewline = false;
    do {
      try {
        outputStreamEndsInNewline = _continueSingleStep();
      } on StoryException catch (e) {
        _addError(e.message, useEndLineNumber: e.useEndLineNumber);
        break;
      }

      if (outputStreamEndsInNewline) break;

      // Run out of async time?
      if (_asyncContinueActive &&
          durationStopwatch.elapsedMilliseconds > millisecsLimitAsync) {
        break;
      }
    } while (canContinue);

    durationStopwatch.stop();

    Map<String, InkObject>? changedVariablesToObserve;

    // 4 outcomes:
    //  - got newline (so finished this line of text)
    //  - can't continue (e.g. choices or ending)
    //  - ran out of time during evaluation
    //  - error
    //
    // Successfully finished evaluation in time (or in error)
    if (outputStreamEndsInNewline || !canContinue) {
      // Need to rewind, due to evaluating further than we should?
      if (_stateSnapshotAtLastNewline != null) _restoreStateSnapshot();

      // Finished a section of content / reached a choice point?
      if (!canContinue) {
        if (state.callStack.canPopThread) {
          _addError(
            'Thread available to pop, threads should always be flat by the '
            'end of evaluation?',
          );
        }

        if (state.generatedChoices.isEmpty &&
            !state.didSafeExit &&
            _temporaryEvaluationContainer == null) {
          if (state.callStack.canPopType(PushPopType.tunnel)) {
            _addError(
              "unexpectedly reached end of content. Do you need a '->->' to "
              'return from a tunnel?',
            );
          } else if (state.callStack.canPopType(PushPopType.function)) {
            _addError(
              "unexpectedly reached end of content. Do you need a '~ return'?",
            );
          } else if (!state.callStack.canPop) {
            _addError(
              "ran out of content. Do you need a '-> DONE' or '-> END'?",
            );
          } else {
            _addError(
              'unexpectedly reached end of content for unknown reason. Please '
              'debug compiler!',
            );
          }
        }
      }

      state.didSafeExit = false;
      _sawLookaheadUnsafeFunctionAfterNewline = false;

      if (_recursiveContinueCount == 1) {
        changedVariablesToObserve = _state.variablesState
            .completeVariableObservation();
      }

      _asyncContinueActive = false;
      onDidContinue?.call();
    }

    _recursiveContinueCount--;

    _profiler?.postContinue();

    // Report any errors that occured during evaluation.
    // This may either have been StoryExceptions that were thrown
    // and caught during evaluation, or directly added with AddError.
    if (state.hasError || state.hasWarning) {
      final handler = onError;
      if (handler != null) {
        if (state.hasError) {
          for (final err in state.currentErrors ?? const <String>[]) {
            handler(err, ErrorType.error);
          }
        }
        if (state.hasWarning) {
          for (final err in state.currentWarnings ?? const <String>[]) {
            handler(err, ErrorType.warning);
          }
        }
        _resetErrors();
      }
      // Throw an exception since there's no error handler
      else {
        final sb = StringBuffer('Ink had ');
        final errors = state.currentErrors ?? const <String>[];
        final warnings = state.currentWarnings ?? const <String>[];
        if (state.hasError) {
          sb.write(errors.length);
          sb.write(errors.length == 1 ? ' error' : ' errors');
          if (state.hasWarning) sb.write(' and ');
        }
        if (state.hasWarning) {
          sb.write(warnings.length);
          sb.write(warnings.length == 1 ? ' warning' : ' warnings');
        }
        sb.write(
          '. It is strongly suggested that you assign an error handler to '
          'story.onError. The first issue was: ',
        );
        sb.write(state.hasError ? errors[0] : warnings[0]);

        // If you get this exception, please assign an error handler to your
        // story. If you're using Unity, you can do something like this when
        // you create your story:
        //
        // var story = new Ink.Runtime.Story(jsonTxt);
        // story.onError = (errorMessage, errorType) => {
        //     if( errorType == ErrorType.Warning )
        //         Debug.LogWarning(errorMessage);
        //     else
        //         Debug.LogError(errorMessage);
        // };
        //
        //
        throw StoryException(sb.toString());
      }
    }

    // Send out variable observation events at the last second, since it
    // might trigger new ink to be run
    if (changedVariablesToObserve != null &&
        changedVariablesToObserve.isNotEmpty) {
      _state.variablesState.notifyObservers(changedVariablesToObserve);
    }
  }

  bool _continueSingleStep() {
    _profiler?.preStep();

    // Run main step function (walks through content)
    _step();

    _profiler?.postStep();

    // Run out of content and we have a default invisible choice that we can
    // follow?
    if (!canContinue && !state.callStack.elementIsEvaluateFromGame) {
      _tryFollowDefaultInvisibleChoice();
    }

    _profiler?.preSnapshot();

    // Don't save/rewind during string evaluation, which is e.g. used for
    // choices
    if (!state.inStringEvaluation) {
      // We previously found a newline, but were we just double checking that
      // it wouldn't immediately be removed by glue?
      final snapshot = _stateSnapshotAtLastNewline;
      if (snapshot != null) {
        // Has proper text or a tag been added? Then we know that the newline
        // that was previously added is definitely the end of the line.
        final change = _calculateNewlineOutputStateChange(
          snapshot.currentText,
          state.currentText,
          snapshot.currentTags.length,
          state.currentTags.length,
        );

        // The last time we saw a newline, it was definitely the end of the
        // line, so we want to rewind to that point.
        if (change == _OutputStateChange.extendedBeyondNewline ||
            _sawLookaheadUnsafeFunctionAfterNewline) {
          _restoreStateSnapshot();

          // Hit a newline for sure, we're done
          return true;
        }
        // Newline that previously existed is no longer valid - e.g.
        // glue was encounted that caused it to be removed.
        else if (change == _OutputStateChange.newlineRemoved) {
          _discardSnapshot();
        }
      }

      // Current content ends in a newline - approaching end of our
      // evaluation
      if (state.outputStreamEndsInNewline) {
        // If we can continue evaluation for a bit:
        // Create a snapshot in case we need to rewind.
        // We're going to continue stepping in case we see glue or some
        // non-text content such as choices.
        if (canContinue) {
          // Don't bother to record the state beyond the current newline.
          // e.g.:
          // Hello world\n            // record state at the end of here
          // ~ complexCalculation()   // don't actually need this unless it
          //                          // generates text
          if (_stateSnapshotAtLastNewline == null) _stateSnapshot();
        }
        // Can't continue, so we're about to exit - make sure we
        // don't have an old state hanging around.
        else {
          _discardSnapshot();
        }
      }
    }

    _profiler?.postSnapshot();

    return false;
  }

  // Assumption: prevText is the snapshot where we saw a newline, and we're
  // checking whether we're really done with that line. Therefore prevText
  // will definitely end in a newline.
  //
  // We take tags into account too, so that a tag following a content line:
  //   Content
  //   # tag
  // ... doesn't cause the tag to be wrongly associated with the content
  // above.
  _OutputStateChange _calculateNewlineOutputStateChange(
    String prevText,
    String currText,
    int prevTagCount,
    int currTagCount,
  ) {
    // Simple case: nothing's changed, and we still have a newline
    // at the end of the current content
    final newlineStillExists =
        currText.length >= prevText.length &&
        prevText.isNotEmpty &&
        currText[prevText.length - 1] == '\n';
    if (prevTagCount == currTagCount &&
        prevText.length == currText.length &&
        newlineStillExists) {
      return _OutputStateChange.noChange;
    }

    // Old newline has been removed, it wasn't the end of the line after all
    if (!newlineStillExists) return _OutputStateChange.newlineRemoved;

    // Tag added - definitely the start of a new line
    if (currTagCount > prevTagCount) {
      return _OutputStateChange.extendedBeyondNewline;
    }

    // There must be new content - check whether it's just whitespace
    for (var i = prevText.length; i < currText.length; i++) {
      final c = currText[i];
      if (c != ' ' && c != '\t') {
        return _OutputStateChange.extendedBeyondNewline;
      }
    }

    // There's new text but it's just spaces and tabs, so there's still the
    // potential for glue to kill the newline.
    return _OutputStateChange.noChange;
  }

  /// Continue the story until the next choice point or until it runs out of
  /// content. This is as opposed to the Continue() method which only
  /// evaluates one line of output at a time.
  String continueMaximally() {
    _ifAsyncWeCant('ContinueMaximally');

    final sb = StringBuffer();

    while (canContinue) {
      sb.write(continueStory());
    }

    return sb.toString();
  }

  /// Looks up the content at [path] from the story's root.
  SearchResult contentAtPath(Path path) =>
      mainContentContainer.contentAtPath(path);

  /// The knot or top-level function named [name], or null.
  Container? knotContainerWithName(String name) {
    final namedContainer = mainContentContainer.namedContent[name];
    return namedContainer is Container ? namedContainer : null;
  }

  /// A pointer to the content at [path]; reports an error if it can't be
  /// found.
  Pointer pointerAtPath(Path path) {
    if (path.length == 0) return Pointer.nullPointer;

    Pointer p;

    var pathLengthToUse = path.length;

    SearchResult result;
    final last = path.lastComponent;
    if (last != null && last.isIndex) {
      pathLengthToUse = path.length - 1;
      result = mainContentContainer.contentAtPath(
        path,
        partialPathLength: pathLengthToUse,
      );
      p = Pointer(result.container, last.index);
    } else {
      result = mainContentContainer.contentAtPath(path);
      p = Pointer(result.container, -1);
    }

    final obj = result.obj;
    if (obj == null ||
        identical(obj, mainContentContainer) && pathLengthToUse > 0) {
      error(
        "Failed to find content at path '$path', and no approximation of it "
        'was possible.',
      );
    } else if (result.approximate) {
      warning(
        "Failed to find content at path '$path', so it was approximated to: "
        "'${obj.path}'.",
      );
    }

    return p;
  }

  // Maximum snapshot stack:
  //  - stateSnapshotDuringSave -- not retained, but returned to game code
  //  - _stateSnapshotAtLastNewline (has older patch)
  //  - _state (current, being patched)

  void _stateSnapshot() {
    _stateSnapshotAtLastNewline = _state;
    _state = _state.copyAndStartPatching(forBackgroundSave: false);
  }

  void _restoreStateSnapshot() {
    final snapshot = _stateSnapshotAtLastNewline;
    if (snapshot == null) return;

    // Patched state had temporarily hijacked our
    // VariablesState and set its own callstack on it,
    // so we need to restore that.
    // If we're in the middle of saving, we may also
    // need to give the VariablesState the old patch.
    snapshot.restoreAfterPatch();

    _state = snapshot;
    _stateSnapshotAtLastNewline = null;

    // If save completed while the above snapshot was
    // active, we need to apply any changes made since
    // the save was started but before the snapshot was made.
    if (!_asyncSaving) _state.applyAnyPatch();
  }

  void _discardSnapshot() {
    // Normally we want to integrate the patch
    // into the main global/counts dictionaries.
    // However, if we're in the middle of async
    // saving, we simply stay in a "patching" state,
    // albeit with the newer cloned patch.
    if (!_asyncSaving) _state.applyAnyPatch();

    // No longer need the snapshot.
    _stateSnapshotAtLastNewline = null;
  }

  /// Advanced usage!
  /// If you have a large story, and saving state to JSON takes too long for
  /// your framerate, you can temporarily freeze a copy of the state for
  /// saving on a separate thread. Internally, the engine maintains a "diff
  /// patch". When you've finished saving your state, call
  /// BackgroundSaveComplete() and that diff patch will be applied, allowing
  /// the story to continue in its usual mode.
  StoryState copyStateForBackgroundThreadSave() {
    _ifAsyncWeCant('start saving on a background thread');
    if (_asyncSaving) {
      throw SystemException(
        "Story is already in background saving mode, can't call "
        'CopyStateForBackgroundThreadSave again!',
      );
    }
    final stateToSave = _state;
    _state = _state.copyAndStartPatching(forBackgroundSave: true);
    _asyncSaving = true;
    return stateToSave;
  }

  /// See CopyStateForBackgroundThreadSave. This method releases the
  /// "frozen" save state, applying its patch that it was using internally.
  void backgroundSaveComplete() {
    // CopyStateForBackgroundThreadSave must be called outside
    // of any async ink evaluation, since otherwise you'd be saving
    // during an intermediate state.
    // However, it's possible to *complete* the save in the middle of
    // a glue-lookahead when there's a state stored in
    // _stateSnapshotAtLastNewline. This state will have its own patch that
    // is newer than the save patch. We hold off on the final apply until
    // the glue-lookahead is finished. In that case, the apply is always
    // done, it's just that it may apply the looked-ahead changes OR it may
    // simply apply the changes made during the save process to the old
    // _stateSnapshotAtLastNewline state.
    if (_stateSnapshotAtLastNewline == null) _state.applyAnyPatch();

    _asyncSaving = false;
  }

  void _step() {
    var shouldAddToStream = true;

    // Get current content
    var pointer = state.currentPointer;
    if (pointer.isNull) return;

    // Step directly to the first element of content in a container (if
    // necessary)
    var resolved = pointer.resolve();
    var containerToEnter = resolved is Container ? resolved : null;
    while (containerToEnter != null) {
      // Mark container as being entered
      _visitContainer(containerToEnter, atStart: true);

      // No content? the most we can do is step past it
      if (containerToEnter.content.isEmpty) break;

      pointer = Pointer.startOf(containerToEnter);
      resolved = pointer.resolve();
      containerToEnter = resolved is Container ? resolved : null;
    }
    state.currentPointer = pointer;

    _profiler?.step(state.callStack);

    // Is the current content object:
    //  - Normal content
    //  - Or a logic/flow statement - if so, do it
    // Stop flow if we hit a stack pop when we're unable to pop (e.g.
    // return/done statement in knot that was diverted to rather than called
    // as a function)
    InkObject? currentContentObj = pointer.resolve();
    final isLogicOrFlowControl = _performLogicAndFlowControl(currentContentObj);

    // Has flow been forced to end by flow control above?
    if (state.currentPointer.isNull) return;

    if (isLogicOrFlowControl) shouldAddToStream = false;

    // Choice with condition?
    if (currentContentObj is ChoicePoint) {
      final choice = _processChoice(currentContentObj);
      if (choice != null) state.generatedChoices.add(choice);

      currentContentObj = null;
      shouldAddToStream = false;
    }

    // If the container has no content, then it will be
    // the "content" itself, but we skip over it.
    if (currentContentObj is Container) shouldAddToStream = false;

    // Content to add to evaluation stack or the output stream
    if (shouldAddToStream) {
      // If we're pushing a variable pointer onto the evaluation stack,
      // ensure that it's specific to our current (possibly temporary)
      // context index. And make a copy of the pointer so that we're not
      // editing the original runtime object.
      if (currentContentObj is VariablePointerValue &&
          currentContentObj.contextIndex == -1) {
        // Create new object so we're not overwriting the story's own data
        final contextIdx = state.callStack.contextForVariableNamed(
          currentContentObj.variableName,
        );
        currentContentObj = VariablePointerValue(
          currentContentObj.variableName,
          contextIdx,
        );
      }

      // Expression evaluation content
      if (state.inExpressionEvaluation) {
        state.pushEvaluationStack(currentContentObj);
      }
      // Output stream content (i.e. not expression evaluation)
      else if (currentContentObj != null) {
        state.pushToOutputStream(currentContentObj);
      }
    }

    // Increment the content pointer, following diverts if necessary
    _nextContent();

    // Starting a thread should be done after the increment to the content
    // pointer, so that when returning from the thread, it returns to the
    // content after this instruction.
    if (currentContentObj is ControlCommand &&
        currentContentObj.commandType == CommandType.startThread) {
      state.callStack.pushThread();
    }
  }

  // Mark a container as having been visited
  void _visitContainer(Container container, {required bool atStart}) {
    if (!container.countingAtStartOnly || atStart) {
      if (container.visitsShouldBeCounted) {
        state.incrementVisitCountForContainer(container);
      }

      if (container.turnIndexShouldBeCounted) {
        state.recordTurnIndexVisitToContainer(container);
      }
    }
  }

  final List<Container> _prevContainers = [];

  void _visitChangedContainersDueToDivert() {
    final previousPointer = state.previousPointer;
    final pointer = state.currentPointer;

    // Unless we're pointing *directly* at a piece of content, we don't do
    // counting here. Otherwise, the main stepping function will do the
    // counting.
    if (pointer.isNull || pointer.index == -1) return;

    // First, find the previously open set of containers
    _prevContainers.clear();
    if (!previousPointer.isNull) {
      final resolvedPrev = previousPointer.resolve();
      Container? prevAncestor = resolvedPrev is Container
          ? resolvedPrev
          : previousPointer.container;
      while (prevAncestor != null) {
        _prevContainers.add(prevAncestor);
        final p = prevAncestor.parent;
        prevAncestor = p is Container ? p : null;
      }
    }

    // If the new object is a container itself, it will be visited
    // automatically at the next actual content step. However, we need to
    // walk up the new ancestry to see if there are more new containers
    InkObject? currentChildOfContainer = pointer.resolve();

    // Invalid pointer? May happen if attemptingto
    if (currentChildOfContainer == null) return;

    var parent = currentChildOfContainer.parent;
    Container? currentContainerAncestor = parent is Container ? parent : null;
    var allChildrenEnteredAtStart = true;
    while (currentContainerAncestor != null &&
        (!_prevContainers.contains(currentContainerAncestor) ||
            currentContainerAncestor.countingAtStartOnly)) {
      // Check whether this ancestor container is being entered at the start,
      // by checking whether the child object is the first.
      final enteringAtStart =
          currentContainerAncestor.content.isNotEmpty &&
          identical(
            currentChildOfContainer,
            currentContainerAncestor.content[0],
          ) &&
          allChildrenEnteredAtStart;

      // Don't count it as entering at start if we're entering random
      // somewhere within a container B that happens to be nested at index 0
      // of container A. It only counts if we're diverting directly to the
      // first leaf node.
      if (!enteringAtStart) allChildrenEnteredAtStart = false;

      // Mark a visit to this container
      _visitContainer(currentContainerAncestor, atStart: enteringAtStart);

      currentChildOfContainer = currentContainerAncestor;
      parent = currentContainerAncestor.parent;
      currentContainerAncestor = parent is Container ? parent : null;
    }
  }

  String _popChoiceStringAndTags(List<String> tags) {
    final choiceOnlyStrVal = state.popEvaluationStack() as StringValue;

    while (state.evaluationStack.isNotEmpty &&
        state.peekEvaluationStack() is Tag) {
      final tag = state.popEvaluationStack() as Tag;
      tags.insert(0, tag.text); // popped in reverse order
    }

    return choiceOnlyStrVal.value;
  }

  Choice? _processChoice(ChoicePoint choicePoint) {
    var showChoice = true;

    // Don't create choice if choice point doesn't pass conditional
    if (choicePoint.hasCondition) {
      final conditionValue = state.popEvaluationStack();
      if (!_isTruthy(conditionValue)) showChoice = false;
    }

    var startText = '';
    var choiceOnlyText = '';
    final tags = <String>[];

    if (choicePoint.hasChoiceOnlyContent) {
      choiceOnlyText = _popChoiceStringAndTags(tags);
    }

    if (choicePoint.hasStartContent) {
      startText = _popChoiceStringAndTags(tags);
    }

    // Don't create choice if player has already read this content
    if (choicePoint.onceOnly) {
      final visitCount = state.visitCountForContainer(choicePoint.choiceTarget);
      if (visitCount > 0) showChoice = false;
    }

    // We go through the full process of creating the choice above so
    // that we consume the content for it, since otherwise it'll
    // be shown on the output stream.
    if (!showChoice) return null;

    final choice = Choice()
      ..targetPath = choicePoint.pathOnChoice ?? Path()
      ..sourcePath = choicePoint.path.toString()
      ..isInvisibleDefault = choicePoint.isInvisibleDefault
      ..tags = tags.isEmpty ? null : tags;

    // We need to capture the state of the callstack at the point where
    // the choice was generated, since after the generation of this choice
    // we may go on to pop out from a tunnel (possible if the choice was
    // wrapped in a conditional), or we may pop out from a thread,
    // at which point that thread is discarded.
    // Fork clones the thread, gives it a new ID, but without affecting
    // the thread stack itself.
    choice.threadAtGeneration = state.callStack.forkThread();

    // Set final text for the choice
    choice.text = _trimSpacesAndTabs(startText + choiceOnlyText);

    return choice;
  }

  /// C#'s `string.Trim(' ', '\t')`.
  static String _trimSpacesAndTabs(String s) {
    var start = 0;
    var end = s.length;
    while (start < end && (s[start] == ' ' || s[start] == '\t')) {
      start++;
    }
    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t')) {
      end--;
    }
    return s.substring(start, end);
  }

  // Does the expression result represented by this object evaluate to true?
  // e.g. is it a Number that's not equal to 1?
  bool _isTruthy(InkObject obj) {
    const truthy = false;
    if (obj is AbstractValue) {
      if (obj is DivertTargetValue) {
        error(
          "Shouldn't use a divert target (to ${obj.targetPath}) as a "
          "conditional value. Did you intend a function call 'likeThis()' or "
          "a read count check 'likeThis'? (no arrows)",
        );
      }

      return obj.isTruthy;
    }
    return truthy;
  }

  /// Checks whether contentObj is a control or flow object rather than a
  /// piece of content, and performs the required command if necessary.
  /// Returns true if object was logic or flow control, false if it's normal
  /// content.
  bool _performLogicAndFlowControl(InkObject? contentObj) {
    if (contentObj == null) return false;

    // Divert
    if (contentObj is Divert) {
      final currentDivert = contentObj;

      if (currentDivert.isConditional) {
        final conditionValue = state.popEvaluationStack();

        // False conditional? Cancel divert
        if (!_isTruthy(conditionValue)) return true;
      }

      if (currentDivert.hasVariableTarget) {
        final varName = currentDivert.variableDivertName;

        final varContents = state.variablesState.getVariableWithName(varName);

        if (varContents == null) {
          error(
            'Tried to divert using a target from a variable that could not '
            'be found ($varName)',
          );
        } else if (varContents is! DivertTargetValue) {
          var errorMessage =
              'Tried to divert to a target from a variable, but the variable '
              "($varName) didn't contain a divert target, it ";
          if (varContents is IntValue && varContents.value == 0) {
            errorMessage += 'was empty/null (the value 0).';
          } else {
            errorMessage += "contained '$varContents'.";
          }

          error(errorMessage);
        }

        final target = varContents;
        state.divertedPointer = pointerAtPath(target.targetPath);
      } else if (currentDivert.isExternal) {
        _callExternalFunction(
          currentDivert.targetPathString,
          currentDivert.externalArgs,
        );
        return true;
      } else {
        state.divertedPointer = currentDivert.targetPointer;
      }

      if (currentDivert.pushesToStack) {
        state.callStack.push(
          currentDivert.stackPushType,
          outputStreamLengthWithPushed: state.outputStream.length,
        );
      }

      if (state.divertedPointer.isNull && !currentDivert.isExternal) {
        // Human readable name available - runtime divert is part of a
        // hard-written divert that to missing content
        final sourceName = currentDivert.debugMetadata?.sourceName;
        if (sourceName != null) {
          error('Divert target doesn\'t exist: $sourceName');
        } else {
          error('Divert resolution failed: $currentDivert');
        }
      }

      return true;
    }
    // Start/end an expression evaluation? Or print out the result?
    else if (contentObj is ControlCommand) {
      final evalCommand = contentObj;

      switch (evalCommand.commandType) {
        case CommandType.evalStart:
          _assert(
            state.inExpressionEvaluation == false,
            'Already in expression evaluation?',
          );
          state.inExpressionEvaluation = true;

        case CommandType.evalEnd:
          _assert(
            state.inExpressionEvaluation == true,
            'Not in expression evaluation mode',
          );
          state.inExpressionEvaluation = false;

        case CommandType.evalOutput:
          // If the expression turned out to be empty, there may not be
          // anything on the stack
          if (state.evaluationStack.isNotEmpty) {
            final output = state.popEvaluationStack();

            // Functions may evaluate to Void, in which case we skip output
            if (output is! Void) {
              // TODO: Should we really always blanket convert to string?
              // It would be okay to have numbers in the output stream the
              // only problem is when exporting text for viewing, it skips
              // over numbers etc.
              final text = StringValue(output.toString());

              state.pushToOutputStream(text);
            }
          }

        case CommandType.noOp:
          break;

        case CommandType.duplicate:
          state.pushEvaluationStack(state.peekEvaluationStack());

        case CommandType.popEvaluatedValue:
          state.popEvaluationStack();

        case CommandType.popFunction:
        case CommandType.popTunnel:
          final popType = evalCommand.commandType == CommandType.popFunction
              ? PushPopType.function
              : PushPopType.tunnel;

          // Tunnel onwards is allowed to specify an optional override
          // for where to go next, rather than just returning.
          DivertTargetValue? overrideTunnelReturnTarget;
          if (popType == PushPopType.tunnel) {
            final popped = state.popEvaluationStack();
            overrideTunnelReturnTarget = popped is DivertTargetValue
                ? popped
                : null;
            if (overrideTunnelReturnTarget == null) {
              _assert(
                popped is Void,
                "Expected void if ->-> doesn't override target",
              );
            }
          }

          if (state.tryExitFunctionEvaluationFromGame()) {
            break;
          } else if (state.callStack.currentElement.type != popType ||
              !state.callStack.canPop) {
            const names = {
              PushPopType.function: 'function return statement (~ return)',
              PushPopType.tunnel: 'tunnel onwards statement (->->)',
            };

            var expected = names[state.callStack.currentElement.type];
            if (expected == null) {
              throw SystemException(
                "The given key '${state.callStack.currentElement.type.csName}' "
                'was not present in the dictionary.',
              );
            }
            if (!state.callStack.canPop) {
              expected = 'end of flow (-> END or choice)';
            }

            final errorMsg = 'Found ${names[popType]}, when expected $expected';

            error(errorMsg);
          } else {
            state.popCallstack();

            // Does tunnel onwards override by diverting to a new ->->
            // target?
            if (overrideTunnelReturnTarget != null) {
              state.divertedPointer = pointerAtPath(
                overrideTunnelReturnTarget.targetPath,
              );
            }
          }

        case CommandType.beginString:
          state.pushToOutputStream(evalCommand);

          _assert(
            state.inExpressionEvaluation == true,
            'Expected to be in an expression when evaluating a string',
          );
          state.inExpressionEvaluation = false;

        // Leave it to story.currentText and story.currentTags to sort out
        // the text from the tags. This is mostly because we can't always
        // rely on the existence of EndTag, and we don't want to try and
        // flatten dynamic tags to strings every time \n is pushed to output
        case CommandType.beginTag:
          state.pushToOutputStream(evalCommand);

        case CommandType.endTag:
          // EndTag has 2 modes:
          //  - When in string evaluation (for choices)
          //  - Normal
          //
          // The only way you could have an EndTag in the middle of
          // string evaluation is if we're currently generating text for a
          // choice, such as:
          //
          //   + choice # tag
          //
          // In the above case, the ink will be run twice:
          //  - First, to generate the choice text. String evaluation
          //    will be on, and the final string will be pushed to the
          //    evaluation stack, ready to be popped to make a Choice
          //    object.
          //  - Second, when ink generates text after choosing the choice.
          //    On this ocassion, it's not in string evaluation mode.
          //
          // On the writing side, we disallow manually putting tags within
          // strings like this:
          //
          //   {"hello # world"}
          //
          // So we know that the tag must be being generated as part of
          // choice content. Therefore, when the tag has been generated,
          // we push it onto the evaluation stack in the exact same way
          // as the string for the choice content.
          if (state.inStringEvaluation) {
            final contentStackForTag = <InkObject>[];
            var outputCountConsumed = 0;

            for (var i = state.outputStream.length - 1; i >= 0; --i) {
              final obj = state.outputStream[i];

              outputCountConsumed++;

              if (obj is ControlCommand) {
                if (obj.commandType == CommandType.beginTag) {
                  break;
                } else {
                  error(
                    'Unexpected ControlCommand while extracting tag from '
                    'choice',
                  );
                }
              }

              if (obj is StringValue) contentStackForTag.add(obj);
            }

            // Consume the content that was produced for this string
            state.popFromOutputStream(outputCountConsumed);

            final sb = StringBuffer();
            for (final strVal in contentStackForTag.reversed) {
              sb.write((strVal as StringValue).value);
            }

            final choiceTag = Tag(state.cleanOutputWhitespace(sb.toString()));
            // Pushing to the evaluation stack means it gets picked up
            // when a Choice is generated from the next Choice Point.
            state.pushEvaluationStack(choiceTag);
          }
          // Otherwise! Simply push EndTag, so that in the output stream we
          // have a structure of: [BeginTag, "the tag content", EndTag]
          else {
            state.pushToOutputStream(evalCommand);
          }

        // Dynamic strings and tags are built in the same way
        case CommandType.endString:
          // Since we're iterating backward through the content,
          // build a stack so that when we build the string,
          // it's in the right order
          final contentStackForString = <InkObject>[];
          final contentToRetain = <InkObject>[];

          var outputCountConsumed = 0;
          for (var i = state.outputStream.length - 1; i >= 0; --i) {
            final obj = state.outputStream[i];

            outputCountConsumed++;

            if (obj is ControlCommand &&
                obj.commandType == CommandType.beginString) {
              break;
            }
            if (obj is Tag) contentToRetain.add(obj);
            if (obj is StringValue) contentStackForString.add(obj);
          }

          // Consume the content that was produced for this string
          state.popFromOutputStream(outputCountConsumed);

          // Rescue the tags that we want actually to keep on the output
          // stack rather than consume as part of the string we're building.
          // At the time of writing, this only applies to Tag objects
          // generated by choices, which are pushed to the stack during
          // string generation.
          for (final rescuedTag in contentToRetain.reversed) {
            state.pushToOutputStream(rescuedTag);
          }

          // Build string out of the content we collected
          final sb = StringBuffer();
          for (final c in contentStackForString.reversed) {
            sb.write(c.toString());
          }

          // Return to expression evaluation (from content mode)
          state.inExpressionEvaluation = true;
          state.pushEvaluationStack(StringValue(sb.toString()));

        case CommandType.choiceCount:
          final choiceCount = state.generatedChoices.length;
          state.pushEvaluationStack(IntValue(choiceCount));

        case CommandType.turns:
          state.pushEvaluationStack(IntValue(state.currentTurnIndex + 1));

        case CommandType.turnsSince:
        case CommandType.readCount:
          final target = state.popEvaluationStack();
          if (target is! DivertTargetValue) {
            var extraNote = '';
            if (target is IntValue) {
              extraNote =
                  ". Did you accidentally pass a read count ('knot_name') "
                  "instead of a target ('-> knot_name')?";
            }
            error(
              'TURNS_SINCE expected a divert target (knot, stitch, label '
              'name), but saw $target$extraNote',
            );
          }

          final divertTarget = target;
          final correctObj = contentAtPath(divertTarget.targetPath).correctObj;
          final container = correctObj is Container ? correctObj : null;

          int eitherCount;
          if (container != null) {
            if (evalCommand.commandType == CommandType.turnsSince) {
              eitherCount = state.turnsSinceForContainer(container);
            } else {
              eitherCount = state.visitCountForContainer(container);
            }
          } else {
            if (evalCommand.commandType == CommandType.turnsSince) {
              eitherCount = -1; // turn count, default to never/unknown
            } else {
              // visit count, assume 0 to default to allowing entry
              eitherCount = 0;
            }

            warning(
              'Failed to find container for $evalCommand lookup at '
              '${divertTarget.targetPath}',
            );
          }

          state.pushEvaluationStack(IntValue(eitherCount));

        case CommandType.random:
          final maxInt = _asIntValue(state.popEvaluationStack());
          final minInt = _asIntValue(state.popEvaluationStack());

          if (minInt == null) {
            error('Invalid value for minimum parameter of RANDOM(min, max)');
          }

          if (maxInt == null) {
            error('Invalid value for maximum parameter of RANDOM(min, max)');
          }

          // +1 because it's inclusive of min and max, for e.g. RANDOM(1,6)
          // for a dice roll.
          var randomRange = maxInt.value - minInt.value + 1;
          if (randomRange > 0x7fffffff || randomRange < -0x80000000) {
            randomRange = 0x7fffffff;
            error(
              'RANDOM was called with a range that exceeds the size that ink '
              'numbers can use.',
            );
          }
          if (randomRange <= 0) {
            error(
              'RANDOM was called with minimum as ${minInt.value} and maximum '
              'as ${maxInt.value}. The maximum must be larger',
            );
          }

          final resultSeed = (state.storySeed + state.previousRandom).toSigned(
            32,
          );
          final random = PRNG(resultSeed);

          final nextRandom = random.next();
          final chosenValue = ((nextRandom % randomRange) + minInt.value)
              .toSigned(32);
          state.pushEvaluationStack(IntValue(chosenValue));

          // Next random number (rather than keeping the Random object around)
          state.previousRandom = nextRandom;

        case CommandType.seedRandom:
          final seed = _asIntValue(state.popEvaluationStack());
          if (seed == null) error('Invalid value passed to SEED_RANDOM');

          // Story seed affects both RANDOM and shuffle behaviour
          state.storySeed = seed.value;
          state.previousRandom = 0;

          // SEED_RANDOM returns nothing.
          state.pushEvaluationStack(Void());

        case CommandType.visitIndex:
          final count =
              state.visitCountForContainer(state.currentPointer.container) -
              1; // index not count
          state.pushEvaluationStack(IntValue(count));

        case CommandType.sequenceShuffleIndex:
          final shuffleIndex = _nextSequenceShuffleIndex();
          state.pushEvaluationStack(IntValue(shuffleIndex));

        case CommandType.startThread:
          // Handled in main step function
          break;

        case CommandType.done:
          // We may exist in the context of the initial
          // act of creating the thread, or in the context of
          // evaluating the content.
          if (state.callStack.canPopThread) {
            state.callStack.popThread();
          }
          // In normal flow - allow safe exit without warning
          else {
            state.didSafeExit = true;

            // Stop flow in current thread
            state.currentPointer = Pointer.nullPointer;
          }

        // Force flow to end completely
        case CommandType.end:
          state.forceEnd();

        case CommandType.listFromInt:
          final intVal = _asIntValue(state.popEvaluationStack());
          final listNameValObj = state.popEvaluationStack();
          final listNameVal = listNameValObj is StringValue
              ? listNameValObj
              : null;

          if (intVal == null) {
            throw StoryException(
              'Passed non-integer when creating a list element from a '
              'numerical value.',
            );
          }

          ListValue? generatedListValue;

          final foundListDef = listDefinitions?.tryListGetDefinition(
            listNameVal?.value,
          );
          if (foundListDef != null) {
            final foundItem = foundListDef.tryGetItemWithValue(intVal.value);
            if (foundItem != null) {
              generatedListValue = ListValue.single(foundItem, intVal.value);
            }
          } else {
            throw StoryException(
              'Failed to find LIST called ${listNameVal?.value}',
            );
          }

          generatedListValue ??= ListValue();

          state.pushEvaluationStack(generatedListValue);

        case CommandType.listRange:
          final max = state.popEvaluationStack();
          final min = state.popEvaluationStack();
          final targetList = state.popEvaluationStack();

          if (targetList is! ListValue ||
              min is! AbstractValue ||
              max is! AbstractValue) {
            throw StoryException(
              'Expected list, minimum and maximum for LIST_RANGE',
            );
          }

          final result = targetList.value.listWithSubRange(
            min.valueObject,
            max.valueObject,
          );

          state.pushEvaluationStack(ListValue.fromList(result));

        case CommandType.listRandom:
          final listVal = state.popEvaluationStack();
          if (listVal is! ListValue) {
            throw StoryException('Expected list for LIST_RANDOM');
          }

          final list = listVal.value;

          InkList newList;

          // List was empty: return empty list
          if (list.count == 0) {
            newList = InkList();
          }
          // Non-empty source list
          else {
            // Generate a random index for the element to take
            final resultSeed = (state.storySeed + state.previousRandom)
                .toSigned(32);
            final random = PRNG(resultSeed);

            final nextRandom = random.next();
            final listItemIndex = nextRandom % list.count;

            // Iterate through to get the random element
            final randomItem = list.entries.elementAt(listItemIndex);

            // Origin list is simply the origin of the one element
            newList = InkList.withOrigin(randomItem.key.originName ?? '', this);
            newList.add(randomItem.key, randomItem.value);

            state.previousRandom = nextRandom;
          }

          state.pushEvaluationStack(ListValue.fromList(newList));

        case CommandType.notSet:
          error('unhandled ControlCommand: $evalCommand');
      }

      return true;
    }
    // Variable assignment
    else if (contentObj is VariableAssignment) {
      final varAss = contentObj;
      final assignedVal = state.popEvaluationStack();

      // When in temporary evaluation, don't create new variables purely
      // within the temporary context, but attempt to create them globally
      //var prioritiseHigherInCallStack = _temporaryEvaluationContainer != null;

      state.variablesState.assign(varAss, assignedVal);

      return true;
    }
    // Variable reference
    else if (contentObj is VariableReference) {
      final varRef = contentObj;
      InkObject? foundValue;

      // Explicit read count value
      if (varRef.pathForCount != null) {
        final container = varRef.containerForCount;
        final count = state.visitCountForContainer(container);
        foundValue = IntValue(count);
      }
      // Normal variable reference
      else {
        foundValue = state.variablesState.getVariableWithName(varRef.name);

        if (foundValue == null) {
          warning(
            "Variable not found: '${varRef.name}'. Using default value of 0 "
            '(false). This can happen with temporary variables if the '
            "declaration hasn't yet been hit. Globals are always given a "
            "default value on load if a value doesn't exist in the save "
            'state.',
          );
          foundValue = IntValue(0);
        }
      }

      state.pushEvaluationStack(foundValue);

      return true;
    }
    // Native function call
    else if (contentObj is NativeFunctionCall) {
      final func = contentObj;
      final funcParams = state.popEvaluationStackCount(func.numberOfParameters);
      final result = func.call(funcParams);
      state.pushEvaluationStack(result);
      return true;
    }

    // No control content, must be ordinary content
    return false;
  }

  static IntValue? _asIntValue(InkObject obj) => obj is IntValue ? obj : null;

  /// Change the current position of the story to the given path. From here
  /// you can call Continue() to evaluate the next line.
  ///
  /// The path string is a dot-separated path as used internally by the
  /// engine. These examples should work:
  ///
  ///     myKnot
  ///     myKnot.myStitch
  ///
  /// Note however that this won't necessarily work:
  ///
  ///     myKnot.myStitch.myLabelledChoice
  ///
  /// ...because of the way that content is nested within a weave structure.
  ///
  /// By default this will reset the callstack beforehand, which means that
  /// any tunnels, threads or functions you were in at the time of calling
  /// will be discarded. This is different from the behaviour of
  /// ChooseChoiceIndex, which will always keep the callstack, since the
  /// choices are known to come from the correct state, and known their
  /// source thread.
  ///
  /// You have the option of passing false to the resetCallstack parameter
  /// if you don't want this behaviour, and will leave any active threads,
  /// tunnels or function calls in-tact.
  ///
  /// This is potentially dangerous! If you're in the middle of a tunnel,
  /// it'll redirect only the inner-most tunnel, meaning that when you
  /// tunnel-return using '->->', it'll return to where you were before.
  /// This may be what you want though. However, if you're in the middle of
  /// a function, ChoosePathString will throw an exception.
  void choosePathString(
    String path, {
    bool resetCallstack = true,
    List<Object?>? arguments,
  }) {
    _ifAsyncWeCant('call ChoosePathString right now');
    onChoosePathString?.call(path, arguments);
    if (resetCallstack) {
      this.resetCallstack();
    } else {
      // ChoosePathString is potentially dangerous since you can call it when
      // the stack is pretty much in any state. Let's catch one of the worst
      // offenders.
      if (state.callStack.currentElement.type == PushPopType.function) {
        var funcDetail = '';
        final container =
            state.callStack.currentElement.currentPointer.container;
        if (container != null) funcDetail = '(${container.path}) ';
        throw SystemException(
          'Story was running a function ${funcDetail}when you called '
          'ChoosePathString($path) - this is almost certainly not not what '
          'you want! Full stack trace: \n${state.callStack.callStackTrace}',
        );
      }
    }

    state.passArgumentsToEvaluationStack(arguments);
    choosePath(Path.fromString(path));
  }

  void _ifAsyncWeCant(String activityStr) {
    if (_asyncContinueActive) {
      throw SystemException(
        "Can't $activityStr. Story is in the middle of a ContinueAsync(). "
        'Make more ContinueAsync() calls or a single Continue() call '
        'beforehand.',
      );
    }
  }

  /// Moves the story to [p], counting visits to the containers entered.
  void choosePath(Path p, {bool incrementingTurnIndex = true}) {
    state.setChosenPath(p, incrementingTurnIndex: incrementingTurnIndex);

    // Take a note of newly visited containers for read counts etc
    _visitChangedContainersDueToDivert();
  }

  /// Chooses the Choice from the currentChoices list with the given
  /// index. Internally, this sets the current content path to that
  /// pointed to by the Choice, ready to continue story evaluation.
  void chooseChoiceIndex(int choiceIdx) {
    final choices = currentChoices;
    _assert(
      choiceIdx >= 0 && choiceIdx < choices.length,
      'choice out of range',
    );

    // Replace callstack with the one from the thread at the choosing point,
    // so that we can jump into the right place in the flow.
    // This is important in case the flow was forked by a new thread, which
    // can create multiple leading edges for the story, each of
    // which has its own context.
    final choiceToChoose = choices[choiceIdx];
    onMakeChoice?.call(choiceToChoose);
    final thread = choiceToChoose.threadAtGeneration;
    if (thread != null) state.callStack.currentThread = thread;

    choosePath(choiceToChoose.targetPath);
  }

  /// Checks if a function exists.
  bool hasFunction(String functionName) {
    try {
      return knotContainerWithName(functionName) != null;
    } catch (_) {
      return false;
    }
  }

  /// Evaluates a function defined in ink, and gathers the possibly
  /// multi-line text as generated by the function.
  /// This text output is any text written as normal content within the
  /// function, as opposed to the return value, which is returned as .NET
  /// object.
  ({Object? result, String textOutput}) evaluateFunctionWithOutput(
    String? functionName, [
    List<Object?>? arguments,
  ]) {
    onEvaluateFunction?.call(functionName ?? '', arguments);
    _ifAsyncWeCant('evaluate a function');

    if (functionName == null) {
      throw SystemException('Function is null');
    } else if (functionName.isEmpty || functionName.trim().isEmpty) {
      throw SystemException('Function is empty or white space.');
    }

    // Get the content that we need to run
    final funcContainer = knotContainerWithName(functionName);
    if (funcContainer == null) {
      throw SystemException("Function doesn't exist: '$functionName'");
    }

    // Snapshot the output stream
    final outputStreamBefore = [...state.outputStream];
    _state.resetOutput();

    // State will temporarily replace the callstack in order to evaluate
    state.startFunctionEvaluationFromGame(funcContainer, arguments);

    // Evaluate the function, and collect the string output
    final stringOutput = StringBuffer();
    while (canContinue) {
      stringOutput.write(continueStory());
    }
    final textOutput = stringOutput.toString();

    // Restore the output stream in case this was called
    // during main story evaluation.
    _state.resetOutput(outputStreamBefore);

    // Finish evaluation, and see whether anything was produced
    final result = state.completeFunctionEvaluationFromGame();
    onCompleteEvaluateFunction?.call(
      functionName,
      arguments,
      textOutput,
      result,
    );
    return (result: result, textOutput: textOutput);
  }

  /// Evaluates a function defined in ink, returning its return value.
  Object? evaluateFunction(String? functionName, [List<Object?>? arguments]) =>
      evaluateFunctionWithOutput(functionName, arguments).result;

  // Evaluate a "hot compiled" piece of ink content, as used by the REPL-like
  // CommandLinePlayer.
  /// Evaluates a compiled expression container and returns its value, or
  /// null. Used by development tools.
  InkObject? evaluateExpression(Container exprContainer) {
    final startCallStackHeight = state.callStack.elements.length;

    state.callStack.push(PushPopType.tunnel);

    _temporaryEvaluationContainer = exprContainer;

    state.goToStart();

    final evalStackHeight = state.evaluationStack.length;

    continueStory();

    _temporaryEvaluationContainer = null;

    // Should have fallen off the end of the Container, which should
    // have auto-popped, but just in case we didn't for some reason,
    // manually pop to restore the state (including currentPath).
    if (state.callStack.elements.length > startCallStackHeight) {
      state.popCallstack();
    }

    final endStackHeight = state.evaluationStack.length;
    if (endStackHeight > evalStackHeight) {
      return state.popEvaluationStack();
    } else {
      return null;
    }
  }

  /// An ink file can provide a fallback functions for when when an EXTERNAL
  /// has been left unbound by the client, and the fallback function will be
  /// called instead. Useful when testing a story in playmode, when it's not
  /// possible to write a client-side C# external function, but you don't
  /// want it to fail to run.
  bool allowExternalFunctionFallbacks = false;

  /// The reference's `TryGetExternalFunction`; null when unbound.
  ExternalFunction? tryGetExternalFunction(String functionName) =>
      _externals[functionName]?.function;

  void _callExternalFunction(String? funcName, int numberOfArguments) {
    Container? fallbackFunctionContainer;

    final funcDef = _externals[funcName];

    // Should this function break glue? Abort run if we've already seen a
    // newline. Set a bool to tell it to restore the snapshot at the end of
    // this instruction.
    if (funcDef != null && !funcDef.lookaheadSafe && state.inStringEvaluation) {
      // 16th Jan 2023: Example ink that was failing:
      //
      //   A line above
      //   ~ temp text = "{theFunc()}"
      //   {text}
      //
      //   === function theFunc()
      //       { external():
      //           Boom
      //       }
      //
      //   EXTERNAL external()
      //
      // What was happening: The external() call would exit out early due to
      // _stateSnapshotAtLastNewline having a value, leaving the evaluation
      // stack without a return value on it. When the if-statement tried to
      // pop a value, the evaluation stack would be empty, and there would be
      // an exception.
      //
      // The snapshot rewinding code is only designed to work when outside
      // of string generation code (there's a check for that in the
      // snapshotting code), so the easiest thing to do was to exclude
      // external function calls from the snapshotting code for now.
      error(
        'External function $funcName could not be called because 1) it '
        "wasn't marked as lookaheadSafe when BindExternalFunction was called "
        'and 2) the story is in the middle of string generation, either '
        'because choice text is being generated, or because you have ink '
        'like "hello {func()}". You can work around this by generating the '
        'result of your function into a temporary variable before the string '
        'or choice gets generated: ~ temp x = $funcName()',
      );
    }

    if (funcDef != null &&
        !funcDef.lookaheadSafe &&
        _stateSnapshotAtLastNewline != null) {
      _sawLookaheadUnsafeFunctionAfterNewline = true;
      return;
    }

    // Try to use fallback function?
    if (funcDef == null) {
      if (allowExternalFunctionFallbacks) {
        fallbackFunctionContainer = knotContainerWithName(funcName ?? '');
        _assert(
          fallbackFunctionContainer != null,
          "Trying to call EXTERNAL function '$funcName' which has not been "
          'bound, and fallback ink function could not be found.',
        );

        // Divert direct into fallback function and we're done
        state.callStack.push(
          PushPopType.function,
          outputStreamLengthWithPushed: state.outputStream.length,
        );
        state.divertedPointer = Pointer.startOf(fallbackFunctionContainer);
        return;
      } else {
        _assert(
          false,
          "Trying to call EXTERNAL function '$funcName' which has not been "
          'bound (and ink fallbacks disabled).',
        );
        return;
      }
    }

    // Pop arguments
    final arguments = <Object?>[];
    for (var i = 0; i < numberOfArguments; ++i) {
      final poppedObj = state.popEvaluationStack() as AbstractValue;
      final valueObj = poppedObj.valueObject;
      arguments.add(valueObj);
    }

    // Reverse arguments from the order they were popped,
    // so they're the right way round again.
    final args = arguments.reversed.toList();

    // Run the function!
    final funcResult = funcDef.function(args);

    // Convert return value (if any) to the a type that the ink engine can
    // use
    InkObject? returnObj;
    if (funcResult != null) {
      returnObj = AbstractValue.create(funcResult);
      _assert(
        returnObj != null,
        'Could not create ink value from returned object of type '
        '${funcResult.runtimeType}',
      );
    } else {
      returnObj = Void();
    }

    state.pushEvaluationStack(returnObj);
  }

  /// Most general form of function binding: [func] receives the ink
  /// arguments unconverted (`int`, `double`, `String`, `bool`, [InkList]).
  /// Unlike the typed forms, [lookaheadSafe] defaults to `true`, as in the
  /// reference.
  void bindExternalFunctionGeneral(
    String funcName,
    ExternalFunction func, {
    bool lookaheadSafe = true,
  }) {
    _ifAsyncWeCant('bind an external function');
    _assert(
      !_externals.containsKey(funcName),
      "Function '$funcName' has already been bound.",
    );
    _externals[funcName] = _ExternalFunctionDef(func, lookaheadSafe);
  }

  /// Converts an argument from ink to [T], as the reference's `TryCoerce`:
  /// a float rounds to the nearest int (halves to even), an int becomes a
  /// float or a bool, a bool becomes 1 or 0, and anything becomes a string.
  T _tryCoerce<T>(Object? value) {
    if (value == null) return null as T;

    if (value is T) return value as T;

    if (value is double && T == int) {
      return _roundHalfToEven(value) as T;
    }

    if (value is int && T == double) {
      return toFloat32(value.toDouble()) as T;
    }

    if (value is int && T == bool) return (value != 0) as T;

    if (value is bool && T == int) return (value ? 1 : 0) as T;

    if (T == String) return csObjectToString(value) as T;

    _assert(
      false,
      'Failed to cast ${_csTypeName(value.runtimeType)} to ${_csTypeName(T)}',
    );
    throw StateError('unreachable');
  }

  /// C#'s `(int)Math.Round(f)`: nearest, halves to even.
  static int _roundHalfToEven(double f) {
    final floor = f.floorToDouble();
    final diff = f - floor;
    double r;
    if (diff > 0.5) {
      r = floor + 1;
    } else if (diff < 0.5) {
      r = floor;
    } else {
      r = floor % 2 == 0 ? floor : floor + 1;
    }
    return floatToInt32(r);
  }

  /// The .NET type name the reference prints in cast errors.
  static String _csTypeName(Type t) => switch (t) {
    const (int) => 'Int32',
    const (double) => 'Single',
    const (bool) => 'Boolean',
    const (String) => 'String',
    const (InkList) => 'InkList',
    _ => t.toString(),
  };

  // lookaheadSafe: The ink engine often evaluates further than you might
  // expect beyond the current line just in case it sees glue that will
  // cause the two lines to become one. In this case it's possible that a
  // function can appear to be called twice instead of just once, and
  // earlier than you expect. If it's safe for your function to be called
  // in this way (since the result and side effect of the function will not
  // change), then you can pass 'true'. Usually, you want to pass 'false',
  // especially if you want some action to be performed in game code when
  // this function is called.

  /// Bind a Dart function with no arguments to an ink EXTERNAL function
  /// declaration. A function that returns nothing (or null) returns nothing
  /// to ink; an `int`, `double`, `String`, `bool` or [InkList] goes back as
  /// that ink value. The return type is `dynamic` so that `void` functions
  /// bind as they are.
  ///
  /// Pass [lookaheadSafe] `true` only if the function may run early or more
  /// than once: the engine evaluates past the current line to look for
  /// glue.
  void bindExternalFunction0(
    String funcName,
    dynamic Function() func, {
    bool lookaheadSafe = false,
  }) {
    bindExternalFunctionGeneral(funcName, (args) {
      _assert(args.isEmpty, 'External function expected no arguments');
      return func();
    }, lookaheadSafe: lookaheadSafe);
  }

  /// Bind a one-argument Dart function to an ink EXTERNAL function. The
  /// argument is converted to [T1] first (see [bindExternalFunction0] for
  /// return values and [lookaheadSafe]):
  ///
  ///     story.bindExternalFunction1<int>('roll', (sides) => rng.nextInt(sides) + 1);
  ///
  /// A float passed to an `int` parameter rounds to the nearest int, halves
  /// to even; an int passed to `double` or `bool` converts; a `bool` passed
  /// to `int` is 1 or 0; any value passed to `String` is its text.
  void bindExternalFunction1<T1>(
    String funcName,
    dynamic Function(T1) func, {
    bool lookaheadSafe = false,
  }) {
    bindExternalFunctionGeneral(funcName, (args) {
      _assert(args.length == 1, 'External function expected one argument');
      return func(_tryCoerce<T1>(args[0]));
    }, lookaheadSafe: lookaheadSafe);
  }

  /// Bind a two-argument Dart function to an ink EXTERNAL function; see
  /// [bindExternalFunction1].
  void bindExternalFunction2<T1, T2>(
    String funcName,
    dynamic Function(T1, T2) func, {
    bool lookaheadSafe = false,
  }) {
    bindExternalFunctionGeneral(funcName, (args) {
      _assert(args.length == 2, 'External function expected two arguments');
      return func(_tryCoerce<T1>(args[0]), _tryCoerce<T2>(args[1]));
    }, lookaheadSafe: lookaheadSafe);
  }

  /// Bind a three-argument Dart function to an ink EXTERNAL function; see
  /// [bindExternalFunction1].
  void bindExternalFunction3<T1, T2, T3>(
    String funcName,
    dynamic Function(T1, T2, T3) func, {
    bool lookaheadSafe = false,
  }) {
    bindExternalFunctionGeneral(funcName, (args) {
      _assert(args.length == 3, 'External function expected three arguments');
      return func(
        _tryCoerce<T1>(args[0]),
        _tryCoerce<T2>(args[1]),
        _tryCoerce<T3>(args[2]),
      );
    }, lookaheadSafe: lookaheadSafe);
  }

  /// Bind a four-argument Dart function to an ink EXTERNAL function; see
  /// [bindExternalFunction1].
  void bindExternalFunction4<T1, T2, T3, T4>(
    String funcName,
    dynamic Function(T1, T2, T3, T4) func, {
    bool lookaheadSafe = false,
  }) {
    bindExternalFunctionGeneral(funcName, (args) {
      _assert(args.length == 4, 'External function expected four arguments');
      return func(
        _tryCoerce<T1>(args[0]),
        _tryCoerce<T2>(args[1]),
        _tryCoerce<T3>(args[2]),
        _tryCoerce<T4>(args[3]),
      );
    }, lookaheadSafe: lookaheadSafe);
  }

  /// Remove a binding for a named EXTERNAL ink function.
  void unbindExternalFunction(String funcName) {
    _ifAsyncWeCant('unbind an external a function');
    _assert(
      _externals.containsKey(funcName),
      "Function '$funcName' has not been bound.",
    );
    _externals.remove(funcName);
  }

  /// Check that all EXTERNAL ink functions have a valid bound C# function.
  /// Note that this is automatically called on the first call to Continue().
  void validateExternalBindings() {
    final missingExternals = <String>{};

    _validateExternalBindingsIn(_root, missingExternals);
    _hasValidatedExternals = true;

    // No problem! Validation complete
    if (missingExternals.isEmpty) {
      _hasValidatedExternals = true;
    }
    // Error for all missing externals
    else {
      final message =
          'ERROR: Missing function binding for external'
          "${missingExternals.length > 1 ? 's' : ''}: "
          "'${missingExternals.join("', '")}' "
          '${allowExternalFunctionFallbacks ? ', and no fallback ink function found.' : ' (ink fallbacks disabled)'}';

      error(message);
    }
  }

  void _validateExternalBindingsIn(Container c, Set<String> missingExternals) {
    for (final innerContent in c.content) {
      if (innerContent is! Container || !innerContent.hasValidName) {
        _validateExternalBindingsOf(innerContent, missingExternals);
      }
    }
    for (final innerKeyValue in c.namedContent.values) {
      _validateExternalBindingsOf(innerKeyValue as InkObject, missingExternals);
    }
  }

  void _validateExternalBindingsOf(InkObject o, Set<String> missingExternals) {
    if (o is Container) {
      _validateExternalBindingsIn(o, missingExternals);
      return;
    }

    if (o is Divert && o.isExternal) {
      final name = o.targetPathString ?? '';

      if (!_externals.containsKey(name)) {
        if (allowExternalFunctionFallbacks) {
          final fallbackFound = mainContentContainer.namedContent.containsKey(
            name,
          );
          if (!fallbackFound) missingExternals.add(name);
        } else {
          missingExternals.add(name);
        }
      }
    }
  }

  /// When the named global variable changes it's value, the observer will
  /// be called to notify it of the change. Note that if the value changes
  /// multiple times within the ink, the observer will only be called once,
  /// at the end of the ink's evaluation. If, during the evaluation, it
  /// changes and then changes back again to its original value, it will
  /// still be called. Note that the observer will also be fired if the
  /// value of the variable is changed externally to the ink, by directly
  /// setting a value in story.variablesState.
  void observeVariable(String variableName, VariableObserver observer) {
    _ifAsyncWeCant('observe a new variable');

    final observers = _variableObservers ??= {};

    if (!state.variablesState.globalVariableExistsWithName(variableName)) {
      throw SystemException(
        "Cannot observe variable '$variableName' because it wasn't declared "
        'in the ink story.',
      );
    }

    (observers[variableName] ??= []).add(observer);
  }

  /// Convenience function to allow multiple variables to be observed with
  /// the same observer delegate function. See the singular ObserveVariable
  /// for details. The observer will get one call for every variable that
  /// has changed.
  void observeVariables(List<String> variableNames, VariableObserver observer) {
    for (final varName in variableNames) {
      observeVariable(varName, observer);
    }
  }

  /// Removes the variable observer, to stop getting variable change
  /// notifications. If you pass a specific variable name, it will stop
  /// observing that particular one. If you pass null (or leave it blank,
  /// since it's optional), then the observer will be removed from all
  /// variables that it's subscribed to. If you pass in a specific variable
  /// name and null for the the observer, all observers for that variable
  /// will be removed.
  void removeVariableObserver({
    VariableObserver? observer,
    String? specificVariableName,
  }) {
    _ifAsyncWeCant('remove a variable observer');

    final observers = _variableObservers;
    if (observers == null) return;

    // Remove observer for this specific variable
    if (specificVariableName != null) {
      final list = observers[specificVariableName];
      if (list != null) {
        if (observer != null) {
          _removeLastOccurrence(list, observer);
          if (list.isEmpty) observers.remove(specificVariableName);
        } else {
          observers.remove(specificVariableName);
        }
      }
    }
    // Remove observer for all variables
    else if (observer != null) {
      for (final varName in [...observers.keys]) {
        final list = observers[varName];
        if (list == null) continue;
        _removeLastOccurrence(list, observer);
        if (list.isEmpty) observers.remove(varName);
      }
    }
  }

  /// C# delegate subtraction removes the last matching invocation.
  static void _removeLastOccurrence(
    List<VariableObserver> list,
    VariableObserver observer,
  ) {
    final i = list.lastIndexOf(observer);
    if (i >= 0) list.removeAt(i);
  }

  void _variableStateDidChangeEvent(
    String variableName,
    InkObject newValueObj,
  ) {
    final observers = _variableObservers?[variableName];
    if (observers == null) return;

    if (newValueObj is! AbstractValue) {
      throw SystemException(
        "Tried to get the value of a variable that isn't a standard type",
      );
    }

    for (final observer in [...observers]) {
      observer(variableName, newValueObj.valueObject);
    }
  }

  /// Get any global tags associated with the story. These are defined as
  /// hash tags defined at the very top of the story.
  List<String>? get globalTags => _tagsAtStartOfFlowContainerWithPathString('');

  /// Gets any tags associated with a particular knot or knot.stitch.
  /// These are defined as hash tags defined at the very top of a
  /// knot or stitch.
  List<String>? tagsForContentAtPath(String path) =>
      _tagsAtStartOfFlowContainerWithPathString(path);

  List<String>? _tagsAtStartOfFlowContainerWithPathString(String pathString) {
    final path = Path.fromString(pathString);

    // Expected to be global story, knot or stitch
    final found = contentAtPath(path).container;
    if (found == null) {
      throw SystemException(
        'Object reference not set to an instance of an object.',
      );
    }
    var flowContainer = found;
    while (true) {
      final firstContent = flowContainer.content[0];
      if (firstContent is Container) {
        flowContainer = firstContent;
      } else {
        break;
      }
    }

    // Any initial tag objects count as the "main tags" associated with that
    // story/knot/stitch
    var inTag = false;
    List<String>? tags;
    for (final c in flowContainer.content) {
      if (c is ControlCommand) {
        if (c.commandType == CommandType.beginTag) {
          inTag = true;
        } else if (c.commandType == CommandType.endTag) {
          inTag = false;
        }
      } else if (inTag) {
        if (c is StringValue) {
          (tags ??= []).add(c.value);
        } else {
          error(
            'Tag contained non-text content. Only plain text is allowed when '
            'using globalTags or TagsAtContentPath. If you want to evaluate '
            'dynamic content, you need to use story.Continue().',
          );
        }
      }
      // Any other content - we're done
      // We only recognise initial text-only tags
      else {
        break;
      }
    }

    return tags;
  }

  /// Useful when debugging a (very short) story, to visualise the state of
  /// the story. Add this call as a watch and open the extended text. A left
  /// arrow mark will denote the current point of the story.
  /// It's only recommended that this is used on very short debug stories,
  /// since it can end up generate a large quantity of text otherwise.
  String buildStringOfHierarchy() {
    final sb = StringBuffer();

    mainContentContainer.buildStringOfHierarchy(
      sb,
      0,
      state.currentPointer.resolve(),
    );

    return sb.toString();
  }

  void _nextContent() {
    // Setting previousContentObject is critical for
    // VisitChangedContainersDueToDivert
    state.previousPointer = state.currentPointer;

    // Divert step?
    if (!state.divertedPointer.isNull) {
      state.currentPointer = state.divertedPointer;
      state.divertedPointer = Pointer.nullPointer;

      // Internally uses state.previousContentObject and
      // state.currentContentObject
      _visitChangedContainersDueToDivert();

      // Diverted location has valid content?
      if (!state.currentPointer.isNull) return;

      // Otherwise, if diverted location doesn't have valid content,
      // drop down and attempt to increment.
      // This can happen if the diverted path is intentionally jumping
      // to the end of a container - e.g. a Conditional that's re-joining
    }

    final successfulPointerIncrement = _incrementContentPointer();

    // Ran out of content? Try to auto-exit from a function,
    // or finish evaluating the content of a thread
    if (!successfulPointerIncrement) {
      var didPop = false;

      if (state.callStack.canPopType(PushPopType.function)) {
        // Pop from the call stack
        state.popCallstack(PushPopType.function);

        // This pop was due to dropping off the end of a function that didn't
        // return anything, so in this case, we make sure that the evaluator
        // has something to chomp on if it needs it
        if (state.inExpressionEvaluation) state.pushEvaluationStack(Void());

        didPop = true;
      } else if (state.callStack.canPopThread) {
        state.callStack.popThread();

        didPop = true;
      } else {
        state.tryExitFunctionEvaluationFromGame();
      }

      // Step past the point where we last called out
      if (didPop && !state.currentPointer.isNull) _nextContent();
    }
  }

  bool _incrementContentPointer() {
    var successfulIncrement = true;

    var pointer = state.callStack.currentElement.currentPointer;
    pointer = Pointer(pointer.container, pointer.index + 1);

    // Each time we step off the end, we fall out to the next container, all
    // the while we're in indexed rather than named content
    while (pointer.index >= (pointer.container?.content.length ?? 0)) {
      successfulIncrement = false;

      final parent = pointer.container?.parent;
      final nextAncestor = parent is Container ? parent : null;
      if (nextAncestor == null) break;

      final indexInAncestor = nextAncestor.content.indexOf(
        pointer.container as InkObject,
      );
      if (indexInAncestor == -1) break;

      pointer = Pointer(nextAncestor, indexInAncestor + 1);

      successfulIncrement = true;
    }

    if (!successfulIncrement) pointer = Pointer.nullPointer;

    state.callStack.currentElement.currentPointer = pointer;

    return successfulIncrement;
  }

  bool _tryFollowDefaultInvisibleChoice() {
    final allChoices = _state.currentChoices;

    // Is a default invisible choice the ONLY choice?
    final invisibleChoices = [
      for (final c in allChoices)
        if (c.isInvisibleDefault) c,
    ];
    if (invisibleChoices.isEmpty ||
        allChoices.length > invisibleChoices.length) {
      return false;
    }

    final choice = invisibleChoices[0];

    // Invisible choice may have been generated on a different thread,
    // in which case we need to restore it before we continue
    final thread = choice.threadAtGeneration;
    if (thread != null) state.callStack.currentThread = thread;

    // If there's a chance that this state will be rolled back to before
    // the invisible choice then make sure that the choice thread is
    // left intact, and it isn't re-entered in an old state.
    if (_stateSnapshotAtLastNewline != null) {
      state.callStack.currentThread = state.callStack.forkThread();
    }

    choosePath(choice.targetPath, incrementingTurnIndex: false);

    return true;
  }

  // Note that this is O(n), since it re-evaluates the shuffle indices
  // from a consistent seed each time.
  // TODO: Is this the best algorithm it can be?
  int _nextSequenceShuffleIndex() {
    final numElementsIntVal = _asIntValue(state.popEvaluationStack());
    if (numElementsIntVal == null) {
      error('expected number of elements in sequence for shuffle index');
    }

    final seqContainer = state.currentPointer.container;

    final numElements = numElementsIntVal.value;

    final seqCountVal = state.popEvaluationStack() as IntValue;
    final seqCount = seqCountVal.value;
    if (numElements == 0) {
      throw SystemException('Attempted to divide by zero.');
    }
    final loopIndex = seqCount ~/ numElements;
    final iterationIndex = seqCount.remainder(numElements);

    // Generate the same shuffle based on:
    //  - The hash of this container, to make sure it's consistent
    //    each time the runtime returns to the sequence
    //  - How many times the runtime has looped around this full shuffle
    final seqPathStr = seqContainer?.path.toString() ?? '';
    var sequenceHash = 0;
    for (final c in seqPathStr.codeUnits) {
      sequenceHash += c;
    }
    final randomSeed = (sequenceHash + loopIndex + state.storySeed).toSigned(
      32,
    );
    final random = PRNG(randomSeed);

    final unpickedIndices = <int>[];
    for (var i = 0; i < numElements; ++i) {
      unpickedIndices.add(i);
    }

    for (var i = 0; i <= iterationIndex; ++i) {
      final chosen = random.next() % unpickedIndices.length;
      final chosenIndex = unpickedIndices[chosen];
      unpickedIndices.removeAt(chosen);

      if (i == iterationIndex) return chosenIndex;
    }

    throw SystemException('Should never reach here');
  }

  /// Throw an exception that gets caught and causes AddError to be called,
  /// then exits the flow.
  Never error(String message, {bool useEndLineNumber = false}) {
    throw StoryException(message)..useEndLineNumber = useEndLineNumber;
  }

  /// Adds a runtime warning, reported through [onError] after the current
  /// continue.
  void warning(String message) => _addError(message, isWarning: true);

  void _addError(
    String message, {
    bool isWarning = false,
    bool useEndLineNumber = false,
  }) {
    final dm = _currentDebugMetadata;

    final errorTypeStr = isWarning ? 'WARNING' : 'ERROR';

    if (dm != null) {
      final lineNum = useEndLineNumber ? dm.endLineNumber : dm.startLineNumber;
      message =
          "RUNTIME $errorTypeStr: '${dm.fileName}' line $lineNum: $message";
    } else if (!state.currentPointer.isNull) {
      message =
          'RUNTIME $errorTypeStr: (${state.currentPointer.path}): $message';
    } else {
      message = 'RUNTIME $errorTypeStr: $message';
    }

    state.addError(message, isWarning: isWarning);

    // In a broken state don't need to know about any other errors.
    if (!isWarning) state.forceEnd();
  }

  void _assert(bool condition, [String? message]) {
    if (condition == false) {
      message ??= 'Story assert';
      throw SystemException('$message ${_currentDebugMetadata ?? ''}');
    }
  }

  DebugMetadata? get _currentDebugMetadata {
    DebugMetadata? dm;

    // Try to get from the current path first
    var pointer = state.currentPointer;
    if (!pointer.isNull) {
      dm = pointer.resolve()?.debugMetadata;
      if (dm != null) return dm;
    }

    // Move up callstack if possible
    for (var i = state.callStack.elements.length - 1; i >= 0; --i) {
      pointer = state.callStack.elements[i].currentPointer;
      if (!pointer.isNull && pointer.resolve() != null) {
        dm = pointer.resolve()?.debugMetadata;
        if (dm != null) return dm;
      }
    }

    // Current/previous path may not be valid if we've just had an error,
    // or if we've simply run out of content.
    // As a last resort, try to grab something from the output stream
    for (var i = state.outputStream.length - 1; i >= 0; --i) {
      final outputObj = state.outputStream[i];
      dm = outputObj.debugMetadata;
      if (dm != null) return dm;
    }

    return null;
  }

  /// The story's root container (or the container being evaluated by
  /// [evaluateExpression]).
  Container get mainContentContainer {
    final temp = _temporaryEvaluationContainer;
    if (temp != null) {
      return temp;
    } else {
      return _root;
    }
  }

  Container get _root {
    final root = _mainContentContainer;
    if (root == null) {
      throw SystemException('Root node for ink not found.');
    }
    return root;
  }

  Container? _mainContentContainer;
  ListDefinitionsOrigin? _listDefinitions;

  final Map<String, _ExternalFunctionDef> _externals = {};
  Map<String, List<VariableObserver>>? _variableObservers;
  bool _hasValidatedExternals = false;

  Container? _temporaryEvaluationContainer;

  late StoryState _state;

  bool _asyncContinueActive = false;
  StoryState? _stateSnapshotAtLastNewline;
  bool _sawLookaheadUnsafeFunctionAfterNewline = false;

  int _recursiveContinueCount = 0;

  bool _asyncSaving = false;

  Profiler? _profiler;
}
