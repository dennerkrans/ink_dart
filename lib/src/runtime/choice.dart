// Port of ink's Choice.cs.

import '../state/call_stack.dart';
import 'ink_object.dart';
import 'path.dart';

/// A generated Choice from the story.
/// A single ChoicePoint in the Story could potentially generate
/// different Choices dynamically dependent on state, so they're
/// separated.
class Choice extends InkObject {
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

  Path targetPath = Path();

  Thread? threadAtGeneration;
  int originalThreadIndex = 0;

  bool isInvisibleDefault = false;

  List<String>? tags;

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
