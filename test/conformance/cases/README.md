# Conformance corpus

Stories vendored from inkjs's test suite, grouped by the phase whose runtime
can run them. Each case is three files:

| File | What |
| --- | --- |
| `<case>.ink` | Source, copied from inkjs |
| `<case>.json` | Compiled story (generated) |
| `<case>.golden.json` | inkjs transcript: lines, tags, choice lists, chosen indices, errors, final `state.toJson()` (generated) |

An optional `<case>.script.json` (a JSON list of choice indices) overrides the
default choice script, which takes the first choice every time.

## Provenance and pins

- Source: [y-lohse/inkjs](https://github.com/y-lohse/inkjs) `src/tests/inkfiles/original/`,
  commit `6b11534` (2026-09-01).
- Compiler and oracle: npm `inkjs` 2.4.0 (pinned in `tool/package.json`).
  Compiled stories are `inkVersion` 21; saves are `inkSaveVersion` 10.
- Seed: 42 for every case. Guards: 1000 continues, 100 choices; a case that
  hits one records a `truncated` event.

Regenerate with `node tool/regen_goldens.mjs [filter]`. Re-vendor from a
fresh inkjs checkout with `node tool/vendor_cases.mjs path/to/inkjs`.

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

## Known limits of the transcripts

- inkjs's specs drive some stories with `ChoosePathString`, `EvaluateFunction`,
  variable writes or bound externals. The generic driver does none of that,
  so `phase2/bindings/*`, `phase2/newlines/newlines_trimming_with_func_external_fallback`
  and `phase3/inkjs/tests` currently record inkjs's
  `Missing function binding` exception. Phase 2 extends `script.json` with
  those operations and regenerates.
- inkjs 2.4.0's JSON writer drops the `.0` from whole floats, which made the
  compiler turn `7 / 3.0` into integer division. `tool/ink.mjs` patches
  `SimpleJson.Writer.WriteFloat` to write `3.0` as the C# reference does;
  story JSON and saved state both go through the patched writer.
- Known inkjs-vs-C# differences the goldens keep, because inkjs is the
  oracle: floats are doubles (`7 / 3.0` prints `2.3333333333333335`; C#
  prints `2.333333`), and a whole float result becomes an int (`3.0 * 2`
  is saved as `6`, not `6.0`).
- Compiled JSON still differs from inkjs's checked-in JSON (ignoring
  `inkVersion` 20 → 21) for 8 stories: `choices/tags_in_choice`,
  `choices/various_blank_choice_warning`,
  `diverts/tunnel_onwards_to_variable_divert_target`,
  `lists/contains_empty_list_always_false`, `lists/list_range`, and the three
  `tags/` stories. Some `.ink` sources changed after inkjs last regenerated
  its JSON (`list_range`); the rest are not investigated. The goldens use the
  pinned compiler's output throughout.

## Licence

The `.ink` files are from inkjs, used under its MIT licence:

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
