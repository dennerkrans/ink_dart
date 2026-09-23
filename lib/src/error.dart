// Port of inkjs src/engine/Error.ts.

/// Receives errors and warnings as data instead of an exception.
typedef ErrorHandler = void Function(String message, ErrorType type);

enum ErrorType { author, warning, error }
