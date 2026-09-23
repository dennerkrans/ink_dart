// Port of ink's ControlCommand.cs.

import 'ink_object.dart';

enum CommandType {
  notSet('NotSet'),
  evalStart('EvalStart'),
  evalOutput('EvalOutput'),
  evalEnd('EvalEnd'),
  duplicate('Duplicate'),
  popEvaluatedValue('PopEvaluatedValue'),
  popFunction('PopFunction'),
  popTunnel('PopTunnel'),
  beginString('BeginString'),
  endString('EndString'),
  noOp('NoOp'),
  choiceCount('ChoiceCount'),
  turns('Turns'),
  turnsSince('TurnsSince'),
  readCount('ReadCount'),
  random('Random'),
  seedRandom('SeedRandom'),
  visitIndex('VisitIndex'),
  sequenceShuffleIndex('SequenceShuffleIndex'),
  startThread('StartThread'),
  done('Done'),
  end('End'),
  listFromInt('ListFromInt'),
  listRange('ListRange'),
  listRandom('ListRandom'),
  beginTag('BeginTag'),
  endTag('EndTag');

  const CommandType(this.csName);

  /// The C# enum member name, as the reference prints it.
  final String csName;
}

class ControlCommand extends InkObject {
  ControlCommand([this.commandType = CommandType.notSet]);

  final CommandType commandType;

  @override
  InkObject copy() => ControlCommand(commandType);

  // The following static factory methods are to make generating these
  // objects slightly more succinct. Without these, the code gets pretty
  // massive! e.g.
  //
  //     var c = new Runtime.ControlCommand(Runtime.ControlCommand.CommandType.EvalStart)
  //
  // as opposed to
  //
  //     var c = Runtime.ControlCommand.EvalStart()

  static ControlCommand evalStart() => ControlCommand(CommandType.evalStart);
  static ControlCommand evalOutput() => ControlCommand(CommandType.evalOutput);
  static ControlCommand evalEnd() => ControlCommand(CommandType.evalEnd);
  static ControlCommand duplicate() => ControlCommand(CommandType.duplicate);
  static ControlCommand popEvaluatedValue() =>
      ControlCommand(CommandType.popEvaluatedValue);
  static ControlCommand popFunction() =>
      ControlCommand(CommandType.popFunction);
  static ControlCommand popTunnel() => ControlCommand(CommandType.popTunnel);
  static ControlCommand beginString() =>
      ControlCommand(CommandType.beginString);
  static ControlCommand endString() => ControlCommand(CommandType.endString);
  static ControlCommand noOp() => ControlCommand(CommandType.noOp);
  static ControlCommand choiceCount() =>
      ControlCommand(CommandType.choiceCount);
  static ControlCommand turns() => ControlCommand(CommandType.turns);
  static ControlCommand turnsSince() => ControlCommand(CommandType.turnsSince);
  static ControlCommand readCount() => ControlCommand(CommandType.readCount);
  static ControlCommand random() => ControlCommand(CommandType.random);
  static ControlCommand seedRandom() => ControlCommand(CommandType.seedRandom);
  static ControlCommand visitIndex() => ControlCommand(CommandType.visitIndex);
  static ControlCommand sequenceShuffleIndex() =>
      ControlCommand(CommandType.sequenceShuffleIndex);
  static ControlCommand startThread() =>
      ControlCommand(CommandType.startThread);
  static ControlCommand done() => ControlCommand(CommandType.done);
  static ControlCommand end() => ControlCommand(CommandType.end);
  static ControlCommand listFromInt() =>
      ControlCommand(CommandType.listFromInt);
  static ControlCommand listRange() => ControlCommand(CommandType.listRange);
  static ControlCommand listRandom() => ControlCommand(CommandType.listRandom);
  static ControlCommand beginTag() => ControlCommand(CommandType.beginTag);
  static ControlCommand endTag() => ControlCommand(CommandType.endTag);

  @override
  String toString() => commandType.csName;
}
