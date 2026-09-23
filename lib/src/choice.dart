// Port of inkjs src/engine/Choice.ts. Phase 0: public fields only; the
// thread, path and clone members arrive with the runtime in phase 1.

/// A choice presented to the player after a [Story] stops continuing.
class Choice {
  String text = '';
  int index = 0;
  List<String>? tags;
}
