// Port of ink's Void.cs.

import 'ink_object.dart';

/// What a function that returns nothing leaves on the evaluation stack.
class Void extends InkObject {
  @override
  String toString() => 'Void';
}
