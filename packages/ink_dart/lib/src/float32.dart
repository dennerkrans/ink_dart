// 32-bit float support. The C# ink runtime stores FloatValue as a C# `float`
// and formats and parses it with .NET's rules; Dart only has 64-bit doubles,
// so these helpers reproduce the C# behaviour on top of them.
//
// Formatting matches .NET 10 under the invariant culture, which is what the
// conformance oracle runs with. Note that C# ink formats output text with the
// *current* culture (Value<T>.ToString() calls value.ToString()), so a C# game
// on a machine whose culture writes `2,5` or `∞` prints those; the invariant
// form is the one this port targets.

import 'dart:typed_data';

final Float32List _f32 = Float32List(1);
final Uint32List _f32Bits = _f32.buffer.asUint32List();

/// Rounds [v] to the nearest IEEE 754 single-precision value (ties to even),
/// as a C# `(float)` cast does.
double toFloat32(double v) {
  _f32[0] = v;
  return _f32[0];
}

double _fromBits(int bits) {
  _f32Bits[0] = bits;
  return _f32[0];
}

int _bitsOf(double f) {
  _f32[0] = f;
  return _f32Bits[0];
}

/// Formats [v] (rounded to float32) as .NET 10's
/// `float.ToString(CultureInfo.InvariantCulture)` does: the shortest digits
/// that round-trip, fixed notation for decimal exponents -5 < e < 9 and
/// scientific otherwise (`1E-05`, `1.5E+09`), `-0`, `Infinity`, `-Infinity`,
/// `NaN`.
String formatFloat32(double v) {
  final f = toFloat32(v);
  if (f.isNaN) return 'NaN';
  if (f.isInfinite) return f > 0 ? 'Infinity' : '-Infinity';
  final sign = f.isNegative ? '-' : '';
  if (f == 0) return '${sign}0';

  final magnitude = f.abs();
  var exponential = magnitude.toStringAsExponential(8);
  for (var precision = 1; precision < 9; precision++) {
    final candidate = magnitude.toStringAsExponential(precision - 1);
    if (toFloat32(double.parse(candidate)) == magnitude) {
      exponential = candidate;
      break;
    }
  }

  final ePos = exponential.indexOf('e');
  var digits = exponential.substring(0, ePos).replaceFirst('.', '');
  var exponent = int.parse(exponential.substring(ePos + 1));
  (digits, exponent) = _breakTieToEven(magnitude, digits, exponent);
  digits = digits.replaceFirst(RegExp(r'0+$'), '');

  if (exponent >= 9 || exponent < -4) {
    final rest = digits.length > 1 ? '.${digits.substring(1)}' : '';
    final expSign = exponent < 0 ? '-' : '+';
    final expDigits = exponent.abs().toString().padLeft(2, '0');
    return '$sign${digits[0]}${rest}E$expSign$expDigits';
  }
  if (exponent < 0) {
    return '${sign}0.${'0' * (-exponent - 1)}$digits';
  }
  final intLength = exponent + 1;
  if (digits.length <= intLength) {
    return '$sign${digits.padRight(intLength, '0')}';
  }
  return '$sign${digits.substring(0, intLength)}.${digits.substring(intLength)}';
}

/// Dart rounds a tie in the last digit away from zero (`1592845.25` →
/// `1592845.3`); .NET picks the even digit (`1592845.2`). When [magnitude]
/// lies exactly halfway between two candidates with as many digits as
/// [digits] (first digit at 10^[exponent]), return the even one if it too
/// round-trips.
(String, int) _breakTieToEven(double magnitude, String digits, int exponent) {
  final last = digits.codeUnitAt(digits.length - 1) - 0x30;
  if (last.isEven) return (digits, exponent);
  final scale = exponent - digits.length + 1;
  final n = BigInt.parse(digits);
  final two = BigInt.two;
  for (final (neighbour, halfway) in [
    (n - BigInt.one, n * two - BigInt.one),
    (n + BigInt.one, n * two + BigInt.one),
  ]) {
    // magnitude == halfway / 2 × 10^scale, i.e. 2 × magnitude == halfway × 10^scale.
    if (_compareDecimalToDouble(halfway, scale, magnitude * 2) != 0) continue;
    var text = neighbour.toString();
    var e = exponent;
    if (text.length > digits.length) {
      e++;
      text = text.substring(0, digits.length);
    }
    final candidate = double.parse('${text}e${e - text.length + 1}');
    if (toFloat32(candidate) == magnitude) return (text, e);
  }
  return (digits, exponent);
}

/// Writes [v] as ink's C# `SimpleJson.Writer.Write(float)` does: the
/// [formatFloat32] text, with `.0` appended when it has neither `.` nor `E`
/// (so it reads back as a float), `3.4E+38` / `-3.4E+38` for infinities and
/// `0.0` for NaN.
String writeJsonFloat32(double v) {
  final text = formatFloat32(v);
  switch (text) {
    case 'Infinity':
      return '3.4E+38';
    case '-Infinity':
      return '-3.4E+38';
    case 'NaN':
      return '0.0';
  }
  if (!text.contains('.') && !text.contains('E')) return '$text.0';
  return text;
}

final RegExp _floatSyntax = RegExp(
  r'^[\t\n\v\f\r ]*([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?'
  r'[\t\n\v\f\r ]*$',
);
final RegExp _namedSyntax = RegExp(
  r'^[\t\n\v\f\r ]*([+-]?)(infinity|nan)[\t\n\v\f\r ]*$',
  caseSensitive: false,
);

/// Parses [text] as .NET 10's `float.TryParse(text, NumberStyles.Float,
/// CultureInfo.InvariantCulture, out f)` does, or returns null where it
/// fails. The C# runtime uses this for string-to-float casts (Value.cs) and
/// for float tokens in JSON (SimpleJson.cs).
///
/// Accepts surrounding whitespace, a sign, `5.`, `.5`, an exponent, and
/// `Infinity` / `NaN` in any case; rejects thousands separators, hex and
/// non-ASCII digits. Out-of-range values become ±Infinity. Rounding is
/// correct to float32 (no double-rounding error).
double? parseFloat32(String text) {
  final named = _namedSyntax.firstMatch(text);
  if (named != null) {
    final negative = named.group(1) == '-';
    if ((named.group(2) ?? '').toLowerCase() == 'nan') return double.nan;
    return negative ? double.negativeInfinity : double.infinity;
  }

  final m = _floatSyntax.firstMatch(text);
  if (m == null) return null;
  final negative = m.group(1) == '-';
  final intDigits = m.group(2) ?? '';
  final fracDigits = m.group(3) ?? m.group(4) ?? '';
  final expText = m.group(5);

  final allDigits = '$intDigits$fracDigits'.replaceFirst(RegExp(r'^0+'), '');
  if (allDigits.isEmpty) return negative ? -0.0 : 0.0;

  // Clamp the exponent: beyond this the result is 0 or infinity anyway.
  var exp10 = expText == null ? 0 : _clampedExponent(expText);
  exp10 -= fracDigits.length;

  final approx = double.parse('${allDigits}e$exp10');
  final magnitude = _roundToFloat32(approx, BigInt.parse(allDigits), exp10);
  return negative ? -magnitude : magnitude;
}

int _clampedExponent(String text) {
  final negative = text.startsWith('-');
  final digits = text.replaceFirst(RegExp(r'^[+-]'), '');
  final trimmed = digits.replaceFirst(RegExp(r'^0+'), '');
  final value = trimmed.length > 6 ? 1000000 : int.parse('0$trimmed');
  return negative ? -value : value;
}

/// Rounds the decimal `digits × 10^exp10` (≥ 0), approximated by the double
/// [approx], to float32. Double-then-float rounding is only wrong when
/// [approx] lands exactly on a float32 midpoint; then compare exactly.
double _roundToFloat32(double approx, BigInt digits, int exp10) {
  final f = toFloat32(approx);
  if (f == approx || approx.isInfinite) return f;

  final double lo;
  final double hi;
  if (f > approx) {
    hi = f;
    lo = _fromBits(_bitsOf(f) - 1);
  } else {
    lo = f;
    hi = _fromBits(_bitsOf(f) + 1);
  }
  // Midpoint between the largest float and "the next one up" (infinity).
  final mid = hi.isInfinite
      ? lo + 10141204801825835211973625643008.0
      : (lo + hi) / 2;
  if (approx != mid) return f;

  final c = _compareDecimalToDouble(digits, exp10, mid);
  if (c > 0) return hi;
  if (c < 0) return lo;
  return f;
}

/// Sign of `digits × 10^exp10 − d` for a finite non-negative double [d].
int _compareDecimalToDouble(BigInt digits, int exp10, double d) {
  final bytes = ByteData(8)..setFloat64(0, d);
  final bits = bytes.getUint64(0);
  final biased = (bits >> 52) & 0x7ff;
  final fraction = bits & 0xfffffffffffff;
  final mantissa = BigInt.from(biased == 0 ? fraction : fraction | (1 << 52));
  final exp2 = (biased == 0 ? 1 : biased) - 1075;

  var left = digits;
  var right = mantissa;
  if (exp10 >= 0) {
    left *= BigInt.from(10).pow(exp10);
  } else {
    right *= BigInt.from(10).pow(-exp10);
  }
  if (exp2 >= 0) {
    right <<= exp2;
  } else {
    left <<= -exp2;
  }
  return left.compareTo(right);
}
