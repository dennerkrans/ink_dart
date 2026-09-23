// Port of inkjs src/engine/Story.ts. Phase 0: signatures only.

import 'choice.dart';
import 'error.dart';
import 'state/story_state.dart';

/// A compiled ink story and the machine that runs it.
class Story {
  /// Loads a story from its compiled JSON token tree.
  Story(Map<String, Object?> json) {
    throw UnimplementedError('Story');
  }

  /// Loads a story from the compiled JSON string.
  factory Story.fromJson(String json) =>
      throw UnimplementedError('Story.fromJson');

  /// Receives errors and warnings; when null, the first error throws.
  ErrorHandler? onError;

  StoryState get state => throw UnimplementedError('Story.state');

  bool get canContinue => throw UnimplementedError('Story.canContinue');

  /// Runs to the end of the next line and returns it. Named for inkjs's
  /// `Continue`, which is a reserved word in Dart.
  String continueStory() => throw UnimplementedError('Story.continueStory');

  List<String> get currentTags => throw UnimplementedError('Story.currentTags');

  List<Choice> get currentChoices =>
      throw UnimplementedError('Story.currentChoices');

  List<String>? get globalTags => throw UnimplementedError('Story.globalTags');

  void chooseChoiceIndex(int choiceIdx) =>
      throw UnimplementedError('Story.chooseChoiceIndex');
}
