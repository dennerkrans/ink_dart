// Written for ink_dart: what flows share (globals, visit counts) and keep
// apart (position, output, choices), across switching, removal and save/load.
VAR coins = 0
Default flow starts.
-> DONE

== market ==
~ coins += 5
Market, visit {market}, coins {coins}.
* [Buy bread] Bread bought. -> DONE
* [Leave market] -> DONE

== docks ==
~ coins += 1
Docks, visit {docks}, market visits {market}, coins {coins}.
+ [Fish] You fish. -> docks
+ [Leave docks] -> DONE
