# ink_dart

Pure Dart runtime for inkle's ink, ported structurally from inkjs. The full spec is `docs/SPEC.md`; read it before any code.

## Rules

- **Structural port.** Keep inkjs's class, method and field names (Dart casing). One file per class under `lib/src/`. When inkjs is unclear, the C# runtime in `inkle/ink` decides. Never redesign; conformance depends on matching the reference's control flow.
- **Conformance first.** No runtime class is written until the golden harness in `test/conformance/` runs end to end against at least one story. A feature is done when its goldens pass, not when it compiles.
- **Pure Dart.** No Flutter import anywhere in `packages/ink_dart`. Dependencies: `collection`, `meta` at most. No code generation, no reflection, no `!` sprinkled to silence null safety.
- **Types.** `IntValue` and `FloatValue` stay distinct; follow ink's numeric promotion rules, not Dart's. Numbers follow the C# runtime, not inkjs: `FloatValue` is 32-bit (round after every operation), a whole float result stays a float (inkjs turns it into an int), and floats print as .NET's shortest round-trip form under the invariant culture (`2.3333333`, `1E-05`, `Infinity`).
- **Equality.** Plain data types (`Path`, `Component`, `Pointer`, `InkListItem`, `InkList`) implement `==` and `hashCode`. Runtime objects (`InkObject` and its subclasses, values included) keep the reference's equality: identity, except `Divert`, which compares by target as in C#. Don't add `==` to a runtime class unless C# overrides `Equals` there; observers and path lookup depend on it.
- **Errors are data.** Collect into `state.currentErrors`, surface via `onError`; throw only when no handler is set.
- **Determinism.** Port the C# runtime's random source exactly: `new System.Random(seed)`, .NET's seeded (Knuth subtractive) generator, not inkjs's `PRNG`. Every conformance case runs with a fixed seed.
- **Do not skip a failing golden.** A skipped test needs a comment naming the reference behaviour it waits on.

## Phase 0: the harness (do this before anything else)

The oracle is the C# reference runtime (ink 1.2.1, DLLs in `tool/oracle/lib/`), not inkjs; regenerating goldens needs the .NET 10 SDK, running tests does not. inkjs (`tool/`, `npm ci`) is used only for vendoring and, later, cross-runtime save tests.

1. `npm install inkjs` in `tool/`; `tool/vendor_cases.mjs` uses its compiler to sort stories by phase.
2. Vendor inkjs's `.ink` test stories into `test/conformance/cases/`, grouped by phase.
3. `tool/regen_goldens.mjs` runs `tool/oracle` (C#): compile each `.ink` to JSON with the ink compiler, run it in the C# runtime with a fixed seed and a fixed choice script, emit `<case>.golden.json` containing every line, its tags, every choice list, and the final `state.toJson()`.
4. Write the Dart side: a data-driven test that loads `<case>.json`, replays the same script and seed, and diffs against the golden line by line.
5. Only then: `Story`, `Container`, `Path`, `Pointer`, `JsonSerialisation`, `StoryState`, `continueStory`.

## Phases

1. Core flow (done: the whole runtime is ported, and all 168 goldens pass)
2. Persistence, observers, externals, `evaluateFunction`, `choosePathString`, tags: verify with scripted cases and a save/load round trip over every golden
3. Verify lists and threads with scripted cases (thread choices across save/load first), and vendor ink's own C# test stories from `Tests.cs`
4. Multi-flow verification (scripts that call `switchFlow`/`removeFlow`), profiler, `flutter_ink`

Ship to pub.dev after phase 2 with lists and threads supported and multi-flow marked experimental until phase 4 verifies it. Nothing is refused at load.

## References

- inkjs: https://github.com/y-lohse/inkjs (port from `src/engine/`)
- ink (C#): https://github.com/inkle/ink (`ink-engine-runtime/`, tie-breaker)
- Format doc (out of date, read for intent): https://github.com/inkle/ink/blob/master/Documentation/ink_JSON_runtime_format.md
- blade-ink (Java) and bladeink (Rust): second opinions in Dart-shaped languages
- `ink_runtime` 2.0.0 on pub.dev: not a baseline; a reference of last resort

## Commands

```
dart pub get
dart analyze
dart test
dart test test/conformance
dart run example/play.dart path/to/story.json
node tool/regen_goldens.mjs
```
