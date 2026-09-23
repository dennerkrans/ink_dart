// PRNG against .NET's `new System.Random(seed).Next()`; data recorded by
// tool/oracle_unit.

import 'dart:convert';
import 'dart:io';

import 'package:ink_dart/src/prng.dart';
import 'package:test/test.dart';

void main() {
  final data =
      jsonDecode(File('test/unit/prng_cases.json').readAsStringSync())
          as Map<String, Object?>;
  final cases = (data['cases'] as List).cast<Map<String, Object?>>();

  for (final c in cases) {
    final seed = c['seed'] as int;
    test('seed $seed', () {
      final prng = PRNG(seed);
      final expected = (c['next'] as List).cast<int>();
      expect([for (var i = 0; i < expected.length; i++) prng.next()], expected);
    });
  }

  test('seed wraps like a C# int', () {
    final wrapped = PRNG(0x7fffffff + 5);
    final direct = PRNG(-0x80000000 + 4);
    expect(wrapped.next(), direct.next());
  });
}
