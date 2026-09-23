# Conformance corpus

Stories vendored from inkjs's test suite, grouped by the phase whose runtime
can run them. Each case is three files:

| File | What |
| --- | --- |
| `<case>.ink` | Source, copied from inkjs |
| `<case>.json` | Compiled story (generated) |
| `<case>.golden.json` | C# reference transcript: lines, tags, choice lists, chosen indices, errors, final `state.ToJson()` (generated) |

An optional `<case>.script.json` (a JSON list of choice indices) overrides the
default choice script, which takes the first choice every time.

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

Regenerate with `node tool/regen_goldens.mjs [filter]` (needs the .NET 10
SDK; tests do not). Re-vendor from a fresh inkjs checkout with
`node tool/vendor_cases.mjs path/to/inkjs` (needs `npm ci` in `tool/`).

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

- inkjs's specs drive some stories with `ChoosePathString`, `EvaluateFunction`,
  variable writes or bound externals. The generic driver does none of that,
  so `phase2/bindings/*`, `phase2/newlines/newlines_trimming_with_func_external_fallback`
  and `phase3/inkjs/tests` currently record the runtime's
  `Missing function binding` exception. Phase 2 extends `script.json` with
  those operations and regenerates.
- ink's own C# test suite (`tests/Tests.cs` in inkle/ink) keeps its stories
  inline in code; they are not vendored yet.

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
