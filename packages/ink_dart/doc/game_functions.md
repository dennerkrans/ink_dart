Share state with the story: its variables, functions the game provides, and
ink functions the game calls.

## Variables

Global variables (`VAR` in ink) are read and written through
`variablesState`. Set them before the first `continueStory` so the ink
sees them from its first line.

```dart
story.variablesState['strength'] = 3;        // int
story.variablesState['name'] = 'Ada';        // String
final gold = story.variablesState['gold'];   // int, double, String, bool or InkList
for (final name in story.variablesState) { /* every global */ }
```

Only variables the ink declares can be set; anything else throws a
`StoryException`.

## Watching variables

```dart
story.observeVariable('gold', (name, value) => hud.gold = value as int);
```

At the end of each `continueStory`, the observer runs once for each watched
variable that changed, with its latest value. Changes the engine makes
while looking ahead (see below) and then rewinds don't count. Remove an
observer with `removeVariableObserver`.

## External functions

Declare a function in ink with `EXTERNAL roll(sides)`, then bind it before
the first `continueStory`:

```dart
story.bindExternalFunction1<int>('roll', (sides) => rng.nextInt(sides) + 1);
story.bindExternalFunction2<String, int>('give', (item, count) {
  inventory.add(item, count); // returning nothing returns nothing to ink
});
```

`bindExternalFunction0` to `bindExternalFunction4` convert each argument to
the type you declare, as the C# runtime does: a float passed to an `int`
parameter rounds (halves to even), an int becomes a `double` or a `bool`, and
any value can be taken as a `String`. `bindExternalFunctionGeneral` passes
the raw values instead.

**Lookahead.** To decide whether the next line is glued to this one, the
engine sometimes runs a little past the end of a line and then rewinds. A
function bound with `lookaheadSafe: false` (the default) is never called
during that lookahead: the engine stops there instead. Pass `true` only for
functions with no side effects, such as a pure calculation.

If a function isn't bound, the first `continueStory` throws a
`StoryException` naming every missing function, whether or not `onError` is
set. With `allowExternalFunctionFallbacks = true`,
an ink function of the same name is called instead, so a story can run in
Inky without the game:

```
EXTERNAL roll(sides)
=== function roll(sides) ===
~ return RANDOM(1, sides)
```

## Calling ink functions

```dart
final price = story.evaluateFunction('price_of', ['sword']);
final r = story.evaluateFunctionWithOutput('describe', ['sword']);
print(r.textOutput); // any text the function printed
print(r.result);     // its return value
```

Arguments may be `int`, `double`, `String`, `bool` or `InkList`. A function
returning a divert target returns its path as a string.

## Lists

An ink `LIST` variable comes back as an `InkList`, a set of `InkListItem`s
with their values:

```dart
final inventory = story.variablesState['inventory'] as InkList;
if (inventory.containsItemNamed('lantern')) { ... }
print(inventory); // "lantern, rope", in value order
```
