import 'dart:convert';
import 'dart:io';

import 'package:ink_dart/ink_dart.dart';
import 'package:test/test.dart';

void main() {
  test('Story(Map) from jsonDecode reads float literals as floats', () {
    const base = 'test/conformance/cases/phase1/evaluation/arithmetic';
    final golden =
        jsonDecode(File('$base.golden.json').readAsStringSync())
            as Map<String, Object?>;
    final expected = [
      for (final e in (golden['events'] as List).cast<Map<String, Object?>>())
        if (e['type'] == 'line') e['text'],
    ].join();

    final json =
        jsonDecode(File('$base.json').readAsStringSync())
            as Map<String, Object?>;
    final story = Story(json)..state.storySeed = golden['seed'] as int;

    expect(story.continueMaximally(), expected);
  });
}
