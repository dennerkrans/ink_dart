// A complete, self-contained ink_dart example: load a compiled story, bind
// a game function, watch a variable, play to the end, and save.
//
// For a terminal player that loads any compiled story, see play.dart.

import 'dart:math';

import 'package:ink_dart/ink_dart.dart';

/// Compiled from this ink with inklecate:
///
/// ```ink
/// EXTERNAL roll(sides)
/// VAR gold = 0
/// The door is locked. # location: cellar
/// * [Pick the lock]
///     {roll(20) >= 11: The lock clicks open. -> treasure | The pick snaps.}
///     -> END
/// * [Leave] You walk away.
///     -> END
/// = treasure
/// ~ gold += 10
/// You find {gold} gold.
/// -> END
///
/// === function roll(sides) ===
/// ~ return RANDOM(1, sides)
/// ```
const storyJson =
    r'{"inkVersion":21,"root":[["^The door is locked. ","#","^location: cellar","/#","\n","ev","str","^Pick the lock","/str","/ev",{"*":"0.c-0","flg":20},"ev","str","^Leave","/str","/ev",{"*":"0.c-1","flg":20},{"c-0":["\n","ev",20,{"x()":"roll","exArgs":1},11,">=","/ev",[{"->":".^.b","c":true},{"b":["^ The lock clicks open. ",{"->":"treasure"},{"->":"0.c-0.9"},null]}],[{"->":".^.b"},{"b":["^ The pick snaps.",{"->":"0.c-0.9"},null]}],"nop","\n","end",{"->":"0.g-0"},{"#f":5}],"c-1":["^ You walk away.","\n","end",{"->":"0.g-0"},{"#f":5}],"g-0":["done",null]}],"done",{"treasure":["ev",{"VAR?":"gold"},10,"+",{"VAR=":"gold","re":true},"/ev","^You find ","ev",{"VAR?":"gold"},"out","/ev","^ gold.","\n","end",null],"roll":[{"temp=":"sides"},"ev",1,{"VAR?":"sides"},"rnd","/ev","~ret","\n",null],"global decl":["ev",0,{"VAR=":"gold"},"/ev","end",null]}],"listDefs":{}}';

void main() {
  final story = Story.fromJson(storyJson);
  story.onError = (message, type) => print('[$type] $message');

  // The game rolls the dice, so the app's RNG and dice animation agree.
  // Without this binding the story would use its own ink fallback.
  final rng = Random(2);
  story.bindExternalFunction1<int>('roll', (sides) => rng.nextInt(sides) + 1);

  story.observeVariable(
    'gold',
    (name, value) => print('  ($name is now $value)'),
  );

  while (true) {
    while (story.canContinue) {
      final text = story.continueStory().trim();
      final tags = story.currentTags;
      print(tags.isEmpty ? text : '$text   # ${tags.join(', ')}');
    }
    if (story.currentChoices.isEmpty) break;

    for (final choice in story.currentChoices) {
      print('  ${choice.index + 1}. ${choice.text}');
    }
    story.chooseChoiceIndex(0);
  }

  final saved = story.state.toJson();
  print('Saved ${saved.length} bytes of state.');
}
