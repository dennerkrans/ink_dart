// Port of ink's StoryException.cs.

/// An error in the story content, reported through `Story.onError` (or
/// thrown when no handler is set).
///
/// {@category Getting started}
class StoryException implements Exception {
  /// Creates an exception with [message].
  StoryException(this.message);

  /// What went wrong, as the reference words it.
  final String message;

  /// Whether the error location should use the end line of the content.
  bool useEndLineNumber = false;

  @override
  String toString() => message;
}
