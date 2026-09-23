// Port of the C# ink runtime's random source. The C# runtime (Story.cs,
// StoryState.cs) calls `new System.Random(seed).Next()`; inkjs's PRNG.ts is
// a different generator and is not the target (see CLAUDE.md, Determinism).
//
// A seeded System.Random in .NET uses the legacy Knuth subtractive generator
// (dotnet/runtime Random.Net5CompatImpl.cs, Net5CompatSeedImpl), unchanged
// since .NET Framework so seeded sequences stay stable. This is that
// generator, with every value kept in C#'s 32-bit int range.

const int _int32Max = 0x7fffffff;
const int _int32Min = -0x80000000;
const int _mseed = 161803398;

// C# int arithmetic is unchecked: it wraps at 32 bits, and the seeding
// loops rely on that for large seeds.
int _add(int a, int b) => (a + b).toSigned(32);
int _sub(int a, int b) => (a - b).toSigned(32);

/// Seeded pseudo-random generator matching .NET's `new System.Random(seed)`.
class PRNG {
  /// Mirrors `new System.Random(seed)`.
  ///
  /// [seed] is reduced to a 32-bit signed int first, as a C# `int` would
  /// hold it after unchecked arithmetic such as
  /// `state.storySeed + state.previousRandom`.
  PRNG(int seed) {
    final seed32 = seed.toSigned(32);
    final subtraction = seed32 == _int32Min ? _int32Max : seed32.abs();
    var mj = _sub(_mseed, subtraction);
    _seedArray[55] = mj;
    var mk = 1;
    var ii = 0;
    for (var i = 1; i < 55; i++) {
      ii += 21;
      if (ii >= 55) ii -= 55;
      _seedArray[ii] = mk;
      mk = _sub(mj, mk);
      if (mk < 0) mk = _add(mk, _int32Max);
      mj = _seedArray[ii];
    }
    for (var k = 1; k < 5; k++) {
      for (var i = 1; i < 56; i++) {
        var n = i + 30;
        if (n >= 55) n -= 55;
        var v = _sub(_seedArray[i], _seedArray[1 + n]);
        if (v < 0) v = _add(v, _int32Max);
        _seedArray[i] = v;
      }
    }
  }

  final List<int> _seedArray = List<int>.filled(56, 0);
  int _inext = 0;
  int _inextp = 21;

  /// Mirrors `System.Random.Next()`: a value in `[0, int.MaxValue)`.
  ///
  /// The only Random call the C# ink runtime makes: `RANDOM`, `LIST_RANDOM`,
  /// shuffle sequences and the default story seed all use it.
  int next() {
    var locINext = _inext + 1;
    if (locINext >= 56) locINext = 1;
    var locINextp = _inextp + 1;
    if (locINextp >= 56) locINextp = 1;

    var retVal = _sub(_seedArray[locINext], _seedArray[locINextp]);
    if (retVal == _int32Max) retVal--;
    if (retVal < 0) retVal = _add(retVal, _int32Max);

    _seedArray[locINext] = retVal;
    _inext = locINext;
    _inextp = locINextp;
    return retVal;
  }
}
