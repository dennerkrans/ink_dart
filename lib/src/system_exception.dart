/// Stands in for the C# runtime's `System.Exception`: a failure the
/// reference throws past `Story.onError` rather than collecting.
///
/// [toString] is the bare message, as C#'s `Exception.Message` is.
class SystemException implements Exception {
  /// Creates an exception with [message].
  SystemException(this.message);

  /// What went wrong, as the reference words it.
  final String message;

  @override
  String toString() => message;
}
