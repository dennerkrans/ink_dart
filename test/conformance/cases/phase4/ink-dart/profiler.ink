// Written for ink_dart: profiles a story touching most runtime object types,
// so the profiler's step log also checks every object's description.
LIST mood = calm, (tense), angry
VAR score = 1.5
Opening {greet("you")} # intro
-> scene ->
<- aside
* [Stay] {~Quiet.|Still.} Mood {mood + 1}.
* {score > 1} [Go] Going<>
  -> END
- Score {score * 2}.
-> END

== scene ==
~ temp n = 2
{ n:
- 1: one
- 2: two
- else: many
}
->->

== aside ==
+ [Aside] Whispered. -> DONE

== function greet(who) ==
~ return "hello " + who
