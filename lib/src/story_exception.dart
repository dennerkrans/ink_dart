// Port of ink's StoryException.cs.

/// An error in the story content, reported through `Story.onError` (or
/// thrown when no handler is set).
class StoryException implements Exception {
  StoryException(this.message);

  final String message;

  bool useEndLineNumber = false;

  @override
  String toString() => message;
}
