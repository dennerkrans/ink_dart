import 'package:flutter/foundation.dart';
import 'package:ink_dart/ink_dart.dart';

/// One line of story output, with the tags attached to it.
@immutable
class StoryLine {
  /// Creates a line; [StoryController] makes these as the story continues.
  const StoryLine(this.text, this.tags);

  /// The line's text, including its trailing newline.
  final String text;

  /// Tags written on the line (`# tag` in ink).
  final List<String> tags;

  @override
  String toString() => tags.isEmpty ? text : '$text# ${tags.join(' # ')}';
}

/// An error or warning the story reported while continuing.
@immutable
class StoryError {
  /// Creates an error record; [StoryController] makes these from the
  /// story's `onError`.
  const StoryError(this.message, this.type);

  /// The runtime's message, as the C# runtime words it.
  final String message;

  /// Whether this is an error, a warning or an author note.
  final ErrorType type;

  @override
  String toString() => '$type: $message';
}

/// Drives a [Story] and notifies listeners whenever its output changes.
///
/// The controller never continues on its own: bind external functions and
/// set variables on [story] first, then call [continueMaximally] (or
/// [continueStory] for one line at a time). It collects every line into
/// [lines] until [clearTranscript], and every error into [errors].
///
/// The controller owns [Story.onError]; don't set it yourself.
class StoryController extends ChangeNotifier {
  /// Wraps an existing [story].
  StoryController(this.story) {
    story.onError = (message, type) {
      _errors.add(StoryError(message, type));
    };
  }

  /// Loads a story from its compiled JSON. Takes the JSON string rather
  /// than a decoded map, so float literals keep their type on the web.
  StoryController.fromJson(String json) : this(Story.fromJson(json));

  /// The story being played; use it for anything the controller doesn't
  /// wrap (variables, external functions, flows, evaluating functions).
  final Story story;

  final List<StoryLine> _lines = [];
  final List<StoryError> _errors = [];
  final Map<String, _Watch> _watches = {};

  /// Every line produced since the story started or since the last
  /// [clearTranscript].
  List<StoryLine> get lines => List.unmodifiable(_lines);

  /// Errors and warnings reported so far, oldest first.
  List<StoryError> get errors => List.unmodifiable(_errors);

  /// The choices on offer now; pass a choice's `index` to [choose].
  List<Choice> get choices => story.currentChoices;

  /// Whether there is more content before the next choice or the end.
  bool get canContinue => story.canContinue;

  /// Whether the story has finished: nothing to continue and no choices.
  bool get isEnded => !story.canContinue && story.currentChoices.isEmpty;

  /// Continues one line and returns it, or returns null if the story
  /// can't continue.
  StoryLine? continueStory() {
    if (!story.canContinue) return null;
    final line = _continueOnce();
    notifyListeners();
    return line;
  }

  /// Continues until the next choice or the end, collecting every line.
  void continueMaximally() {
    if (!story.canContinue) return;
    while (story.canContinue) {
      _continueOnce();
    }
    notifyListeners();
  }

  StoryLine _continueOnce() {
    final text = story.continueStory();
    final line = StoryLine(text, List.unmodifiable(story.currentTags));
    _lines.add(line);
    return line;
  }

  /// Chooses the choice with [index] (a [Choice.index] from [choices]),
  /// then continues to the next choice unless [continueAfter] is false.
  void choose(int index, {bool continueAfter = true}) {
    story.chooseChoiceIndex(index);
    if (continueAfter) {
      continueMaximally();
    } else {
      notifyListeners();
    }
  }

  /// Forgets the collected [lines], for example at the start of a new beat.
  void clearTranscript() {
    _lines.clear();
    notifyListeners();
  }

  /// Saves the story's state; see [StoryState.toJson].
  String toJson() => story.state.toJson();

  /// Loads a saved state and clears the transcript. The story then carries
  /// on from where it was saved.
  void loadJson(String json) {
    story.state.loadJson(json);
    _lines.clear();
    notifyListeners();
  }

  /// A listenable holding the current value of the global variable [name],
  /// updated whenever the story assigns it.
  ValueListenable<Object?> watch(String name) {
    final existing = _watches[name];
    if (existing != null) return existing.notifier;

    final notifier = ValueNotifier<Object?>(story.variablesState[name]);
    void observer(String _, Object? value) => notifier.value = value;
    story.observeVariable(name, observer);
    _watches[name] = _Watch(notifier, observer);
    return notifier;
  }

  @override
  void dispose() {
    for (final entry in _watches.entries) {
      story.removeVariableObserver(
        observer: entry.value.observer,
        specificVariableName: entry.key,
      );
      entry.value.notifier.dispose();
    }
    _watches.clear();
    super.dispose();
  }
}

class _Watch {
  _Watch(this.notifier, this.observer);
  final ValueNotifier<Object?> notifier;
  final VariableObserver observer;
}
