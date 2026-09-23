// Port of ink's CallStack.cs, with its nested Element and Thread classes.

import '../json/json_serialisation.dart';
import '../json/simple_json.dart';
import '../runtime/ink_object.dart';
import '../runtime/list_value.dart';
import '../runtime/path.dart';
import '../runtime/pointer.dart';
import '../runtime/push_pop.dart';
import '../story.dart';
import '../system_exception.dart';

/// `CallStack.Element` in the reference.
class Element {
  Element(
    this.type,
    this.currentPointer, [
    this.inExpressionEvaluation = false,
  ]);

  Pointer currentPointer;

  bool inExpressionEvaluation;
  Map<String, InkObject> temporaryVariables = {};
  PushPopType type;

  /// When this callstack element is actually a function evaluation called
  /// from the game, we need to keep track of the size of the evaluation stack
  /// when it was called so that we know whether there was any return value.
  int evaluationStackHeightWhenPushed = 0;

  /// When functions are called, we trim whitespace from the start and end of
  /// what they generate, so we make sure know where the function's start and
  /// end are.
  int functionStartInOuputStream = 0;

  Element copy() {
    final copy = Element(type, currentPointer, inExpressionEvaluation)
      ..temporaryVariables = {...temporaryVariables}
      ..evaluationStackHeightWhenPushed = evaluationStackHeightWhenPushed
      ..functionStartInOuputStream = functionStartInOuputStream;
    return copy;
  }
}

/// `CallStack.Thread` in the reference.
class Thread {
  Thread();

  Thread.fromJson(Map<String, Object?> jThreadObj, Story storyContext) {
    threadIndex = jThreadObj['threadIndex'] as int;

    final jThreadCallstack = jThreadObj['callstack'] as List<Object?>;
    for (final jElTok in jThreadCallstack) {
      final jElementObj = jElTok as Map<String, Object?>;

      final pushPopType = PushPopType.values[jElementObj['type'] as int];

      var pointer = Pointer.nullPointer;

      final currentContainerPathStrToken = jElementObj['cPath'];
      if (currentContainerPathStrToken != null) {
        final currentContainerPathStr = currentContainerPathStrToken.toString();

        final threadPointerResult = storyContext.contentAtPath(
          Path.fromString(currentContainerPathStr),
        );
        pointer = Pointer(
          threadPointerResult.container,
          jElementObj['idx'] as int,
        );

        if (threadPointerResult.obj == null) {
          throw SystemException(
            "When loading state, internal story location couldn't be found: "
            '$currentContainerPathStr. Has the story changed since this save '
            'data was created?',
          );
        } else if (threadPointerResult.approximate) {
          final c = pointer.container;
          if (c != null) {
            storyContext.warning(
              "When loading state, exact internal story location couldn't be "
              "found: '$currentContainerPathStr', so it was approximated to "
              "'${c.path}' to recover. Has the story changed since this save "
              'data was created?',
            );
          } else {
            storyContext.warning(
              "When loading state, exact internal story location couldn't be "
              "found: '$currentContainerPathStr' and it may not be "
              'recoverable. Has the story changed since this save data was '
              'created?',
            );
          }
        }
      }

      final inExpressionEvaluation = jElementObj['exp'] as bool;

      final el = Element(pushPopType, pointer, inExpressionEvaluation);

      final temps = jElementObj['temp'];
      if (temps != null) {
        el.temporaryVariables =
            JsonSerialisation.jObjectToDictionaryRuntimeObjs(
              temps as Map<String, Object?>,
            );
      } else {
        el.temporaryVariables.clear();
      }

      callstack.add(el);
    }

    final prevContentObjPath = jThreadObj['previousContentObject'];
    if (prevContentObjPath != null) {
      final prevPath = Path.fromString(prevContentObjPath as String);
      previousPointer = storyContext.pointerAtPath(prevPath);
    }
  }

  List<Element> callstack = [];
  int threadIndex = 0;
  Pointer previousPointer = Pointer.nullPointer;

  Thread copy() {
    final copy = Thread()..threadIndex = threadIndex;
    for (final e in callstack) {
      copy.callstack.add(e.copy());
    }
    copy.previousPointer = previousPointer;
    return copy;
  }

  void writeJson(Writer writer) {
    writer.writeObjectStart();

    // callstack
    writer.writePropertyStart('callstack');
    writer.writeArrayStart();
    for (final el in callstack) {
      writer.writeObjectStart();
      final container = el.currentPointer.container;
      if (container != null) {
        writer.writeProperty('cPath', container.path.componentsString);
        writer.writeIntProperty('idx', el.currentPointer.index);
      }

      writer.writeBoolProperty('exp', el.inExpressionEvaluation);
      writer.writeIntProperty('type', el.type.index);

      if (el.temporaryVariables.isNotEmpty) {
        writer.writePropertyStart('temp');
        JsonSerialisation.writeDictionaryRuntimeObjs(
          writer,
          el.temporaryVariables,
        );
        writer.writePropertyEnd();
      }

      writer.writeObjectEnd();
    }
    writer.writeArrayEnd();
    writer.writePropertyEnd();

    // threadIndex
    writer.writeIntProperty('threadIndex', threadIndex);

    if (!previousPointer.isNull) {
      final resolved = previousPointer.resolve();
      if (resolved == null) {
        throw SystemException(
          'Object reference not set to an instance of an object.',
        );
      }
      writer.writeProperty('previousContentObject', resolved.path.toString());
    }

    writer.writeObjectEnd();
  }
}

class CallStack {
  CallStack(Story storyContext)
    : _startOfRoot = Pointer.startOf(storyContext.rootContentContainer) {
    reset();
  }

  CallStack.copyOf(CallStack toCopy)
    : _threadCounter = toCopy._threadCounter,
      _startOfRoot = toCopy._startOfRoot {
    for (final otherThread in toCopy._threads) {
      _threads.add(otherThread.copy());
    }
  }

  List<Element> get elements => _callStack;

  int get depth => elements.length;

  Element get currentElement {
    final thread = _threads[_threads.length - 1];
    final cs = thread.callstack;
    return cs[cs.length - 1];
  }

  int get currentElementIndex => _callStack.length - 1;

  Thread get currentThread => _threads[_threads.length - 1];

  set currentThread(Thread value) {
    _threads.clear();
    _threads.add(value);
  }

  bool get canPop => _callStack.length > 1;

  void reset() {
    _threads = [Thread()];
    _threads[0].callstack.add(Element(PushPopType.tunnel, _startOfRoot));
  }

  // Unfortunately it's not possible to implement jsonToken since
  // the setter needs to take a Story as a context in order to
  // look up objects from paths for currentContainer within elements.
  void setJsonToken(Map<String, Object?> jObject, Story storyContext) {
    _threads.clear();

    final jThreads = jObject['threads'] as List<Object?>;

    for (final jThreadTok in jThreads) {
      final jThreadObj = jThreadTok as Map<String, Object?>;
      _threads.add(Thread.fromJson(jThreadObj, storyContext));
    }

    _threadCounter = jObject['threadCounter'] as int;
    _startOfRoot = Pointer.startOf(storyContext.rootContentContainer);
  }

  void writeJson(Writer w) {
    w.writeObject((writer) {
      writer.writePropertyStart('threads');
      writer.writeArrayStart();

      for (final thread in _threads) {
        thread.writeJson(writer);
      }

      writer.writeArrayEnd();
      writer.writePropertyEnd();

      writer.writePropertyStart('threadCounter');
      writer.writeInt(_threadCounter);
      writer.writePropertyEnd();
    });
  }

  void pushThread() {
    final newThread = currentThread.copy();
    _threadCounter++;
    newThread.threadIndex = _threadCounter;
    _threads.add(newThread);
  }

  Thread forkThread() {
    final forkedThread = currentThread.copy();
    _threadCounter++;
    forkedThread.threadIndex = _threadCounter;
    return forkedThread;
  }

  void popThread() {
    if (canPopThread) {
      _threads.remove(currentThread);
    } else {
      throw SystemException("Can't pop thread");
    }
  }

  bool get canPopThread => _threads.length > 1 && !elementIsEvaluateFromGame;

  bool get elementIsEvaluateFromGame =>
      currentElement.type == PushPopType.functionEvaluationFromGame;

  void push(
    PushPopType type, {
    int externalEvaluationStackHeight = 0,
    int outputStreamLengthWithPushed = 0,
  }) {
    // When pushing to callstack, maintain the current content path, but
    // jump out of expressions by default
    final element = Element(type, currentElement.currentPointer, false)
      ..evaluationStackHeightWhenPushed = externalEvaluationStackHeight
      ..functionStartInOuputStream = outputStreamLengthWithPushed;

    _callStack.add(element);
  }

  bool canPopType([PushPopType? type]) {
    if (!canPop) return false;

    if (type == null) return true;

    return currentElement.type == type;
  }

  void pop([PushPopType? type]) {
    if (canPopType(type)) {
      _callStack.removeLast();
      return;
    } else {
      throw SystemException('Mismatched push/pop in Callstack');
    }
  }

  /// Get variable value, dereferencing a variable pointer if necessary
  InkObject? getTemporaryVariableWithName(
    String name, [
    int contextIndex = -1,
  ]) {
    // contextIndex 0 means global, so index is actually 1-based
    if (contextIndex == -1) contextIndex = currentElementIndex + 1;

    final contextElement = _callStack[contextIndex - 1];

    return contextElement.temporaryVariables[name];
  }

  void setTemporaryVariable(
    String name,
    InkObject value,
    bool declareNew, [
    int contextIndex = -1,
  ]) {
    if (contextIndex == -1) contextIndex = currentElementIndex + 1;

    final contextElement = _callStack[contextIndex - 1];

    if (!declareNew && !contextElement.temporaryVariables.containsKey(name)) {
      throw SystemException('Could not find temporary variable to set: $name');
    }

    final oldValue = contextElement.temporaryVariables[name];
    if (oldValue != null) {
      ListValue.retainListOriginsForAssignment(oldValue, value);
    }

    contextElement.temporaryVariables[name] = value;
  }

  /// Find the most appropriate context for this variable.
  /// Are we referencing a temporary or global variable?
  /// Note that the compiler will have warned us about possible conflicts,
  /// so anything that happens here should be safe!
  int contextForVariableNamed(String name) {
    // Current temporary context?
    // (Shouldn't attempt to access contexts higher in the callstack.)
    if (currentElement.temporaryVariables.containsKey(name)) {
      return currentElementIndex + 1;
    }
    // Global
    else {
      return 0;
    }
  }

  Thread? threadWithIndex(int index) {
    for (final t in _threads) {
      if (t.threadIndex == index) return t;
    }
    return null;
  }

  List<Element> get _callStack => currentThread.callstack;

  String get callStackTrace {
    final sb = StringBuffer();

    for (var t = 0; t < _threads.length; t++) {
      final thread = _threads[t];
      final isCurrent = t == _threads.length - 1;
      sb.write(
        '=== THREAD ${t + 1}/${_threads.length} '
        '${isCurrent ? '(current) ' : ''}===\n',
      );

      for (var i = 0; i < thread.callstack.length; i++) {
        if (thread.callstack[i].type == PushPopType.function) {
          sb.write('  [FUNCTION] ');
        } else {
          sb.write('  [TUNNEL] ');
        }

        final pointer = thread.callstack[i].currentPointer;
        final container = pointer.container;
        if (container != null) {
          sb.write('<SOMEWHERE IN ');
          sb.write(container.path.toString());
          sb.writeln('>');
        }
      }
    }

    return sb.toString();
  }

  List<Thread> _threads = [];
  int _threadCounter = 0;
  Pointer _startOfRoot;
}
