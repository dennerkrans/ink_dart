VAR gold = 3
The tavern is loud. # scene: tavern
The barkeep nods.
* [Buy a drink]
    ~ gold -= 1
    You drink. Gold left: {gold}.
* [Leave]
    You leave.
- -> END
