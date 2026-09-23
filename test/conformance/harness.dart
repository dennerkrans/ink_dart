// Replays a conformance case against the Dart runtime and diffs the result
// against the golden that tool/oracle recorded with the C# ink runtime.
//
// The replay loop mirrors `Play` in tool/oracle/Program.cs step for step;
// keep the two in sync.

import 'dart:convert';
import 'dart:io';

import 'package:ink_dart/ink_dart.dart';

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

  /// The choice indices inkjs took, in order.
  List<int> get picks => [
    for (final e in events)
      if (e['type'] == 'choose') e['index'] as int,
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
  Replay(this.events, this.finalState);

  final List<Map<String, Object?>> events;
  final String? finalState;
}

Replay replay(ConformanceCase c) {
  final events = <Map<String, Object?>>[];
  void record(Map<String, Object?> e) => events.add(e);

  final Story story;
  try {
    story = Story.fromJson(c.storyJson);
  } catch (e) {
    record({'type': 'exception', 'message': '$e'});
    return Replay(events, null);
  }
  story.onError = (message, type) {
    record({'type': _errorKinds[type], 'message': message});
  };

  final picks = c.picks;
  var continues = 0;
  var choicesMade = 0;
  try {
    story.state.storySeed = c.seed;
    record({'type': 'globalTags', 'tags': story.globalTags ?? <String>[]});
    outer:
    for (;;) {
      while (story.canContinue) {
        if (continues++ >= maxContinues) {
          record({'type': 'truncated', 'reason': 'maxContinues'});
          break outer;
        }
        final text = story.continueStory();
        record({
          'type': 'line',
          'text': text,
          'tags': [...story.currentTags],
        });
      }
      final choices = story.currentChoices;
      if (choices.isEmpty) {
        record({'type': 'end'});
        break;
      }
      record({
        'type': 'choices',
        'choices': [
          for (final ch in choices)
            {'index': ch.index, 'text': ch.text, 'tags': ch.tags ?? <String>[]},
        ],
      });
      if (choicesMade >= maxChoices) {
        record({'type': 'truncated', 'reason': 'maxChoices'});
        break;
      }
      final index = choicesMade < picks.length ? picks[choicesMade] : 0;
      choicesMade++;
      record({'type': 'choose', 'index': index});
      story.chooseChoiceIndex(index);
    }
  } catch (e) {
    record({'type': 'exception', 'message': '$e'});
  }
  String? finalState;
  try {
    finalState = story.state.toJson();
  } catch (e) {
    finalState = null;
  }
  return Replay(events, finalState);
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
  if (where == null) return null;
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
