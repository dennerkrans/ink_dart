// Port of ink's Choice.cs.

import '../state/call_stack.dart';
import 'ink_object.dart';
import 'path.dart';

/// A generated Choice from the story.
/// A single ChoicePoint in the Story could potentially generate
/// different Choices dynamically dependent on state, so they're
/// separated.
///
/// {@category Getting started}
class Choice extends InkObject {
  /// Creates an empty choice; the story fills it in when generating
  /// choices.
  Choice();

  /// The main text to presented to the player for this Choice.
  String text = '';

  /// The target path that the Story should be diverted to if
  /// this Choice is chosen.
  String get pathStringOnChoice => targetPath.toString();

  set pathStringOnChoice(String value) => targetPath = Path.fromString(value);

  /// Get the path to the original choice point - where was this choice
  /// defined in the story?
  String sourcePath = '';

  /// The original index into currentChoices list on the Story when
  /// this Choice was generated, for convenience.
  int index = 0;

  /// The path the story diverts to when this choice is chosen.
  Path targetPath = Path();

  /// A copy of the call stack thread as it was when this choice was generated;
  /// restored when the choice is chosen.
  Thread? threadAtGeneration;

  /// The index of [threadAtGeneration], as saved in state JSON.
  int originalThreadIndex = 0;

  /// Whether this is an invisible default choice (a fallback `* ->`), taken
  /// automatically when no other choice is available. Not shown in
  /// `Story.currentChoices`.
  bool isInvisibleDefault = false;

  /// Tags written on the choice, or null if it has none.
  List<String>? tags;

  /// A copy of this choice with its own copy of [threadAtGeneration].
  Choice clone() {
    final copy = Choice()
      ..text = text
      ..sourcePath = sourcePath
      ..index = index
      ..targetPath = targetPath
      ..originalThreadIndex = originalThreadIndex
      ..isInvisibleDefault = isInvisibleDefault;
    final t = threadAtGeneration;
    if (t != null) copy.threadAtGeneration = t.copy();
    return copy;
  }
}
