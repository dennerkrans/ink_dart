## 0.1.1

- Guides in the API reference (getting started, game functions and
  variables, saving and loading, flows, matching Unity and Inky), a fuller
  library overview, and a C# API mapping in the README. The guides' snippets
  are tested.
- Popping an empty evaluation stack (reachable by jumping into the middle of
  a function with `choosePathString`) now fails with the C# runtime's
  message instead of a Dart `RangeError`.
- Checked further: saves made by inkjs load as in the C# runtime, and a
  differential fuzzer found no other difference from C# over 14,300 random
  runs.

## 0.1.0

First release: a pure Dart runtime for inkle's ink, ported from the C#
runtime (with inkjs's names) and checked against it.

### Stories

- Plays stories compiled by ink 1.2 (`inkVersion` 18–21) from Inky,
  inklecate or inkjs's compiler. Older formats are refused with a clear
  error. The compiler is not included.
- The whole runtime: flow and weaves, choices (once-only, sticky,
  conditional, invisible defaults, choice-only text), diverts, tunnels,
  functions, threads, global and temporary variables, `ref` parameters,
  lists and every list operation, glue and whitespace rules, visit and turn
  counts, sequences, cycles and shuffles, `RANDOM` and `SEED_RANDOM`.
- Tags: static and dynamic, on lines and choices, `globalTags` and
  `tagsForContentAtPath`.
- Errors and warnings are data: they go to `onError` with an `ErrorType`,
  and a `StoryException` is thrown only when no handler is set.

### Game interface

- `Story.fromJson`, `continueStory`, `continueMaximally`, `continueAsync`,
  `currentText`, `currentTags`, `currentChoices`, `chooseChoiceIndex`.
- `choosePathString` with `resetCallstack` and arguments;
  `evaluateFunction` and `evaluateFunctionWithOutput`.
- `variablesState`: read, write and iterate globals; `observeVariable`,
  `observeVariables`, `removeVariableObserver`.
- External functions: `bindExternalFunction0` to `bindExternalFunction4`
  convert ink's arguments to the declared types as C# does (a float passed to
  an `int` rounds, halves to even), `bindExternalFunctionGeneral` passes them
  raw; lookahead safety, `unbindExternalFunction`, and ink fallbacks with
  `allowExternalFunctionFallbacks`.
- Saves: `state.toJson` / `state.loadJson` write and read the same bytes as
  the C# runtime (`inkSaveVersion` 10; saves from version 8 load).
  `visitCountAtPathString`, `resetState`, `resetCallstack`.
- Multi-flow: `switchFlow`, `removeFlow`, `switchToDefaultFlow`,
  `currentFlowName`, `aliveFlowNames`.
- Background saves: `copyStateForBackgroundThreadSave` and
  `backgroundSaveComplete`.
- Profiler: `startProfiling`, `endProfiling`, `Profiler.report`,
  `stepLengthReport` and `megalog`.
- Examples: `example/example.dart`, and `example/play.dart`, a terminal
  player for any compiled story.

### Matches the C# runtime

- Floats are 32-bit and print as .NET does (`7 / 3.0` prints `2.3333333`);
  ints are 32-bit and wrap; a whole float result stays a float.
- `RANDOM`, `LIST_RANDOM` and shuffles use .NET's seeded `System.Random`,
  so a seed gives the same story as in Unity or Inky.
- Runtime error messages use the C# wording.
- Pure Dart with no dependencies: VM, AOT, Flutter and the web (use
  `Story.fromJson` there, since `jsonDecode` can't tell `3` from `3.0`).

### How it is checked

- 176 conformance stories: inkjs's test corpus, inkjs's integration story
  driven by its engine specs, and cases written for this port. ink's own C#
  test stories are all in the corpus already.
- Every golden is recorded by inkle's C# runtime (ink 1.2.1) with a fixed
  seed and script; the Dart port must match every line, tag, choice, error
  and the final save byte for byte.
- Scripts drive the game interface: external functions, observers,
  `evaluateFunction`, `choosePathString`, variables, save/load, flows,
  background saves and the profiler's step log.
- Every case is replayed again loading C#'s save at each choice into a fresh
  Dart story. Tests run on the VM and AOT-compiled, in CI.

### Known differences

- The C# runtime prints floats in the machine's culture (`2,5` on some
  systems); ink_dart always uses the invariant form (`2.5`).
