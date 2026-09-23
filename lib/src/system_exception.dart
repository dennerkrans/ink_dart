/// Stands in for the C# runtime's `System.Exception`: a failure the
/// reference throws past `Story.onError` rather than collecting.
///
/// [toString] is the bare message, as C#'s `Exception.Message` is.
class SystemException implements Exception {
  SystemException(this.message);

  final String message;

  @override
  String toString() => message;
}
