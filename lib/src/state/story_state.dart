// Port of inkjs src/engine/StoryState.ts. Phase 0: signatures only.

/// The saveable state of a running story.
class StoryState {
  int get storySeed => throw UnimplementedError('StoryState.storySeed');
  set storySeed(int value) => throw UnimplementedError('StoryState.storySeed');

  String toJson() => throw UnimplementedError('StoryState.toJson');
}
