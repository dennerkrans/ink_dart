// Port of ink's Profiler.cs: Profiler and its StepDetails.

import 'profile_node.dart';
import 'runtime/control_command.dart';
import 'runtime/ink_object.dart';
import 'state/call_stack.dart';

/// Simple ink profiler that logs every instruction in the story and counts
/// frequency and timing. To use:
///
///     final profiler = story.startProfiling();
///     // (play your story for a bit)
///     final reportStr = profiler.report();
///     story.endProfiling();
class Profiler {
  /// Creates a profiler; [Story.startProfiling] makes one and attaches it.
  Profiler() : _rootNode = ProfileNode();

  /// The root node in the hierarchical tree of recorded ink timings.
  ProfileNode get rootNode => _rootNode;

  /// Generate a printable report based on the data recording during
  /// profiling.
  String report() {
    final sb = StringBuffer()
      ..write('$_numContinues CONTINUES / LINES:\n')
      ..write('TOTAL TIME: ${formatMillisecs(_continueTotal)}\n')
      ..write('SNAPSHOTTING: ${formatMillisecs(_snapTotal)}\n')
      ..write(
        'OTHER: ${formatMillisecs(_continueTotal - (_stepTotal + _snapTotal))}'
        '\n',
      )
      ..write(_rootNode.toString());
    return sb.toString();
  }

  /// Called by the story before each continue.
  void preContinue() {
    _continueWatch
      ..reset()
      ..start();
  }

  /// Called by the story after each continue.
  void postContinue() {
    _continueWatch.stop();
    _continueTotal += _millisecs(_continueWatch);
    _numContinues++;
  }

  /// Called by the story before each step.
  void preStep() {
    _currStepStack = null;
    _stepWatch
      ..reset()
      ..start();
  }

  /// Called by the story once the step's content is known: records the
  /// call stack by the name of each element's nearest named container.
  void step(CallStack callstack) {
    _stepWatch.stop();

    final stack = <String>[];
    for (final element in callstack.elements) {
      var stackElementName = '';
      final objPath = element.currentPointer.path;
      if (objPath != null) {
        for (var c = 0; c < objPath.length; c++) {
          final comp = objPath.getComponent(c);
          if (!comp.isIndex) {
            stackElementName = comp.name ?? '';
            break;
          }
        }
      }
      stack.add(stackElementName);
    }

    _currStepStack = stack;

    final currObj = callstack.currentElement.currentPointer.resolve();

    String stepType;
    if (currObj is ControlCommand) {
      stepType = '${currObj.commandType.csName} CC';
    } else {
      stepType = '${currObj.runtimeType}';
    }

    _currStepDetails = _StepDetails(stepType, currObj);

    _stepWatch.start();
  }

  /// Called by the story after each step.
  void postStep() {
    _stepWatch.stop();

    final duration = _millisecs(_stepWatch);
    _stepTotal += duration;

    _rootNode.addSample(_currStepStack ?? const [], duration);

    final details = _currStepDetails;
    if (details != null) {
      details.time = duration;
      _stepDetails.add(details);
    }
  }

  /// Generate a printable report specifying the average and maximum times
  /// spent stepping over different internal ink instruction types.
  /// This report type is primarily used to profile the ink engine itself
  /// rather than your own specific ink.
  String stepLengthReport() {
    final sb = StringBuffer()..writeln('TOTAL: ${_rootNode.totalMillisecs}ms');

    final byType = <String, List<_StepDetails>>{};
    for (final s in _stepDetails) {
      (byType[s.type] ??= []).add(s);
    }

    final averages = [
      for (final e in byType.entries)
        MapEntry(
          e.key,
          e.value.fold<double>(0, (a, d) => a + d.time) / e.value.length,
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    sb.writeln(
      'AVERAGE STEP TIMES: '
      '${averages.map((e) => '${e.key}: ${e.value}ms').join(', ')}',
    );

    final accumulated = [
      for (final e in byType.entries)
        MapEntry(
          '${e.key} (x${e.value.length})',
          e.value.fold<double>(0, (a, d) => a + d.time),
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    sb.writeln(
      'ACCUMULATED STEP TIMES: '
      '${accumulated.map((e) => '${e.key}: ${e.value}').join(', ')}',
    );

    return sb.toString();
  }

  /// Create a large log of all the internal instructions that were
  /// evaluated while profiling was active. Log is in a tab-separated
  /// format, for easy loading into a spreadsheet application.
  String megalog() {
    final sb = StringBuffer()..writeln('Step type\tDescription\tPath\tTime');

    for (final step in _stepDetails) {
      sb
        ..write(step.type)
        ..write('\t')
        ..write(step.obj.toString())
        ..write('\t')
        ..write(step.obj?.path)
        ..write('\t')
        ..writeln(step.time.toStringAsFixed(8));
    }

    return sb.toString();
  }

  /// Called by the story before it snapshots state for lookahead.
  void preSnapshot() {
    _snapWatch
      ..reset()
      ..start();
  }

  /// Called by the story after it snapshots state for lookahead.
  void postSnapshot() {
    _snapWatch.stop();
    _snapTotal += _millisecs(_snapWatch);
  }

  double _millisecs(Stopwatch watch) =>
      watch.elapsedTicks * 1000.0 / watch.frequency;

  /// Formats a duration as the reference does: seconds above a second,
  /// fewer decimals for longer times.
  static String formatMillisecs(double num) {
    if (num > 5000) {
      return '${_formatN(num / 1000.0, 1)} secs';
    }
    if (num > 1000) {
      return '${_formatN(num / 1000.0, 2)} secs';
    } else if (num > 100) {
      return '${_formatN(num, 0)} ms';
    } else if (num > 1) {
      return '${_formatN(num, 1)} ms';
    } else if (num > 0.01) {
      return '${_formatN(num, 3)} ms';
    } else {
      return '${_formatN(num, 2)} ms';
    }
  }

  /// .NET's "N" format under the invariant culture: grouped thousands.
  static String _formatN(double num, int decimals) {
    final fixed = num.abs().toStringAsFixed(decimals);
    final dot = fixed.indexOf('.');
    final whole = dot < 0 ? fixed : fixed.substring(0, dot);
    final frac = dot < 0 ? '' : fixed.substring(dot);
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    return '${num < 0 ? '-' : ''}$grouped$frac';
  }

  final Stopwatch _continueWatch = Stopwatch();
  final Stopwatch _stepWatch = Stopwatch();
  final Stopwatch _snapWatch = Stopwatch();

  double _continueTotal = 0;
  double _snapTotal = 0;
  double _stepTotal = 0;

  List<String>? _currStepStack;
  _StepDetails? _currStepDetails;
  final ProfileNode _rootNode;
  int _numContinues = 0;

  final List<_StepDetails> _stepDetails = [];
}

class _StepDetails {
  _StepDetails(this.type, this.obj);
  final String type;
  final InkObject? obj;
  double time = 0;
}
