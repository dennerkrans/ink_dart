/// Pure Dart runtime for inkle's ink, ported structurally from inkjs and
/// checked against the C# reference runtime.
///
/// ```dart
/// final story = Story.fromJson(jsonString);
/// while (story.canContinue) {
///   print(story.continueStory());
/// }
/// ```
library;

export 'src/error.dart' show ErrorHandler, ErrorType;
export 'src/profile_node.dart' show ProfileNode;
export 'src/profiler.dart' show Profiler;
export 'src/runtime/choice.dart' show Choice;
export 'src/runtime/ink_list.dart' show InkList;
export 'src/runtime/ink_list_item.dart' show InkListItem;
export 'src/state/story_state.dart' show StoryState;
export 'src/state/variables_state.dart' show VariablesState;
export 'src/story.dart' show ExternalFunction, Story, VariableObserver;
export 'src/story_exception.dart' show StoryException;
export 'src/system_exception.dart' show SystemException;
