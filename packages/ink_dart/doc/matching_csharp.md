ink_dart is checked against inkle's C# runtime, so a story plays the same
here as in Unity, Inky or inklecate: the same seed and choices give the same
text, tags, choices, errors and save files.

## Numbers

ink's numbers follow C#, not Dart or JavaScript:

- Integers are 32-bit and wrap around on overflow.
- Floats are 32-bit and print the way .NET does: `7 / 3.0` prints
  `2.3333333`, very small or large values use `E` notation (`1E-05`), and
  infinity prints `Infinity`.
- A float result stays a float even when it's whole (`1.5 * 2` is `3.0`,
  saved as `3.0`).

inkjs, the JavaScript port, uses 64-bit doubles and turns whole results into
integers, so a story can print different numbers there than in Unity.
ink_dart sides with Unity.

## Randomness

`RANDOM`, `LIST_RANDOM` and shuffles use .NET's seeded `System.Random`, as
the C# runtime does, so the same `storySeed` gives the same rolls and
shuffles as a Unity build. Set `story.state.storySeed` to fix the seed, for
example in tests.

## One difference

The C# runtime prints floats in the device's language settings (`2,5` in
some locales). ink_dart always prints the invariant form (`2.5`).

## How it's checked

Every release plays 176 stories (inkjs's test corpus, inkjs's integration
story, and cases written for the port) and compares each line, tag, choice,
error and save with what the C# runtime recorded. Each story is also
replayed through a save and load at every choice, and saves made by inkjs
are loaded too. A fuzzer plays thousands of random runs in both runtimes and
compares them.
