/// Flutter widgets for [ink_dart](https://pub.dev/packages/ink_dart), the
/// pure Dart runtime for [inkle's ink](https://www.inklestudios.com/ink/).
///
/// - [StoryController] drives a story and notifies listeners as it
///   changes: it continues when asked, collects the lines with their tags,
///   records errors instead of throwing, chooses, saves and loads, and turns
///   a variable into a `ValueListenable` with [StoryController.watch].
/// - [StoryView] shows the lines and current choices, playing on when a
///   choice is tapped; replace how they look with `lineBuilder` and
///   `choiceBuilder`.
/// - [StoryDebugView] shows where the story is, its variables, visit
///   counts, errors and an optional profiler report.
///
/// ```dart
/// final controller = StoryController.fromJson(compiledJson);
///
/// // Game-side setup comes before the first continue.
/// controller.story.bindExternalFunction1<int>('roll', (sides) => dice.roll(sides));
/// final gold = controller.watch('gold');
///
/// controller.continueMaximally();
///
/// // In the widget tree:
/// StoryView(controller: controller);
/// ValueListenableBuilder(
///   valueListenable: gold,
///   builder: (context, value, _) => Text('Gold: $value'),
/// );
/// ```
///
/// Save with [StoryController.toJson] and restore with
/// [StoryController.loadJson]; saves use the C# ink runtime's format. For
/// the story API itself (variables, external functions, flows), see
/// ink_dart's guides, starting with
/// [Getting started](https://pub.dev/documentation/ink_dart/latest/topics/Getting%20started-topic.html).
///
/// This library re-exports `package:ink_dart/ink_dart.dart`, so one import
/// is enough.
library;

export 'package:ink_dart/ink_dart.dart';

export 'src/story_controller.dart' show StoryController, StoryError, StoryLine;
export 'src/story_debug_view.dart' show StoryDebugView;
export 'src/story_view.dart' show StoryView;
