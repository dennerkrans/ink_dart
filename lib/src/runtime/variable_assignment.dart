// Port of ink's VariableAssignment.cs.

import 'ink_object.dart';

/// The value to be assigned is popped off the evaluation stack, so no need
/// to keep it here.
class VariableAssignment extends InkObject {
  VariableAssignment(this.variableName, this.isNewDeclaration);

  final String? variableName;
  final bool isNewDeclaration;
  bool isGlobal = false;

  @override
  String toString() => 'VarAssign to $variableName';
}
