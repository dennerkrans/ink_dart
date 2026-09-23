// Data-driven conformance suite: one test per <case>.golden.json under
// cases/. Regenerate goldens with `node tool/regen_goldens.mjs`.
//
// To skip a case, pass `skip:` with a comment naming the reference
// behaviour it waits on (see CLAUDE.md).

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
}
