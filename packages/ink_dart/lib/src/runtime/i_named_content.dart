// Port of ink's INamedContent.cs.

/// Content addressable by name within its parent container.
abstract interface class INamedContent {
  String? get name;
  bool get hasValidName;
}
