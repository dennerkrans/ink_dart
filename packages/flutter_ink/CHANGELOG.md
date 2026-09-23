## 0.1.1

- A fuller library overview in the API reference.
- The example is now a runnable app (`example/`, Android, iOS, macOS and
  web): `cd example && flutter run`.

## 0.1.0

First release: Flutter widgets for ink_dart.

- `StoryController`, a `ChangeNotifier` around an ink_dart `Story`:
  - continues only when asked (`continueStory`, `continueMaximally`), so
    external functions and variables can be set up first;
  - collects `lines` with their tags, and records `errors` instead of
    throwing;
  - `choose` (continuing to the next choice by default), `isEnded`,
    `clearTranscript` for beat boundaries;
  - `toJson` and `loadJson`, in the C# runtime's save format;
  - `watch(name)` turns a global variable into a `ValueListenable`.
- `StoryView`: the story's lines and current choices in a `ListView`,
  playing on when a choice is tapped; `lineBuilder` and `choiceBuilder`
  replace the default `Text` and `TextButton`.
- `StoryDebugView`: position, flow, turn, save size, variables, visit counts,
  turn indices, errors, and an optional profiler report.
- Re-exports `package:ink_dart/ink_dart.dart`.
- Example app with a story beside its debug view.
