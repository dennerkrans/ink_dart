// Plays one conformance case in the C# runtime: the optional op script, then
// the default loop. Mirrors `Driver` in packages/ink_dart/test/conformance/harness.dart; keep
// the two in step, op for op and event for event.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json.Nodes;
using Ink;
using Ink.Runtime;
using Story = Ink.Runtime.Story;

sealed class Driver
{
    readonly string _json;
    readonly JsonArray _events = new();
    readonly Dictionary<string, string> _slots = new();
    Story _story;
    StoryState _backgroundSave;
    Profiler _profiler;

    public Driver(string json, string resumeFrom = null)
    {
        _json = json;
        _resumeFrom = resumeFrom;
    }

    // A save to load before playing; skips the global tags and the script.
    readonly string _resumeFrom;

    void Record(JsonObject e) => _events.Add(e);

    public (JsonArray events, string finalState) Play(JsonArray script)
    {
        try
        {
            NewStory();
        }
        catch (Exception e)
        {
            Record(new JsonObject { ["type"] = "exception", ["message"] = e.Message });
            return (_events, null);
        }

        var continues = 0;
        var choicesMade = 0;
        try
        {
            if (_resumeFrom != null)
                _story.state.LoadJson(_resumeFrom);
            else
                Record(new JsonObject { ["type"] = "globalTags", ["tags"] = Tags(_story.globalTags) });

            foreach (var op in _resumeFrom == null ? script ?? new JsonArray() : new JsonArray())
            {
                try
                {
                    RunOp(op.AsObject(), ref continues);
                }
                catch (Exception e)
                {
                    Record(new JsonObject { ["type"] = "exception", ["message"] = e.Message });
                }
            }

            var done = false;
            while (!done)
            {
                while (_story.canContinue)
                {
                    if (continues++ >= Oracle.MaxContinues)
                    {
                        Record(new JsonObject { ["type"] = "truncated", ["reason"] = "maxContinues" });
                        done = true;
                        break;
                    }
                    ContinueOnce();
                }
                if (done) break;

                if (_story.currentChoices.Count == 0)
                {
                    Record(new JsonObject { ["type"] = "end" });
                    break;
                }
                RecordChoices();
                if (choicesMade >= Oracle.MaxChoices)
                {
                    Record(new JsonObject { ["type"] = "truncated", ["reason"] = "maxChoices" });
                    break;
                }
                choicesMade++;
                // The save a game would make here; Dart must write the same
                // bytes and load these.
                Record(new JsonObject { ["type"] = "checkpoint", ["state"] = _story.state.ToJson() });
                Choose(0);
            }
        }
        catch (Exception e)
        {
            Record(new JsonObject { ["type"] = "exception", ["message"] = e.Message });
        }
        return (_events, _story.state.ToJson());
    }

    void NewStory()
    {
        _story = new Story(_json);
        _story.onError += (message, type) =>
        {
            var kind = type switch
            {
                ErrorType.Author => "author",
                ErrorType.Warning => "warning",
                _ => "error",
            };
            Record(new JsonObject { ["type"] = kind, ["message"] = message });
        };
        _story.state.storySeed = Oracle.Seed;
    }

    void ContinueOnce()
    {
        var text = _story.Continue();
        Record(new JsonObject
        {
            ["type"] = "line",
            ["text"] = text,
            ["tags"] = Tags(_story.currentTags),
        });
    }

    void RecordChoices()
    {
        Record(new JsonObject
        {
            ["type"] = "choices",
            ["choices"] = new JsonArray(_story.currentChoices.Select(c => (JsonNode)new JsonObject
            {
                ["index"] = c.index,
                ["text"] = c.text,
                ["tags"] = Tags(c.tags),
            }).ToArray()),
        });
    }

    void Choose(int index)
    {
        Record(new JsonObject { ["type"] = "choose", ["index"] = index });
        _story.ChooseChoiceIndex(index);
    }

    void RunOp(JsonObject op, ref int continues)
    {
        var name = (string)op["op"];
        switch (name)
        {
            case "continue":
                continues++;
                ContinueOnce();
                break;
            case "continueMaximally":
                while (_story.canContinue && continues++ < Oracle.MaxContinues)
                    ContinueOnce();
                break;
            case "choose":
                RecordChoices();
                Choose((int)op["index"]);
                break;
            case "choosePathString":
                _story.ChoosePathString(
                    (string)op["path"],
                    op["resetCallstack"] == null || (bool)op["resetCallstack"],
                    Args(op));
                break;
            case "evaluateFunction":
            {
                var fn = (string)op["name"];
                var result = _story.EvaluateFunction(fn, out var output, Args(op));
                Record(new JsonObject
                {
                    ["type"] = "function",
                    ["name"] = fn,
                    ["result"] = Encode(result),
                    ["output"] = output,
                });
                break;
            }
            case "setVariable":
                _story.variablesState[(string)op["name"]] = Decode(op["value"]);
                break;
            case "getVariable":
                Record(new JsonObject
                {
                    ["type"] = "variable",
                    ["name"] = (string)op["name"],
                    ["value"] = Encode(_story.variablesState[(string)op["name"]]),
                });
                break;
            case "variableNames":
                Record(new JsonObject
                {
                    ["type"] = "variableNames",
                    ["names"] = new JsonArray(_story.variablesState.Select(n => (JsonNode)n).ToArray()),
                });
                break;
            case "observe":
                _story.ObserveVariable((string)op["name"], (varName, value) =>
                    Record(new JsonObject
                    {
                        ["type"] = "observed",
                        ["name"] = varName,
                        ["value"] = Encode(value),
                    }));
                break;
            case "bind":
                Bind(op);
                break;
            case "unbind":
                _story.UnbindExternalFunction((string)op["name"]);
                break;
            case "allowExternalFunctionFallbacks":
                _story.allowExternalFunctionFallbacks = (bool)op["value"];
                break;
            case "save":
                _slots[(string)op["slot"] ?? ""] = _story.state.ToJson();
                break;
            case "load":
                _story.state.LoadJson(_slots[(string)op["slot"] ?? ""]);
                break;
            case "resetState":
                // ResetState seeds from the clock; keep the case deterministic.
                _story.ResetState();
                _story.state.storySeed = Oracle.Seed;
                break;
            case "freshStory":
                // A new Story from the same JSON, as a game would make on relaunch.
                NewStory();
                break;
            case "currentText":
                Record(new JsonObject { ["type"] = "currentText", ["text"] = _story.currentText });
                break;
            case "currentChoices":
                RecordChoices();
                break;
            case "switchFlow":
                _story.SwitchFlow((string)op["name"]);
                break;
            case "removeFlow":
                _story.RemoveFlow((string)op["name"]);
                break;
            case "switchToDefaultFlow":
                _story.SwitchToDefaultFlow();
                break;
            case "backgroundSaveStart":
                // Freeze a copy to save while the story plays on.
                _backgroundSave = _story.CopyStateForBackgroundThreadSave();
                break;
            case "backgroundSaveWrite":
                _slots[(string)op["slot"] ?? ""] = _backgroundSave.ToJson();
                break;
            case "backgroundSaveComplete":
                _story.BackgroundSaveComplete();
                _backgroundSave = null;
                break;
            case "startProfiling":
                _profiler = _story.StartProfiling();
                break;
            case "endProfiling":
                _story.EndProfiling();
                break;
            case "profile":
                RecordProfile();
                break;
            case "flowInfo":
                Record(new JsonObject
                {
                    ["type"] = "flows",
                    ["current"] = _story.currentFlowName,
                    ["isDefault"] = _story.currentFlowIsDefaultFlow,
                    ["alive"] = new JsonArray(_story.aliveFlowNames.Select(n => (JsonNode)n).ToArray()),
                });
                break;
            case "visitCount":
                Record(new JsonObject
                {
                    ["type"] = "visitCount",
                    ["path"] = (string)op["path"],
                    ["count"] = _story.state.VisitCountAtPathString((string)op["path"]),
                });
                break;
            case "tagsForContentAtPath":
                Record(new JsonObject
                {
                    ["type"] = "tags",
                    ["path"] = (string)op["path"],
                    ["tags"] = Tags(_story.TagsForContentAtPath((string)op["path"])),
                });
                break;
            default:
                throw new Exception($"unknown script op: {name}");
        }
    }

    // The profiler's deterministic parts: continues counted, every step's
    // type, description and path (the megalog without its timings), and the
    // sample counts per call-stack path, sorted by path.
    void RecordProfile()
    {
        var report = _profiler.Report();
        var continues = int.Parse(report.Substring(0, report.IndexOf(' ')));
        var steps = _profiler.Megalog().Split('\n')
            .Skip(1)
            .Where(l => l.Length > 0)
            .Select(l => l.Substring(0, l.LastIndexOf('\t')))
            .Select(l => (JsonNode)l)
            .ToArray();
        var tree = new List<string>();
        void Walk(ProfileNode node, string path)
        {
            var m = System.Text.RegularExpressions.Regex.Match(node.ownReport, @"\((\d+) self samples, (\d+) total\)");
            tree.Add($"{path}: self {m.Groups[1].Value}, total {m.Groups[2].Value}");
            if (!node.hasChildren) return;
            foreach (var kv in node.descendingOrderedNodes) Walk(kv.Value, path + "/" + kv.Key);
        }
        Walk(_profiler.rootNode, "");
        tree.Sort(StringComparer.Ordinal);
        Record(new JsonObject
        {
            ["type"] = "profile",
            ["continues"] = continues,
            ["steps"] = new JsonArray(steps),
            ["tree"] = new JsonArray(tree.Select(t => (JsonNode)t).ToArray()),
        });
    }

    // External function behaviours, named in the script. Each records the
    // call before running.
    // A typed binding goes through C#'s generic BindExternalFunction<T>, so
    // the runtime's TryCoerce converts the argument. `echo` returns it.
    void BindTyped(JsonObject op, string type)
    {
        var fn = (string)op["name"];
        var lookaheadSafe = op["lookaheadSafe"] != null && (bool)op["lookaheadSafe"];
        object Echo(object x)
        {
            Record(new JsonObject
            {
                ["type"] = "external",
                ["name"] = fn,
                ["args"] = new JsonArray(Encode(x)),
            });
            return x;
        }
        switch (type)
        {
            case "int": _story.BindExternalFunction<int>(fn, x => Echo(x), lookaheadSafe); break;
            case "float": _story.BindExternalFunction<float>(fn, x => Echo(x), lookaheadSafe); break;
            case "bool": _story.BindExternalFunction<bool>(fn, x => Echo(x), lookaheadSafe); break;
            case "string": _story.BindExternalFunction<string>(fn, x => Echo(x), lookaheadSafe); break;
            default: throw new Exception($"unknown binding type: {type}");
        }
    }

    void Bind(JsonObject op)
    {
        var types = op["types"]?.AsArray();
        if (types != null)
        {
            if (types.Count != 1) throw new Exception("typed bindings take one type");
            BindTyped(op, (string)types[0]);
            return;
        }
        var fn = (string)op["name"];
        var behaviour = (string)op["behaviour"] ?? "record";
        var lookaheadSafe = op["lookaheadSafe"] != null && (bool)op["lookaheadSafe"];
        _story.BindExternalFunctionGeneral(fn, args =>
        {
            Record(new JsonObject
            {
                ["type"] = "external",
                ["name"] = fn,
                ["args"] = new JsonArray(args.Select(a => Encode(a)).ToArray()),
            });
            switch (behaviour)
            {
                case "record":
                    return null;
                case "return":
                    return Decode(op["value"]);
                case "multiply":
                    // Float if either side is.
                    if (args[0] is int x && args[1] is int y) return x * y;
                    return Convert.ToSingle(args[0]) * Convert.ToSingle(args[1]);
                case "repeat":
                    return string.Concat(Enumerable.Repeat((string)args[1], (int)args[0]));
                case "callInk":
                    // Increment the argument, then hand it to an ink function.
                    return _story.EvaluateFunction((string)op["function"], (int)args[0] + 1);
                default:
                    throw new Exception($"unknown external behaviour: {behaviour}");
            }
        }, lookaheadSafe);
    }

    static object[] Args(JsonObject op)
    {
        var args = op["args"]?.AsArray();
        return args == null ? new object[0] : args.Select(Decode).ToArray();
    }

    static JsonArray Tags(List<string> tags) =>
        new JsonArray((tags ?? new List<string>()).Select(t => (JsonNode)t).ToArray());

    // Values cross the script and the golden as {"int": 5}, {"float": "2.5"},
    // {"string": "x"}, {"bool": true}, {"list": "a, b"}, {"divert": "a.b"},
    // or null.
    static JsonNode Encode(object value) => value switch
    {
        null => null,
        int i => new JsonObject { ["int"] = i },
        float f => new JsonObject { ["float"] = f.ToString(CultureInfo.InvariantCulture) },
        bool b => new JsonObject { ["bool"] = b },
        string s => new JsonObject { ["string"] = s },
        InkList l => new JsonObject { ["list"] = l.ToString() },
        Ink.Runtime.Path p => new JsonObject { ["divert"] = p.ToString() },
        _ => new JsonObject { ["unknown"] = value.GetType().Name },
    };

    static object Decode(JsonNode node)
    {
        if (node == null) return null;
        var o = node.AsObject();
        if (o["int"] != null) return (int)o["int"];
        if (o["float"] != null) return float.Parse((string)o["float"], CultureInfo.InvariantCulture);
        if (o["bool"] != null) return (bool)o["bool"];
        if (o["string"] != null) return (string)o["string"];
        throw new Exception($"cannot decode script value: {node.ToJsonString()}");
    }
}
