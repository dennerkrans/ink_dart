# ink_dart

A pure Dart runtime for [inkle's ink](https://www.inklestudios.com/ink/),
checked against inkle's C# runtime, and Flutter widgets on top.

| Package | What |
| --- | --- |
| [`packages/ink_dart`](packages/ink_dart) | The runtime: plays compiled ink JSON with the same text, randomness and saves as the C# runtime. No dependencies. |
| [`packages/flutter_ink`](packages/flutter_ink) | Flutter widgets: a story controller, a story view and a debug view. |

## Development

```
cd packages/ink_dart && dart test            # unit, conformance, save/load round trip
cd packages/flutter_ink && flutter test      # widget tests
node tool/regen_goldens.mjs                  # re-record goldens with the C# runtime (.NET 10)
```

`tool/` holds the conformance oracle (inkle's C# ink 1.2.1, driven by
`tool/oracle`) and the scripts that vendored the corpus. The corpus and its
format are described in
[`packages/ink_dart/test/conformance/cases/README.md`](packages/ink_dart/test/conformance/cases/README.md);
the design is in [`docs/SPEC.md`](docs/SPEC.md).

## Licence

MIT. ink_dart ports inkle's ink and inkjs (both MIT); their notices are in
`LICENSE`.
