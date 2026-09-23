# Conformance corpus

Stories vendored from inkjs's test suite, grouped by the phase whose runtime
can run them. Each case is three files:

| File | What |
| --- | --- |
| `<case>.ink` | Source, copied from inkjs |
| `<case>.json` | Compiled story (generated) |
| `<case>.golden.json` | C# reference transcript: lines, tags, choice lists, chosen indices, errors, final `state.ToJson()` (generated) |

An optional `<case>.script.json` holds ops that run before the default loop
(continue to the next choice, take the first, repeat). The golden copies the
script, so the Dart side replays the golden alone.

## Script ops

Each op is a JSON object with an `"op"` key. Values are tagged:
`{"int": 5}`, `{"float": "2.5"}`, `{"string": "x"}`, `{"bool": true}`, and
list values come back as `{"list": "a, b"}` and divert targets as
`{"divert": "knot.stitch"}`.

| Op | Fields | Event recorded |
| --- | --- | --- |
| `continue` / `continueMaximally` | | `line` per line |
| `choose` | `index` | `choices`, `choose` |
| `choosePathString` | `path`, `resetCallstack`?, `args`? | |
| `evaluateFunction` | `name`, `args`? | `function` (`result`, `output`) |
| `setVariable` / `getVariable` | `name`, `value` | `variable` (get) |
| `variableNames` | | `variableNames` |
| `observe` | `name` | `observed` on each change |
| `bind` / `unbind` | `name`, `behaviour`, `lookaheadSafe`?, `value`?, `function`? | `external` on each call |
| `allowExternalFunctionFallbacks` | `value` | |
| `save` / `load` | `slot` | |
| `freshStory` | | (a new `Story` from the same JSON) |
| `resetState` | | (then re-seeds with 42) |
| `switchFlow` / `removeFlow` / `switchToDefaultFlow` | `name` | |
| `visitCount` | `path` | `visitCount` |
| `tagsForContentAtPath` | `path` | `tags` |
| `currentText` / `currentChoices` | | `currentText` / `choices` |
| `flowInfo` | | `flows` (`current`, `isDefault`, `alive`) |
| `backgroundSaveStart` / `backgroundSaveWrite` / `backgroundSaveComplete` | `slot` (write) | |
| `startProfiling` / `endProfiling` / `profile` | | `profile` (`continues`, `steps` without timings, `tree` of sample counts) |

Bind behaviours: `record` (returns nothing), `return` (`value`), `multiply`,
`repeat` (string repeated n times), `callInk` (argument + 1 passed to the ink
`function`). An op that throws records an `exception` event and the script
goes on. Both drivers (`tool/oracle/Driver.cs`, `test/conformance/harness.dart`)
implement the same ops.

The Dart suite also replays every case in save/load round-trip mode: at each
default-loop choice point the state is saved, loaded into a fresh `Story`,
and must serialise identically and play on to the same transcript.

## Provenance and pins

- Stories: [y-lohse/inkjs](https://github.com/y-lohse/inkjs) `src/tests/inkfiles/original/`,
  commit `6b11534` (2026-09-01).
- Compiler and oracle: inkle's C# ink 1.2.1 (tag `v1.2.1`, `35c63e5`), via
  `ink_compiler.dll` and `ink-engine-runtime.dll` from the inklecate release,
  checked in under `tool/oracle/lib/` (identical in the linux, mac and
  windows zips). Compiled stories are `inkVersion` 21; saves are
  `inkSaveVersion` 10.
- Seed: 42 for every case, set after the story is constructed. Construction
  already runs the `global decl` block with a time-based seed, so a case must
  not use `RANDOM` or a shuffle in a `VAR` initialiser; none in the corpus
  does. Guards: 1000 continues, 100 choices; a case that
  hits one records a `truncated` event.

The `.script.json` files are hand-written and live beside the cases, so
re-vendoring must keep them (don't delete `cases/` wholesale).

Regenerate with `node tool/regen_goldens.mjs [filter]` (needs the .NET 10
SDK; tests do not). Re-vendor from a fresh inkjs checkout with
`node tool/vendor_cases.mjs path/to/inkjs` (needs `npm ci` in `tool/`).

## Saves made by inkjs

`<case>.inkjs-save.json` (40 cases) is the save inkjs 2.4.0 makes at the
first choice, written by `node tool/record_inkjs_saves.mjs` (needs `npm ci`
in `tool/`) wherever it holds the same state as the C# runtime's checkpoint
there. The oracle then loads each one into a fresh C# story, as it is and
without `previousRandom` (older inkjs versions left it out), and records what
happens under `fromInkjsSave` and `fromInkjsSaveWithoutPreviousRandom` in
the golden. The Dart suite loads the same saves and must match byte for
byte.

One C# behaviour shows up only here: a save doesn't record that a choice is
an invisible default, so after loading, the C# runtime (and so ink_dart)
offers it as a visible, empty choice. inkjs writes an extra
`isInvisibleDefault` field for it, which neither loader reads.

## Cases written for ink_dart

`*/ink-dart/` holds stories written here rather than vendored, each saying so
in its first line: list operators the corpus barely uses (`^`, `hasnt`,
int-to-list coercion, ranges, mixed origins), `LIST_RANDOM` over mixed
origins, `RANDOM` edge cases, typed external bindings (in `bindings/`), thread
choices holding temporaries and tunnels, multi-flow state and background
saves, and a profiled story whose step log checks every runtime object's
description. Their goldens come from the
C# runtime like every other case.

## Phase assignment

A story goes in the higher of its category's phase and the phase of the
features its compiled JSON uses (`tool/ink.mjs`, `phaseFor`): tags or
externals put it in phase 2 at least, lists or threads in phase 3. So
`phase3/` holds stragglers from `booleans/`, `choices/`, `knots/` and others
that use `LIST` or `<-`, and inkjs's big `inkjs/tests.ink` (which uses lists).

## Not vendored

- `*/compiler/` folders: compiler-only tests; the compiler is out of scope.
- Stories inkjs's own suite expects to fail compilation:
  `choices/nested_choice_error`, `knots/stitch_naming_collision`,
  `variables/variable_name_colision_with_flow`,
  `variables/variable_name_collision_with_arg`,
  `weaves/weave_point_naming_collision`.

## Why C# and not inkjs

The goldens were first recorded with inkjs 2.4.0. Switching to the C#
runtime changed 13 transcripts, for three reasons the port must follow C# on:

- **Floats.** C# floats are 32-bit and print in .NET's shortest round-trip
  form (`7 / 3.0` → `2.3333333`); inkjs uses doubles (`2.3333333333333335`)
  and turns a whole float result into an int, so `1.5 * 2 / 4` gives `0`
  instead of `0.75`. inkjs's JSON writer also drops the `.0` from whole
  floats. (`evaluation/arithmetic`, `extra/arithmetic_2`,
  `builtins/floor_ceiling_and_casts`)
- **Randomness.** C# seeds shuffles and `RANDOM` with `new System.Random(seed)`;
  inkjs uses its own PRNG, so sequences differ. (`sequences/all_sequence_types`,
  `sequences/shuffle_stack_muddying`, `lists/list_random`)
- **Error text.** C# words some messages differently, e.g. pointers print as
  `(0.1)`; the port reproduces C#'s text. (`variables/temp_not_found`, and
  the `Missing function binding` cases below)

## Known limits of the transcripts

- Scripts follow inkjs's specs for 19 stories that the specs drive through
  the API. Where C# and inkjs disagree, the golden keeps C#: `EvaluateFunction`
  returning a divert gives `somewhere.here`, not inkjs's `-> somewhere.here`.
- `phase3/inkjs/tests`, inkjs's integration story, is scripted from inkjs's
  engine specs (`src/tests/specs/inkjs/engine/`): each spec becomes a
  `freshStory` followed by its calls, with loops unrolled. Two specs that pass
  a JavaScript object as an argument have no ink equivalent and are left out.
- ink's own C# test suite (`tests/Tests.cs` in inkle/ink) adds no stories:
  `node tool/vendor_ink_tests.mjs path/to/ink` finds every runtime test already
  in inkjs's corpus (by name or by content); the rest are compiler-only or
  fail to compile.

## Licence

`tool/oracle/lib/` holds inkle's ink DLLs under ink's MIT licence
(`tool/oracle/lib/LICENSE.txt`). The `.ink` files are from inkjs, used under
its MIT licence:

```
MIT License

Copyright (c) 2017 inkle Ltd.
Copyright (c) 2017 inkjs contributors (see AUTHORS)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
