## 0.1.0

First release.

- Plays stories compiled by ink 1.2 (`inkVersion` 18–21); saves are
  `inkSaveVersion` 10 and byte-identical to the C# runtime's.
- The whole runtime: flow, choices, diverts, tunnels, functions, threads,
  variables, lists, tags, visit and turn counts, sequences and shuffles.
- Game interface: `continueStory`, `chooseChoiceIndex`, `choosePathString`,
  `evaluateFunction`, `variablesState`, variable observers, external
  functions (`bindExternalFunction0`…`4` with C#'s argument conversion, and
  `bindExternalFunctionGeneral`), `state.toJson` / `state.loadJson`.
- Numbers and randomness follow the C# reference runtime: 32-bit floats,
  .NET's float formatting, .NET's seeded `System.Random`.
- Multi-flow (`switchFlow`, `removeFlow`), background saves, and the
  profiler (`startProfiling`, `Profiler.report`, `megalog`).
- Checked against inkle's C# runtime on 176 stories, each also replayed
  through save/load at every choice.
