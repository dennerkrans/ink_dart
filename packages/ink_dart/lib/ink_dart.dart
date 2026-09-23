/// A pure Dart runtime for [inkle's ink](https://www.inklestudios.com/ink/),
/// the narrative scripting language behind *80 Days* and *Heaven's Vault*.
///
/// It plays stories compiled to ink's JSON format, and it is checked against
/// inkle's C# runtime: the same story, seed and choices give the same text,
/// tags, choices, errors and save files as in Unity or Inky.
///
/// ```dart
/// import 'package:ink_dart/ink_dart.dart';
///
/// final story = Story.fromJson(jsonString);
/// story.onError = (message, type) => print('$type: $message');
///
/// while (story.canContinue) {
///   print(story.continueStory());
/// }
/// for (final choice in story.currentChoices) {
///   print('${choice.index}: ${choice.text}');
/// }
/// story.chooseChoiceIndex(0);
/// ```
///
/// The API follows ink's C# `Story` API name for name, in Dart casing, so
/// ink's own guide to
/// [running your ink](https://github.com/inkle/ink/blob/master/Documentation/RunningYourInk.md)
/// applies. The one rename is `continueStory` for `Continue`, since
/// `continue` is a Dart keyword.
///
/// ## Guides
///
/// - [Getting started](../topics/Getting%20started-topic.html): compiling,
///   the play loop, choices, tags and errors.
/// - [Game functions and variables](../topics/Game%20functions%20and%20variables-topic.html):
///   `variablesState`, observers, external functions, calling ink
///   functions, lists.
/// - [Saving and loading](../topics/Saving%20and%20loading-topic.html):
///   save files, moving them between runtimes, background saves.
/// - [Flows](../topics/Flows-topic.html): several threads of story at once.
/// - [Matching Unity and Inky](../topics/Matching%20Unity%20and%20Inky-topic.html):
///   numbers, randomness and how the port is checked.
///
/// ## Where to start
///
/// - [Story]: load, play, choose, and everything the game talks to.
/// - [StoryState]: the saveable state, from [Story.state].
/// - [VariablesState]: the story's global variables.
/// - [Choice], [InkList], [ErrorType], [StoryException].
/// - [Profiler]: where a story spends its time.
///
/// For Flutter widgets on top of this package, see
/// [flutter_ink](https://pub.dev/packages/flutter_ink).
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
