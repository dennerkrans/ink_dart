# ink_dart

Pure Dart runtime for [inkle's ink](https://github.com/inkle/ink), ported
structurally from [inkjs](https://github.com/y-lohse/inkjs), with behaviour
checked against inkle's C# runtime (numbers and randomness follow C#). Spec:
[`docs/SPEC.md`](docs/SPEC.md). For the ink language itself, see the
[official ink documentation](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md).

**Status: phase 2.** The runtime passes every conformance case (168 stories,
including lists, threads and multi-flow), checked against inkle's C#
runtime. 19 cases drive the game-side API through scripts: external
functions, observers, `evaluateFunction`, `choosePathString`, variables,
save/load and flows. Every save is byte-identical to C#'s, and C#'s saves
load and play on in Dart.

```
dart run example/play.dart path/to/story.json [--seed N]
```

Layout note: the repo root is the `ink_dart` package (as `CLAUDE.md`'s
commands assume), not `packages/ink_dart/` as sketched in the spec;
`flutter_ink` joins later as a workspace member.

## Conformance

```
node tool/regen_goldens.mjs   # C# ink 1.2.1 oracle: compile cases, record transcripts (.NET 10 SDK)
dart test test/conformance    # replay in Dart, diff against goldens
dart test test/conformance -N phase1/   # the phase 1 loop
```

See [`test/conformance/cases/README.md`](test/conformance/cases/README.md)
for the corpus, pins and golden format.
