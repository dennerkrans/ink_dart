# ink_dart

A pure Dart runtime for [inkle's ink](https://www.inklestudios.com/ink/),
the narrative scripting language. It plays stories compiled to ink's JSON
format on the Dart VM, in AOT-compiled apps and in Flutter, with no
dependencies.

It is a port of inkle's C# runtime (with inkjs's names), and it is checked
against that runtime: the same story, seed and choices give the same text,
tags, choices, errors and save files, byte for byte.

For the ink language itself, see the
[ink documentation](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md).
The API follows ink's C# `Story` API name for name, in Dart casing, so
[running your ink](https://github.com/inkle/ink/blob/master/Documentation/RunningYourInk.md)
applies too.

## Use

Compile your story to JSON with [Inky](https://github.com/inkle/inky) or
`inklecate`, then:

```dart
import 'package:ink_dart/ink_dart.dart';

final story = Story.fromJson(jsonString);
story.onError = (message, type) => print('$type: $message');

// Game-side values and functions, before the first continue.
story.variablesState['str_mod'] = 1;
story.bindExternalFunction1<int>('roll', (sides) => rng.nextInt(sides) + 1);
story.observeVariable('gold', (name, value) => hud.gold = value as int);

while (story.canContinue) {
  final text = story.continueStory(); // one line, with its trailing newline
  render(text, story.currentTags);
}
for (final choice in story.currentChoices) {
  show(choice.index, choice.text, choice.tags);
}
story.chooseChoiceIndex(0);

final saved = story.state.toJson(); // persist between sessions
story.state.loadJson(saved);
```

`continueStory` is ink's `Continue`, renamed because `continue` is reserved
in Dart. External functions bind with `bindExternalFunction0` to
`bindExternalFunction4`, which convert ink's arguments to the declared
types as the C# runtime does (a float passed to an `int` parameter rounds,
halves to even), or with `bindExternalFunctionGeneral` for the raw values.

## Guides

The API reference has short guides:
[Getting started](https://pub.dev/documentation/ink_dart/latest/topics/Getting%20started-topic.html),
[Game functions and variables](https://pub.dev/documentation/ink_dart/latest/topics/Game%20functions%20and%20variables-topic.html),
[Saving and loading](https://pub.dev/documentation/ink_dart/latest/topics/Saving%20and%20loading-topic.html),
[Flows](https://pub.dev/documentation/ink_dart/latest/topics/Flows-topic.html) and
[Matching Unity and Inky](https://pub.dev/documentation/ink_dart/latest/topics/Matching%20Unity%20and%20Inky-topic.html).

## From ink's C# API

If you know ink from Unity, the names carry over in Dart casing:

| C# (`Ink.Runtime.Story`) | ink_dart |
| --- | --- |
| `new Story(json)` | `Story.fromJson(json)` |
| `Continue()` | `continueStory()` (`continue` is a Dart keyword) |
| `ContinueMaximally()`, `canContinue` | `continueMaximally()`, `canContinue` |
| `currentChoices`, `ChooseChoiceIndex(i)` | `currentChoices`, `chooseChoiceIndex(i)` |
| `currentTags`, `globalTags`, `TagsForContentAtPath(p)` | `currentTags`, `globalTags`, `tagsForContentAtPath(p)` |
| `ChoosePathString(p, reset, args)` | `choosePathString(p, resetCallstack: reset, arguments: args)` |
| `variablesState["x"]` | `variablesState['x']` |
| `ObserveVariable(name, fn)` | `observeVariable(name, fn)` |
| `BindExternalFunction<T>(name, fn)` | `bindExternalFunction1<T>(name, fn)` (0 to 4 arguments) |
| `BindExternalFunctionGeneral(name, fn)` | `bindExternalFunctionGeneral(name, fn)` |
| `EvaluateFunction(name, out text, args)` | `evaluateFunctionWithOutput(name, args)` |
| `state.ToJson()`, `state.LoadJson(s)` | `state.toJson()`, `state.loadJson(s)` |
| `SwitchFlow(name)`, `RemoveFlow(name)` | `switchFlow(name)`, `removeFlow(name)` |
| `onError += handler` | `onError = handler` |

`example/play.dart` plays any compiled story in the terminal:

```
dart run example/play.dart path/to/story.json [--seed N]
```

## Compatibility

| | |
| --- | --- |
| Story format | `inkVersion` 18–21 (ink 1.2; older formats refused) |
| Save format | `inkSaveVersion` 10; saves load from version 8 |
| Reference | inkle's C# runtime, ink 1.2.1 |

Numbers and randomness follow the C# runtime rather than inkjs: floats are
32-bit and print as .NET does (`7 / 3.0` prints `2.3333333`), and `RANDOM`
and shuffles use .NET's seeded generator, so a seed gives the same story
here as in Unity or Inky.

Multi-flow (`switchFlow`, `removeFlow`) and background saves
(`copyStateForBackgroundThreadSave`) are covered by the conformance cases
too.

On the web, use `Story.fromJson`: `Story(Map)` fed by `jsonDecode` cannot
tell `3` from `3.0` there.

## Development

The conformance corpus, the C# oracle that records it, and the design notes
live in the [repository](https://github.com/dennerkrans/ink_dart), not the
published package. Flutter widgets are in
[flutter_ink](https://github.com/dennerkrans/ink_dart/tree/main/packages/flutter_ink).

## Licence

MIT. ink_dart ports inkle's ink and inkjs (both MIT); their notices are in
`LICENSE`.
