// Data-driven conformance suite: one test per <case>.golden.json under
// cases/. Regenerate goldens with `node tool/regen_goldens.mjs`.

import 'dart:io';

import 'package:test/test.dart';

import 'harness.dart';

/// Phases whose runtime is not ported yet, and the reference behaviour each
/// waits on.
const _waitingOn = {
  3:
      'phase 3: InkList/ListDefinition and thread/done with choice-thread '
      'restore (inkjs InkList.ts, CallStack.ts Thread)',
  4: 'phase 4: multi-flow SwitchFlow/RemoveFlow (inkjs StoryState.ts flows)',
};

void main() {
  final cases = ConformanceCase.discover(Directory('test/conformance/cases'));

  test('corpus is present', () {
    expect(cases, isNotEmpty);
  });

  for (final c in cases) {
    test(c.name, () {
      final mismatch = diff(c, replay(c));
      if (mismatch != null) fail(mismatch);
    }, skip: _waitingOn[c.phase]);
  }
}
