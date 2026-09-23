// Written for ink_dart: choices made in threads that hold temporaries and
// tunnels, played through save/load at every choice.
-> hub
== hub ==
~ temp visits = 0
- (loop)
~ visits++
Hub, visit {visits}.
<- shop(visits)
<- talk
* {visits < 3} [Wait] -> loop
* [Leave] -> DONE
== shop(n) ==
~ temp price = n * 10
* [Buy for {price}] You buy it for {price}. -> give_change(price) -> hub
== talk ==
* [Talk] "Hello." -> hub
== give_change(p) ==
Change: {100 - p}.
->->
