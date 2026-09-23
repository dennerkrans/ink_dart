# ink_dart

Pure Dart runtime for inkle's ink, ported structurally from inkle's C# runtime (with inkjs's names) and checked against it, plus Flutter widgets on top. The design is `docs/SPEC.md`; read it before changing the runtime.

## Status

0.1.0 of both packages is released (2026-09-23): [ink_dart](https://pub.dev/packages/ink_dart) and [flutter_ink](https://pub.dev/packages/flutter_ink) on pub.dev, GitHub release `v0.1.0`. All four planned phases are done: core flow, persistence and the game interface, lists and threads, multi-flow with the profiler and `flutter_ink`. Work from here is maintenance, new ink versions, and bugs that show up as conformance differences.

## Layout

- `packages/ink_dart`: the runtime. `lib/src/runtime/` (object model), `lib/src/state/`, `lib/src/json/`, `lib/src/story.dart`; tests in `test/unit/` and `test/conformance/`.
- `packages/flutter_ink`: `StoryController`, `StoryView`, `StoryDebugView`. It depends on `ink_dart` by version; `pubspec_overrides.yaml` points it at the local package for development.
- `tool/`: the conformance oracle (`tool/oracle`, C# over inkle's ink 1.2.1 DLLs), `tool/oracle_unit` (float and `Random` test data), `regen_goldens.mjs`, and the one-off vendoring scripts.
- No pub workspace: it would pull the Flutter SDK into ink_dart's own resolution.

## Rules

- **Structural port.** Keep the reference's class, method and field names (Dart casing), one file per class under `lib/src/`. The C# runtime in `inkle/ink` is the reference; inkjs is the second opinion. Never redesign; conformance depends on matching the reference's control flow.
- **Conformance decides.** A change is done when its goldens pass, not when it compiles. New behaviour gets a case first, recorded by the C# oracle; never hand-edit a golden.
- **Pure Dart.** No Flutter import anywhere in `packages/ink_dart`, and no runtime dependencies (`collection`, `meta` at most, if ever needed). No code generation, no reflection, no `!` sprinkled to silence null safety.
- **flutter_ink uses the public API only.** If it needs something internal, export it from ink_dart deliberately; never import `package:ink_dart/src/`.
- **Types.** `IntValue` and `FloatValue` stay distinct; follow ink's numeric promotion rules, not Dart's. Numbers follow the C# runtime, not inkjs: ints are 32-bit and wrap, `FloatValue` is 32-bit (round after every operation), a whole float result stays a float (inkjs turns it into an int), and floats print as .NET's shortest round-trip form under the invariant culture (`2.3333333`, `1E-05`, `Infinity`).
- **Equality.** Plain data types (`Path`, `Component`, `Pointer`, `InkListItem`, `InkList`) implement `==` and `hashCode`. Runtime objects (`InkObject` and its subclasses, values included) keep the reference's equality: identity, except `Divert`, which compares by target as in C#. Don't add `==` to a runtime class unless C# overrides `Equals` there; observers and path lookup depend on it. `toString` follows C#'s `ToString` too (the profiler's step log checks it).
- **Errors are data.** Collect into `state.currentErrors`, surface via `onError`; throw only when no handler is set. Error text uses C#'s wording.
- **Determinism.** The random source is .NET's seeded `new System.Random(seed)` (`lib/src/prng.dart`), not inkjs's `PRNG`. Every conformance case runs with a fixed seed.
- **Saves are C# saves.** `state.toJson()` must be byte-identical to the C# runtime's; the conformance suite checks it at every choice point and at the end.
- **Do not skip a failing golden.** A skipped test needs a comment naming the reference behaviour it waits on.

## Conformance

The oracle is the C# runtime, not inkjs. Regenerating goldens needs the .NET 10 SDK; running tests does not.

- A case is `<case>.ink` under `packages/ink_dart/test/conformance/cases/<phase>/<category>/`, plus an optional `<case>.script.json` of ops (see that folder's README). `node tool/regen_goldens.mjs [filter]` compiles it and records `<case>.json` and `<case>.golden.json`.
- The Dart suite replays each golden twice: straight through, and loading C#'s saved state into a fresh story at every choice point.
- Both drivers, `tool/oracle/Driver.cs` and `packages/ink_dart/test/conformance/harness.dart`, implement the same ops and events; change them together.
- Hand-written cases go in `*/ink-dart/` and say so in their first line. `.script.json` files are hand-written: re-vendoring must keep them.

## Releasing

1. Bump `version` in both pubspecs (flutter_ink's `ink_dart` constraint too, if the runtime changed) and add a `CHANGELOG.md` entry in each package.
2. CI green on `main`; `dart pub publish --dry-run` in `packages/ink_dart` clean; pana 160/160.
3. Publish ink_dart first (`cd packages/ink_dart && dart pub publish`), then flutter_ink (`cd packages/flutter_ink && flutter pub publish`). Publishing is permanent; the user runs both.
   Both packages belong to the verified publisher `daniel.party`. A new package must be transferred to it after its first upload (pub.dev: the package's Admin tab, then Transfer to publisher); new versions of an existing package stay with it.
4. A GitHub release tagged `vX.Y.Z` on `main` with both changelogs; draft it first, publish it once pub.dev has both packages.

## References

- ink (C#): https://github.com/inkle/ink (`ink-engine-runtime/`, the reference)
- inkjs: https://github.com/y-lohse/inkjs (`src/engine/`, names and a second opinion)
- Format doc (out of date, read for intent): https://github.com/inkle/ink/blob/master/Documentation/ink_JSON_runtime_format.md
- blade-ink (Java) and bladeink (Rust): second opinions in Dart-shaped languages

## Commands

```
cd packages/ink_dart
dart pub get
dart analyze
dart test                                  # unit, conformance, save/load round trip
dart test --compiler exe test/conformance  # AOT
dart run example/play.dart path/to/story.json
cd ../flutter_ink && flutter test
node tool/regen_goldens.mjs [filter]       # from the repo root; needs .NET 10
```
