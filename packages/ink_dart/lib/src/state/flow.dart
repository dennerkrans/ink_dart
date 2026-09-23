// Port of ink's Flow.cs.

import '../json/json_serialisation.dart';
import '../json/simple_json.dart';
import '../runtime/choice.dart';
import '../runtime/ink_object.dart';
import '../story.dart';
import 'call_stack.dart';

class Flow {
  Flow(this.name, Story story)
    : callStack = CallStack(story),
      outputStream = [],
      currentChoices = [];

  Flow.fromJson(this.name, Story story, Map<String, Object?> jObject)
    : callStack = CallStack(story),
      outputStream = [],
      currentChoices = [] {
    callStack.setJsonToken(jObject['callstack'] as Map<String, Object?>, story);
    outputStream = JsonSerialisation.jArrayToRuntimeObjList(
      jObject['outputStream'] as List<Object?>,
    );
    currentChoices = JsonSerialisation.jArrayToRuntimeObjList<Choice>(
      jObject['currentChoices'] as List<Object?>,
    );

    // choiceThreads is optional
    final jChoiceThreadsObj = jObject['choiceThreads'];
    loadFlowChoiceThreads(jChoiceThreadsObj as Map<String, Object?>?, story);
  }

  String name;
  CallStack callStack;
  List<InkObject> outputStream;
  List<Choice> currentChoices;

  void writeJson(Writer writer) {
    writer.writeObjectStart();

    writer.writePropertyWith('callstack', callStack.writeJson);
    writer.writePropertyWith(
      'outputStream',
      (w) => JsonSerialisation.writeListRuntimeObjs(w, outputStream),
    );

    // choiceThreads: optional
    // Has to come BEFORE the choices themselves are written out
    // since the originalThreadIndex of each choice needs to be set
    var hasChoiceThreads = false;
    for (final c in currentChoices) {
      final thread = c.threadAtGeneration;
      if (thread == null) continue;
      c.originalThreadIndex = thread.threadIndex;

      if (callStack.threadWithIndex(c.originalThreadIndex) == null) {
        if (!hasChoiceThreads) {
          hasChoiceThreads = true;
          writer.writePropertyStart('choiceThreads');
          writer.writeObjectStart();
        }

        writer.writePropertyStart(c.originalThreadIndex);
        thread.writeJson(writer);
        writer.writePropertyEnd();
      }
    }

    if (hasChoiceThreads) {
      writer.writeObjectEnd();
      writer.writePropertyEnd();
    }

    writer.writePropertyWith('currentChoices', (w) {
      w.writeArrayStart();
      for (final c in currentChoices) {
        JsonSerialisation.writeChoice(w, c);
      }
      w.writeArrayEnd();
    });

    writer.writeObjectEnd();
  }

  // Used both to load old format and current
  void loadFlowChoiceThreads(
    Map<String, Object?>? jChoiceThreads,
    Story story,
  ) {
    for (final choice in currentChoices) {
      final foundActiveThread = callStack.threadWithIndex(
        choice.originalThreadIndex,
      );
      if (foundActiveThread != null) {
        choice.threadAtGeneration = foundActiveThread.copy();
      } else {
        final jSavedChoiceThread =
            jChoiceThreads?['${choice.originalThreadIndex}']
                as Map<String, Object?>;
        choice.threadAtGeneration = Thread.fromJson(jSavedChoiceThread, story);
      }
    }
  }
}
