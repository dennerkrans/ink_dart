// Written for ink_dart: a background save freezes the state while the story
// plays on; the frozen copy saves the old state, and the story keeps its
// changes once the save completes.
VAR gold = 0
- (top)
~ gold += 10
Gold: {gold}.
{gold < 40: -> top}
Rich.
-> DONE
== side ==
Side flow, gold {gold}.
-> DONE
