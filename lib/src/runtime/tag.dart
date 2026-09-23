// Port of ink's Tag.cs.

import 'ink_object.dart';

/// Legacy static tag; dynamic tags are content between BeginTag and EndTag.
/// Still used when flattening tags to strings during string evaluation.
class Tag extends InkObject {
  Tag(this.text);

  final String text;

  @override
  String toString() => '# $text';
}
