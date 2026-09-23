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

Multi-flow (`switchFlow`, `removeFlow`) works but is marked experimental
until more of it is covered by tests. On the web, use `Story.fromJson`:
`Story(Map)` fed by `jsonDecode` cannot tell `3` from `3.0` there.

## Development

The conformance corpus, the C# oracle that records it, and the port's
design notes live in the repository, not the published package:

```
dart test                     # unit tests, conformance, save/load round trip
node tool/regen_goldens.mjs   # re-record goldens with the C# runtime (.NET 10)
```

See `test/conformance/cases/README.md` for the corpus and `docs/SPEC.md`
for the design.

## Licence

MIT. ink_dart ports inkle's ink and inkjs (both MIT); their notices are in
`LICENSE`.
