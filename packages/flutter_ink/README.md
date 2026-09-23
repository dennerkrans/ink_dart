# flutter_ink

Flutter widgets for [ink_dart](https://pub.dev/packages/ink_dart), the pure
Dart runtime for [inkle's ink](https://www.inklestudios.com/ink/).

- `StoryController` drives a story: it continues when you ask, collects the
  lines with their tags, records errors instead of throwing, chooses, saves
  and loads, and turns a global variable into a `ValueListenable`.
- `StoryView` shows the lines and the current choices, and plays on when a
  choice is tapped. Pass `lineBuilder` and `choiceBuilder` to draw them your
  own way.
- `StoryDebugView` shows where the story is, its variables, visit counts,
  errors, and optionally a profiler report.

## Use

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ink/flutter_ink.dart';

final controller = StoryController.fromJson(compiledJson);

// Game-side setup comes before the first continue.
controller.story.bindExternalFunction1<int>('roll', (sides) => dice.roll(sides));
final gold = controller.watch('gold'); // a ValueListenable<Object?>

controller.continueMaximally();

// In your widget tree:
StoryView(controller: controller);
ValueListenableBuilder(
  valueListenable: gold,
  builder: (context, value, _) => Text('Gold: $value'),
);
```

The controller owns the story's `onError`; read `controller.errors` instead.
Save with `controller.toJson()` and restore with `controller.loadJson(saved)`;
saves are the same format the C# ink runtime writes.

`flutter_ink` re-exports `package:ink_dart/ink_dart.dart`, so one import is
enough.

## Licence

MIT; see `LICENSE`, which includes the notices for ink and inkjs, which
ink_dart ports.
