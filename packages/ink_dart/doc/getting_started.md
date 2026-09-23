Load a compiled story, play it line by line, and offer its choices.

## Compile your ink

ink_dart plays the JSON that ink's compiler produces; it doesn't compile
`.ink` itself. Export from [Inky](https://github.com/inkle/inky) (File, then
Export to JSON), or run `inklecate -o story.json story.ink`. Stories from ink
1.2 (`inkVersion` 18 to 21) load; older ones are refused with an error.

## The play loop

```dart
import 'package:ink_dart/ink_dart.dart';

final story = Story.fromJson(jsonString);
story.onError = (message, type) => print('$type: $message');

while (true) {
  while (story.canContinue) {
    final line = story.continueStory(); // one line, with its trailing newline
    show(line, story.currentTags);
  }
  if (story.currentChoices.isEmpty) break; // the story has ended

  for (final choice in story.currentChoices) {
    offer(choice.index, choice.text, choice.tags);
  }
  story.chooseChoiceIndex(await playerPick());
}
```

- `continueStory` is ink's `Continue`, renamed because `continue` is a Dart
  keyword. It runs the story to the end of the next line of text.
  `continueMaximally` runs to the next choice (or the end) and returns all
  the text at once.
- `currentTags` are the tags on the line just produced (`# tag` in ink).
  Tags at the very top of the story are also available as `globalTags`, and
  those at the top of a knot or stitch from `tagsForContentAtPath('knot')`.
- `currentChoices` is empty while the story can continue. Pass a choice's
  `index` back to `chooseChoiceIndex`.

## Errors

Mistakes in the ink that only show up while playing (a divert to a
variable holding no target, a missing `-> END`) are reported to `onError`
with an `ErrorType` of `error` or `warning`, and the story stops at an
error. Set `onError` before the first `continueStory`: without a handler,
the first problem is thrown as a `StoryException`.

## Jumping and restarting

`choosePathString('knot.stitch')` moves the story to a knot or stitch, for
chapter select or debugging. `resetState()` starts the story over;
`resetCallstack()` leaves any tunnels or threads before a jump.

## Next

- [Game functions and variables](../topics/Game%20functions%20and%20variables-topic.html)
- [Saving and loading](../topics/Saving%20and%20loading-topic.html)
