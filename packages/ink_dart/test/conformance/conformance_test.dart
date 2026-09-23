// Data-driven conformance suite: one test per <case>.golden.json under
// cases/. Regenerate goldens with `node tool/regen_goldens.mjs`.
//
// To skip a case, pass `skip:` with a comment naming the reference
// behaviour it waits on (see CLAUDE.md).

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'harness.dart';

void main() {
  final cases = ConformanceCase.discover(Directory('test/conformance/cases'));

  test('corpus is present', () {
    expect(cases, isNotEmpty);
  });

  group('transcript', () {
    for (final c in cases) {
      test(c.name, () {
        final mismatch = diff(c, replay(c));
        if (mismatch != null) fail(mismatch);
      });
    }
  });

  // At every choice point: toJson, a fresh Story, loadJson, and the reloaded
  // state must serialise the same and play on to the same transcript.
  group('save/load round trip', () {
    test('reloads happen', () {
      var reloads = 0;
      for (final c in cases) {
        reloads += replay(c, roundTrip: true).reloads;
      }
      expect(reloads, greaterThan(100));
    });

    for (final c in cases) {
      test(c.name, () {
        final mismatch = diff(c, replay(c, roundTrip: true));
        if (mismatch != null) fail(mismatch);
      });
    }
  });

  // Saves made by inkjs (tool/record_inkjs_saves.mjs), loaded into a fresh
  // story: Dart must do what the C# runtime does after loading the same
  // save, byte for byte. The second variant drops `previousRandom`, which
  // older inkjs versions left out of their saves.
  group('inkjs saves', () {
    final withSaves = [
      for (final c in cases)
        if (c.inkjsSave != null) c,
    ];

    test('saves are present', () {
      expect(withSaves.length, greaterThan(30));
    });

    for (final c in withSaves) {
      test(c.name, () {
        final save = c.inkjsSave ?? '';
        final mismatch = diffResumed(
          c,
          'fromInkjsSave',
          replayFromSave(c, save),
        );
        if (mismatch != null) fail(mismatch);
      });

      test('${c.name} (without previousRandom)', () {
        final save = jsonDecode(c.inkjsSave ?? '{}') as Map<String, Object?>
          ..remove('previousRandom');
        final mismatch = diffResumed(
          c,
          'fromInkjsSaveWithoutPreviousRandom',
          replayFromSave(c, jsonEncode(save)),
        );
        if (mismatch != null) fail(mismatch);
      });
    }
  });
}
