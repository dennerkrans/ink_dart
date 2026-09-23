Save a story's state and restore it later, in this runtime or another.

## Save and load

```dart
final saved = story.state.toJson();   // a String; store it anywhere

// Later, on a fresh Story made from the same compiled JSON:
final story = Story.fromJson(jsonString);
story.state.loadJson(saved);
```

The save holds everything that changes as the story plays: position,
call stack and threads, variables, visit and turn counts, the random seed,
the current text and choices, and every flow. It doesn't hold the story
itself, so load it into a story made from the same JSON. External function
bindings, observers and `onError` aren't saved either: set them up again
before continuing.

Save at a choice, which is where games usually save, or between lines.
Don't save in the middle of a `continueStory` call.

## Moving saves between runtimes

ink_dart writes the same save format as inkle's C# runtime, byte for byte
(`inkSaveVersion` 10), and loads saves back to version 8. A save from a
Unity build of the same story loads here and plays on identically, and the
other way round. Saves made by inkjs load too.

One behaviour comes along with the format: a save doesn't record that a
choice is an invisible default (a fallback choice with no text), so after
loading, it's offered as an empty choice. The C# runtime does the same.

## Saving without stopping

For very large stories, `copyStateForBackgroundThreadSave()` freezes a copy
of the state that you can write out while the story carries on; call
`backgroundSaveComplete()` when you're done. Switching flow isn't allowed in
between.
