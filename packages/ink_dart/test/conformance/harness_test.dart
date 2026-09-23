// Checks the harness itself, independent of the runtime.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'harness.dart';

void main() {
  group('jsonPath', () {
    test('equal trees match', () {
      expect(
        jsonPath(
          {
            'a': [1, 'x', null],
          },
          {
            'a': [1, 'x', null],
          },
          r'$',
        ),
        isNull,
      );
    });

    test('int and float differ', () {
      expect(
        jsonPath(jsonDecode('{"v":1}'), jsonDecode('{"v":1.0}'), r'$'),
        r'$.v',
      );
    });

    test('reports the first differing element', () {
      expect(jsonPath([1, 2, 3], [1, 5, 3], r'$'), r'$[1]');
      expect(jsonPath([1], [1, 2], r'$'), r'$.length');
      expect(jsonPath({'a': 1}, {'b': 1}, r'$'), r'$.a');
    });
  });

  test('golden replayed against itself has no diff', () {
    final c = ConformanceCase(
      File('test/conformance/cases/phase1/misc/hello_world.golden.json'),
    );
    expect(diff(c, Replay(c.events, c.finalState)), isNull);
  });

  test('every golden has its compiled story beside it', () {
    for (final c in ConformanceCase.discover(
      Directory('test/conformance/cases'),
    )) {
      expect(c.storyJson, startsWith('{"inkVersion":'), reason: c.name);
    }
  });
}
