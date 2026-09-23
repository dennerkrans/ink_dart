// Written for ink_dart: LIST_RANDOM and ordering over mixed-origin lists.
LIST a = a1, a2, a3
LIST b = b1, b2, b3
VAR mixed = (a2, b1, a1, b3)
{mixed}
{LIST_RANDOM(mixed)} {LIST_RANDOM(mixed)} {LIST_RANDOM(mixed)} {LIST_RANDOM(mixed)}
~ SEED_RANDOM(7)
{LIST_RANDOM(mixed)} {LIST_RANDOM(mixed)} {LIST_RANDOM(mixed - a2)}
{LIST_RANDOM(())} /
