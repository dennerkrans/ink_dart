# ink_dart

Pure Dart runtime for [inkle's ink](https://github.com/inkle/ink), ported
structurally from [inkjs](https://github.com/y-lohse/inkjs). Spec:
[`docs/SPEC.md`](docs/SPEC.md). For the ink language itself, see the
[official ink documentation](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md).

**Status: phase 0.** The conformance harness is in place; the runtime is not.
The public API exists as signatures that throw `UnimplementedError`.

Layout note: the repo root is the `ink_dart` package (as `CLAUDE.md`'s
commands assume), not `packages/ink_dart/` as sketched in the spec;
`flutter_ink` joins later as a workspace member.

## Conformance

```
cd tool && npm ci && cd ..    # inkjs 2.4.0, compiler and oracle
node tool/regen_goldens.mjs   # compile cases, record inkjs transcripts
dart test test/conformance    # replay in Dart, diff against goldens
dart test test/conformance -N phase1/   # the phase 1 loop
```

See [`test/conformance/cases/README.md`](test/conformance/cases/README.md)
for the corpus, pins and golden format.
