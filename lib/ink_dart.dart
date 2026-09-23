/// Pure Dart runtime for inkle's ink.
///
/// Phase 0: the public API exists as signatures only, so the conformance
/// harness can drive it; every member throws [UnimplementedError] until
/// phase 1 ports the runtime from inkjs.
library;

export 'src/choice.dart' show Choice;
export 'src/error.dart' show ErrorHandler, ErrorType;
export 'src/state/story_state.dart' show StoryState;
export 'src/story.dart' show Story;
