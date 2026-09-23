// Port of ink's Void.cs.

import 'ink_object.dart';

/// What a function that returns nothing leaves on the evaluation stack.
///
/// No `toString` override, as in the reference: it prints
/// `Ink.Runtime.Void` (inkjs prints `Void`).
class Void extends InkObject {}
