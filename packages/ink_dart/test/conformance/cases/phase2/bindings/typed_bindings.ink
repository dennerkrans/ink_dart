// Written for ink_dart (not from inkjs): arguments converted to the types
// of a typed external binding, as C#'s TryCoerce does.
EXTERNAL asInt(x)
EXTERNAL asFloat(x)
EXTERNAL asBool(x)
EXTERNAL asString(x)
{asInt(2.5)} {asInt(3.5)} {asInt(-2.5)} {asInt(2.6)} {asInt(7)} {asInt(true)}
{asFloat(3)} {asFloat(2.5)}
{asBool(0)} {asBool(5)} {asBool(true)}
{asString(2.5)} {asString(7)} {asString(true)} {asString("hi")}
{asBool(2.5)}
