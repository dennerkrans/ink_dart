/// Flutter widgets for ink_dart: [StoryController] drives a story and
/// notifies listeners, [StoryView] shows its text and choices, and
/// [StoryDebugView] shows its state while you write.
///
/// Re-exports `package:ink_dart/ink_dart.dart`, so one import is enough.
library;

export 'package:ink_dart/ink_dart.dart';

export 'src/story_controller.dart' show StoryController, StoryError, StoryLine;
export 'src/story_debug_view.dart' show StoryDebugView;
export 'src/story_view.dart' show StoryView;
