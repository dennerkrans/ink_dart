// float32 helpers against .NET 10 and ink's C# SimpleJson; data recorded by
// tool/oracle_unit.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ink_dart/src/float32.dart';
import 'package:test/test.dart';

double fromBits(int bits) {
  final b = ByteData(4)..setInt32(0, bits);
  return b.getFloat32(0);
}

int bitsOf(double f) {
  final b = ByteData(4)..setFloat32(0, f);
  return b.getInt32(0);
}

void main() {
  final data =
      jsonDecode(File('test/unit/float32_cases.json').readAsStringSync())
          as Map<String, Object?>;
  final format = (data['format'] as List).cast<Map<String, Object?>>();
  final parse = (data['parse'] as List).cast<Map<String, Object?>>();

  test('toFloat32 rounds to single precision', () {
    expect(toFloat32(0.1), fromBits(1036831949));
    expect(toFloat32(1 / 3), fromBits(1051372203));
    expect(toFloat32(3.5e38), double.infinity);
    expect(toFloat32(1e-46), 0.0);
  });

  test('formatFloat32 matches float.ToString(InvariantCulture)', () {
    final mismatches = <String>[];
    for (final c in format) {
      final f = fromBits(c['bits'] as int);
      final actual = formatFloat32(f);
      if (actual != c['toString']) {
        mismatches.add(
          'bits ${c['bits']}: expected ${c['toString']}, got $actual',
        );
      }
    }
    expect(mismatches, isEmpty, reason: '${format.length} cases');
  });

  test('writeJsonFloat32 matches SimpleJson.Writer.Write(float)', () {
    final mismatches = <String>[];
    for (final c in format) {
      final f = fromBits(c['bits'] as int);
      final actual = writeJsonFloat32(f);
      if (actual != c['json']) {
        mismatches.add('bits ${c['bits']}: expected ${c['json']}, got $actual');
      }
    }
    expect(mismatches, isEmpty, reason: '${format.length} cases');
  });

  test('parseFloat32 matches float.TryParse(Float, InvariantCulture)', () {
    final mismatches = <String>[];
    for (final c in parse) {
      final input = c['input'] as String;
      final expected = c['bits'] as int?;
      final actual = parseFloat32(input);
      final actualBits = actual == null ? null : bitsOf(actual);
      // All NaNs are equal for our purposes; .NET yields the default NaN.
      final bothNaN =
          actual != null &&
          actual.isNaN &&
          expected != null &&
          fromBits(expected).isNaN;
      if (actualBits != expected && !bothNaN) {
        mismatches.add(
          '${jsonEncode(input)}: expected $expected, got $actualBits',
        );
      }
    }
    expect(mismatches, isEmpty, reason: '${parse.length} cases');
  });

  test('formatted text parses back to the same float', () {
    for (final c in format) {
      final f = fromBits(c['bits'] as int);
      if (f.isNaN) continue;
      final parsed = parseFloat32(formatFloat32(f));
      expect(parsed, isNotNull);
      if (parsed != null) expect(bitsOf(parsed), bitsOf(f), reason: '$f');
    }
  });
}
