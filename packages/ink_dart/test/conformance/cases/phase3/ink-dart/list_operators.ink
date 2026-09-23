// Written for ink_dart: list operators the vendored corpus uses little.
LIST colours = red, (green), blue, yellow
LIST sizes = small = 10, medium = 20, large = 30
VAR mine = (red, blue)
VAR theirs = (blue, yellow)
{mine ^ theirs}
{mine hasnt yellow} {mine has red} {mine !? (red, blue)}
{mine + 1} {mine - 1}
{(yellow) + 1} / {(red) - 1} /
{mine == (blue, red)} {mine > (red)} {mine >= (red, blue)} {mine < (yellow)}
{LIST_VALUE(large)} {LIST_VALUE(())} /
{(small, red, large)}
{LIST_MIN((medium, blue))} {LIST_MAX((medium, blue))}
{LIST_COUNT(LIST_ALL(green))} {LIST_INVERT(mine)} {LIST_ALL(sizes)}
{LIST_RANGE(LIST_ALL(colours), 2, 3)} {LIST_RANGE(LIST_ALL(sizes), medium, large)}
~ temp empty = ()
{LIST_ALL(empty)} / {empty ? ()} / {() ? ()}
{colours(3)} {sizes(20)} / {colours(9)} /
~ mine = ()
{LIST_ALL(mine)}
{colours + 1}
{colours == 2}
Never reached.
