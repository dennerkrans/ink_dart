// The story behind test/unit/docs_test.dart, which runs the snippets in doc/.
# title: Docs story
EXTERNAL roll(sides)
EXTERNAL give(item, count)
VAR strength = 1
VAR name = "nobody"
VAR gold = 0
LIST inventory = (lantern), rope, (map)
Hello, {name}. # greeting
~ gold = gold + roll(6)
~ give("rope", 1)
* [Market] -> market
* [Leave] Bye. -> END

== market ==
# market tag
~ gold = gold + 1
The market. Gold {gold}.
-> END

=== function price_of(item) ===
~ return 10

=== function describe(item) ===
A fine {item}.
~ return "described"

=== function roll(sides) ===
~ return RANDOM(1, sides)
