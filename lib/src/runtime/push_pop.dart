// Port of ink's PushPop.cs.

enum PushPopType {
  tunnel,
  function,
  functionEvaluationFromGame;

  /// The C# enum member name, as the reference prints it.
  String get csName => switch (this) {
    tunnel => 'Tunnel',
    function => 'Function',
    functionEvaluationFromGame => 'FunctionEvaluationFromGame',
  };
}
