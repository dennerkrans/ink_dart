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

  for (final c in cases) {
    test(c.name, () {
      final mismatch = diff(c, replay(c));
      if (mismatch != null) fail(mismatch);
    });
  }
}
