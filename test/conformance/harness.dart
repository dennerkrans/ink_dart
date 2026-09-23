// Replays a conformance case against the Dart runtime and diffs the result
// against the golden that tool/oracle recorded with the C# ink runtime.
//
// `Driver` mirrors tool/oracle/Driver.cs op for op and event for event;
// keep the two in sync.

import 'dart:convert';
import 'dart:io';

import 'package:ink_dart/ink_dart.dart';
import 'package:ink_dart/src/float32.dart';

/// Same guards as tool/oracle/Program.cs.
const maxContinues = 1000;
const maxChoices = 100;

const _errorKinds = {
  ErrorType.author: 'author',
  ErrorType.warning: 'warning',
  ErrorType.error: 'error',
};

/// One case: `<case>.json` (compiled story) and `<case>.golden.json`.
class ConformanceCase {
  ConformanceCase(this.goldenFile);

  final File goldenFile;

  late final Map<String, Object?> golden =
      jsonDecode(goldenFile.readAsStringSync()) as Map<String, Object?>;

  String get name => golden['case'] as String;

  int get phase => int.parse(name.split('/').first.substring('phase'.length));

  int get seed => golden['seed'] as int;

  List<Map<String, Object?>> get events =>
      (golden['events'] as List).cast<Map<String, Object?>>();

  String? get finalState => golden['finalState'] as String?;

  String get storyJson => File(
    goldenFile.path.replaceFirst(RegExp(r'\.golden\.json$'), '.json'),
  ).readAsStringSync();

  /// The op script the oracle ran, if any.
  List<Map<String, Object?>> get script => [
    ...((golden['script'] as List?) ?? const []).cast<Map<String, Object?>>(),
  ];

  static List<ConformanceCase> discover(Directory dir) {
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.golden.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return [for (final f in files) ConformanceCase(f)];
  }
}

/// What the Dart runtime did with a case.
class Replay {
  Replay(this.events, this.finalState, {this.reloads = 0});

  final List<Map<String, Object?>> events;
  final String? finalState;

  /// Round-trip mode: how many times a reloaded story took over.
  final int reloads;
}

Replay replay(ConformanceCase c, {bool roundTrip = false}) =>
    Driver(c, roundTrip: roundTrip).play();

/// Plays a case: the golden's op script, then the default loop (continue to
/// the next choice, take the first, repeat).
///
/// Every choice point in the default loop records a `checkpoint` with the
/// save JSON. With [roundTrip], the oracle's checkpoint JSON is then loaded
/// into a fresh [Story], which carries on; the transcript must not change.
class Driver {
  Driver(this.c, {this.roundTrip = false});

  final ConformanceCase c;
  final bool roundTrip;

  /// How many times round-trip mode swapped in a reloaded story.
  int reloads = 0;

  final List<Map<String, Object?>> _events = [];
  final Map<String, String> _slots = {};

  /// Ops that configure a story rather than drive it; replayed on the fresh
  /// story in round-trip mode.
  final List<Map<String, Object?>> _configOps = [];

  late Story _story;
  int _checkpoints = 0;

  void _record(Map<String, Object?> e) => _events.add(e);

  Replay play() {
    final Story story;
    try {
      story = _newStory();
    } catch (e) {
      _record({'type': 'exception', 'message': '$e'});
      return Replay(_events, null);
    }
    _story = story;
    _story.state.storySeed = c.seed;

    var continues = 0;
    var choicesMade = 0;
    try {
      _record({'type': 'globalTags', 'tags': _story.globalTags ?? <String>[]});

      for (final op in c.script) {
        try {
          continues = _runOp(op, continues);
        } catch (e) {
          _record({'type': 'exception', 'message': '$e'});
        }
      }

      outer:
      for (;;) {
        while (_story.canContinue) {
          if (continues++ >= maxContinues) {
            _record({'type': 'truncated', 'reason': 'maxContinues'});
            break outer;
          }
          _continueOnce();
        }
        if (_story.currentChoices.isEmpty) {
          _record({'type': 'end'});
          break;
        }
        _recordChoices();
        if (choicesMade >= maxChoices) {
          _record({'type': 'truncated', 'reason': 'maxChoices'});
          break;
        }
        choicesMade++;
        final saved = _story.state.toJson();
        _record({'type': 'checkpoint', 'state': saved});
        if (roundTrip) _swapForReloadedStory(_checkpoints++);
        _choose(0);
      }
    } catch (e) {
      _record({'type': 'exception', 'message': '$e'});
    }
    String? finalState;
    try {
      finalState = _story.state.toJson();
    } catch (e) {
      finalState = null;
    }
    return Replay(_events, finalState, reloads: reloads);
  }

  Story _newStory() {
    final story = Story.fromJson(c.storyJson);
    story.onError = (message, type) {
      _record({'type': _errorKinds[type], 'message': message});
    };
    return story;
  }

  /// Loads the oracle's save from the [n]th checkpoint (C#'s bytes, not
  /// ours) into a fresh story and carries on there.
  void _swapForReloadedStory(int n) {
    final goldenCheckpoints = [
      for (final e in c.events)
        if (e['type'] == 'checkpoint') e['state'] as String,
    ];
    final saved = n < goldenCheckpoints.length
        ? goldenCheckpoints[n]
        : _story.state.toJson();
    final fresh = _newStory();
    final previous = _story;
    _story = fresh;
    for (final op in _configOps) {
      _runOp(op, 0, replaying: true);
    }
    fresh.state.loadJson(saved);
    reloads++;
    final reloaded = fresh.state.toJson();
    final where = jsonPath(jsonDecode(saved), jsonDecode(reloaded), r'$');
    if (where != null) {
      _story = previous;
      _record({'type': 'roundTripMismatch', 'at': where});
    }
  }

  void _continueOnce() {
    final text = _story.continueStory();
    _record({
      'type': 'line',
      'text': text,
      'tags': [..._story.currentTags],
    });
  }

  void _recordChoices() {
    _record({
      'type': 'choices',
      'choices': [
        for (final ch in _story.currentChoices)
          {'index': ch.index, 'text': ch.text, 'tags': ch.tags ?? <String>[]},
      ],
    });
  }

  void _choose(int index) {
    _record({'type': 'choose', 'index': index});
    _story.chooseChoiceIndex(index);
  }

  /// Returns the updated continue count.
  int _runOp(Map<String, Object?> op, int continues, {bool replaying = false}) {
    final name = op['op'] as String;
    switch (name) {
      case 'continue':
        continues++;
        _continueOnce();
      case 'continueMaximally':
        while (_story.canContinue && continues++ < maxContinues) {
          _continueOnce();
        }
      case 'choose':
        _recordChoices();
        _choose(op['index'] as int);
      case 'choosePathString':
        _story.choosePathString(
          op['path'] as String,
          resetCallstack: (op['resetCallstack'] as bool?) ?? true,
          arguments: _args(op),
        );
      case 'evaluateFunction':
        final fn = op['name'] as String;
        final r = _story.evaluateFunctionWithOutput(fn, _args(op));
        _record({
          'type': 'function',
          'name': fn,
          'result': encodeValue(r.result),
          'output': r.textOutput,
        });
      case 'setVariable':
        _story.variablesState[op['name'] as String] = decodeValue(op['value']);
      case 'getVariable':
        _record({
          'type': 'variable',
          'name': op['name'],
          'value': encodeValue(_story.variablesState[op['name'] as String]),
        });
      case 'variableNames':
        _record({
          'type': 'variableNames',
          'names': [..._story.variablesState],
        });
      case 'observe':
        if (!replaying) _configOps.add(op);
        _story.observeVariable(op['name'] as String, (varName, value) {
          _record({
            'type': 'observed',
            'name': varName,
            'value': encodeValue(value),
          });
        });
      case 'bind':
        if (!replaying) _configOps.add(op);
        _bind(op);
      case 'unbind':
        if (!replaying) _configOps.add(op);
        _story.unbindExternalFunction(op['name'] as String);
      case 'allowExternalFunctionFallbacks':
        if (!replaying) _configOps.add(op);
        _story.allowExternalFunctionFallbacks = op['value'] as bool;
      case 'save':
        _slots[(op['slot'] as String?) ?? ''] = _story.state.toJson();
      case 'load':
        final saved = _slots[(op['slot'] as String?) ?? ''];
        if (saved == null) throw StateError('nothing saved in slot');
        _story.state.loadJson(saved);
      case 'resetState':
        // resetState seeds from the clock; keep the case deterministic.
        _story.resetState();
        _story.state.storySeed = c.seed;
      case 'freshStory':
        // A new Story from the same JSON, as a game would make on relaunch.
        _story = _newStory()..state.storySeed = c.seed;
      case 'currentText':
        _record({'type': 'currentText', 'text': _story.currentText});
      case 'currentChoices':
        _recordChoices();
      case 'switchFlow':
        _story.switchFlow(op['name'] as String);
      case 'removeFlow':
        _story.removeFlow(op['name'] as String);
      case 'switchToDefaultFlow':
        _story.switchToDefaultFlow();
      case 'visitCount':
        _record({
          'type': 'visitCount',
          'path': op['path'],
          'count': _story.state.visitCountAtPathString(op['path'] as String),
        });
      case 'tagsForContentAtPath':
        _record({
          'type': 'tags',
          'path': op['path'],
          'tags':
              _story.tagsForContentAtPath(op['path'] as String) ?? <String>[],
        });
      default:
        throw StateError('unknown script op: $name');
    }
    return continues;
  }

  /// External function behaviours, as in tool/oracle/Driver.cs.
  void _bind(Map<String, Object?> op) {
    final fn = op['name'] as String;
    final behaviour = (op['behaviour'] as String?) ?? 'record';
    _story.bindExternalFunctionGeneral(fn, (args) {
      _record({
        'type': 'external',
        'name': fn,
        'args': [for (final a in args) encodeValue(a)],
      });
      switch (behaviour) {
        case 'record':
          return null;
        case 'return':
          return decodeValue(op['value']);
        case 'multiply':
          // Float if either side is.
          final x = args[0];
          final y = args[1];
          if (x is int && y is int) return (x * y).toSigned(32);
          return toFloat32((x as num).toDouble() * (y as num).toDouble());
        case 'repeat':
          return (args[1] as String) * (args[0] as int);
        case 'callInk':
          // Increment the argument, then hand it to an ink function.
          return _story.evaluateFunction(op['function'] as String, [
            (args[0] as int) + 1,
          ]);
        default:
          throw StateError('unknown external behaviour: $behaviour');
      }
    }, lookaheadSafe: (op['lookaheadSafe'] as bool?) ?? false);
  }

  static List<Object?> _args(Map<String, Object?> op) => [
    for (final a in (op['args'] as List?) ?? const []) decodeValue(a),
  ];
}

/// Values cross the script and the golden as `{"int": 5}`,
/// `{"float": "2.5"}`, `{"string": "x"}`, `{"bool": true}`,
/// `{"list": "a, b"}`, or null.
Object? encodeValue(Object? value) => switch (value) {
  null => null,
  final int i => {'int': i},
  final double f => {'float': formatFloat32(f)},
  final bool b => {'bool': b},
  final String s => {'string': s},
  final InkList l => {'list': l.toString()},
  _ => {'unknown': value.runtimeType.toString()},
};

Object? decodeValue(Object? node) {
  if (node == null) return null;
  final o = node as Map<String, Object?>;
  if (o['int'] != null) return o['int'];
  if (o['float'] != null) return parseFloat32(o['float'] as String);
  if (o['bool'] != null) return o['bool'];
  if (o['string'] != null) return o['string'];
  throw StateError('cannot decode script value: $node');
}

/// Returns a readable description of the first divergence, or null when
/// [actual] matches the golden.
String? diff(ConformanceCase c, Replay actual) {
  final expected = c.events;
  final n = expected.length < actual.events.length
      ? expected.length
      : actual.events.length;
  for (var i = 0; i < n; i++) {
    final where = jsonPath(expected[i], actual.events[i], '');
    if (where != null) {
      return _eventMismatch(c, i, expected, actual.events, where);
    }
  }
  if (expected.length != actual.events.length) {
    return _eventMismatch(c, n, expected, actual.events, '');
  }

  final expectedState = c.finalState;
  final actualState = actual.finalState;
  if (expectedState == null || actualState == null) {
    if (expectedState == actualState) return null;
    return '${c.name}: final state\n'
        '  expected: $expectedState\n'
        '  actual:   $actualState';
  }
  final e = jsonDecode(expectedState);
  final a = jsonDecode(actualState);
  final where = jsonPath(e, a, r'$');
  if (where == null) {
    // Same structure; saves must also be byte-identical, so that a Dart
    // save is a C# save.
    if (expectedState == actualState) return null;
    return '${c.name}: final state has the same structure but different '
        'bytes\n'
        '  expected: $expectedState\n'
        '  actual:   $actualState';
  }
  return '${c.name}: final state differs at $where\n'
      '  expected: ${_at(e, where)}\n'
      '  actual:   ${_at(a, where)}';
}

String _eventMismatch(
  ConformanceCase c,
  int i,
  List<Map<String, Object?>> expected,
  List<Map<String, Object?>> actual,
  String where,
) {
  final e = i < expected.length ? expected[i] : null;
  final a = i < actual.length ? actual[i] : null;
  if (e?['type'] == 'checkpoint' && a?['type'] == 'checkpoint') {
    final es = e?['state'] as String;
    final as_ = a?['state'] as String;
    final at = jsonPath(jsonDecode(es), jsonDecode(as_), r'$');
    return '${c.name}: checkpoint at event $i differs'
        '${at == null ? ' in bytes only' : ' at $at'}\n'
        '  expected: $es\n'
        '  actual:   $as_';
  }
  String show(List<Map<String, Object?>> events) =>
      i < events.length ? jsonEncode(events[i]) : '(no event)';
  final context = [
    for (var j = i - 3 < 0 ? 0 : i - 3; j < i; j++)
      '    [$j] ${jsonEncode(expected[j])}',
  ];
  return [
    '${c.name}: event $i differs${where.isEmpty ? '' : ' at $where'}',
    if (context.isNotEmpty) '  preceded by:',
    ...context,
    '  expected: ${show(expected)}',
    '  actual:   ${show(actual)}',
  ].join('\n');
}

/// Path of the first difference between two decoded JSON values, or null.
///
/// Numbers compare by type as well as value: `1` and `1.0` differ, because
/// ink's IntValue and FloatValue do.
String? jsonPath(Object? expected, Object? actual, String path) {
  if (expected is Map && actual is Map) {
    final keys = {...expected.keys, ...actual.keys};
    for (final k in keys) {
      if (!expected.containsKey(k) || !actual.containsKey(k)) return '$path.$k';
      final d = jsonPath(expected[k], actual[k], '$path.$k');
      if (d != null) return d;
    }
    return null;
  }
  if (expected is List && actual is List) {
    for (var i = 0; i < expected.length && i < actual.length; i++) {
      final d = jsonPath(expected[i], actual[i], '$path[$i]');
      if (d != null) return d;
    }
    return expected.length == actual.length ? null : '$path.length';
  }
  if (expected.runtimeType != actual.runtimeType || expected != actual) {
    return path.isEmpty ? r'$' : path;
  }
  return null;
}

String _at(Object? root, String path) {
  Object? node = root;
  final steps = RegExp(r'\.([^.\[]+)|\[(\d+)\]').allMatches(path);
  for (final m in steps) {
    final key = m.group(1);
    final index = m.group(2);
    if (key == 'length') break;
    if (node is Map && key != null) {
      node = node[key];
    } else if (node is List && index != null) {
      final i = int.parse(index);
      node = i < node.length ? node[i] : null;
    } else {
      node = null;
    }
  }
  return jsonEncode(node);
}
