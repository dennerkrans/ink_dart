// Regenerates the conformance goldens with inkle's reference C# runtime.
//
// Usage: dotnet run --project tool/oracle -- <cases dir> [filter]
//
// For every <case>.ink under the cases dir (except include targets):
//   1. compile it with the ink 1.2.1 compiler to <case>.json;
//   2. play it with a fixed seed and a fixed choice script;
//   3. write <case>.golden.json: every line with its tags, every choice
//      list, every chosen index, every error and warning in the order the
//      runtime reported it, and the final state.ToJson() as a string.
//
// The choice script is the optional <case>.script.json, a JSON list of
// choice indices; once it runs out (or when there is none) the first choice
// is taken. The golden records every event, so the Dart side replays the
// golden, not the script. Keep the play loop in step with
// test/conformance/harness.dart.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using Ink;
using Ink.Runtime;
using Path = System.IO.Path;
using Story = Ink.Runtime.Story;

static class Oracle
{
    const string RuntimeVersion = "ink 1.2.1";
    // Fixed for every case; the Dart runner reads it from the golden.
    const int Seed = 42;
    // Guards against stories that loop forever under the choice script.
    const int MaxContinues = 1000;
    const int MaxChoices = 100;

    // Stories ink's own test suite compiles with count-all-visits (`-c`).
    static readonly HashSet<string> CountAllVisitsFiles = new()
    {
        "visit_counts_when_choosing.ink",
        "turns_since_with_variable_target.ink",
        "read_count_variable_target.ink",
        "tests.ink",
    };

    static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("usage: InkOracle <cases dir> [filter]");
            return 64;
        }
        var casesDir = Path.GetFullPath(args[0]);
        var filter = args.Length > 1 ? args[1] : "";
        var written = 0;
        var failures = new List<string>();

        foreach (var inkPath in ListCases(casesDir))
        {
            var rel = Path.GetRelativePath(casesDir, inkPath)
                .Replace('\\', '/');
            rel = rel.Substring(0, rel.Length - ".ink".Length);
            if (!rel.Contains(filter)) continue;
            var basePath = inkPath.Substring(0, inkPath.Length - ".ink".Length);

            var (json, errors, warnings) = CompileInk(inkPath);
            if (json == null)
            {
                failures.Add($"{rel}: {errors.FirstOrDefault()}");
                continue;
            }
            File.WriteAllText($"{basePath}.json", json + "\n");

            var scriptPath = $"{basePath}.script.json";
            var script = File.Exists(scriptPath)
                ? JsonSerializer.Deserialize<List<int>>(File.ReadAllText(scriptPath))
                : new List<int>();

            var (events, finalState) = Play(json, script);
            var golden = new JsonObject
            {
                ["case"] = rel,
                ["runtime"] = RuntimeVersion,
                ["seed"] = Seed,
                ["compilerWarnings"] = new JsonArray(
                    warnings.Select(w => (JsonNode)w).ToArray()),
                ["events"] = events,
                ["finalState"] = finalState,
            };
            File.WriteAllText(
                $"{basePath}.golden.json",
                golden.ToJsonString(JsonOptions).Replace("\r\n", "\n") + "\n");
            written++;
        }

        Console.WriteLine($"wrote {written} goldens ({RuntimeVersion}, seed {Seed})");
        if (failures.Count > 0)
        {
            Console.Error.WriteLine($"\n{failures.Count} cases failed to compile:");
            foreach (var f in failures) Console.Error.WriteLine($"  {f}");
            return 1;
        }
        return 0;
    }

    static List<string> ListCases(string dir)
    {
        var result = new List<string>();
        foreach (var sub in Directory.GetDirectories(dir))
        {
            if (Path.GetFileName(sub) != "includes") result.AddRange(ListCases(sub));
        }
        result.AddRange(Directory.GetFiles(dir, "*.ink"));
        result.Sort(StringComparer.Ordinal);
        return result;
    }

    // Resolves INCLUDEs relative to the including story, not the cwd.
    sealed class CaseFileHandler : IFileHandler
    {
        readonly string _dir;
        public CaseFileHandler(string dir) => _dir = dir;
        public string ResolveInkFilename(string includeName) =>
            Path.GetFullPath(Path.Combine(_dir, includeName));
        public string LoadInkFileContents(string fullFilename) =>
            File.ReadAllText(fullFilename);
    }

    static (string json, List<string> errors, List<string> warnings) CompileInk(
        string inkPath)
    {
        var errors = new List<string>();
        var warnings = new List<string>();
        var options = new Compiler.Options
        {
            sourceFilename = inkPath,
            pluginDirectories = new List<string>(),
            countAllVisits = CountAllVisitsFiles.Contains(Path.GetFileName(inkPath)),
            fileHandler = new CaseFileHandler(Path.GetDirectoryName(inkPath)),
            errorHandler = (message, type) =>
            {
                if (type == Ink.ErrorType.Error) errors.Add(message);
                else warnings.Add(message);
            },
        };
        var source = File.ReadAllText(inkPath);
        try
        {
            var story = new Compiler(source, options).Compile();
            if (story != null && errors.Count == 0) return (story.ToJson(), errors, warnings);
        }
        catch (Exception e)
        {
            errors.Add(e.Message);
        }
        return (null, errors, warnings);
    }

    static JsonArray Tags(List<string> tags) =>
        new JsonArray((tags ?? new List<string>()).Select(t => (JsonNode)t).ToArray());

    static (JsonArray events, string finalState) Play(string json, List<int> script)
    {
        var events = new JsonArray();
        Story story;
        try
        {
            story = new Story(json);
        }
        catch (Exception e)
        {
            events.Add(new JsonObject { ["type"] = "exception", ["message"] = e.Message });
            return (events, null);
        }
        story.onError += (message, type) =>
        {
            var kind = type switch
            {
                Ink.ErrorType.Author => "author",
                Ink.ErrorType.Warning => "warning",
                _ => "error",
            };
            events.Add(new JsonObject { ["type"] = kind, ["message"] = message });
        };
        story.state.storySeed = Seed;

        var continues = 0;
        var choicesMade = 0;
        try
        {
            events.Add(new JsonObject { ["type"] = "globalTags", ["tags"] = Tags(story.globalTags) });
            var done = false;
            while (!done)
            {
                while (story.canContinue)
                {
                    if (continues++ >= MaxContinues)
                    {
                        events.Add(new JsonObject { ["type"] = "truncated", ["reason"] = "maxContinues" });
                        done = true;
                        break;
                    }
                    var text = story.Continue();
                    events.Add(new JsonObject
                    {
                        ["type"] = "line",
                        ["text"] = text,
                        ["tags"] = Tags(story.currentTags),
                    });
                }
                if (done) break;

                var choices = story.currentChoices;
                if (choices.Count == 0)
                {
                    events.Add(new JsonObject { ["type"] = "end" });
                    break;
                }
                events.Add(new JsonObject
                {
                    ["type"] = "choices",
                    ["choices"] = new JsonArray(choices.Select(c => (JsonNode)new JsonObject
                    {
                        ["index"] = c.index,
                        ["text"] = c.text,
                        ["tags"] = Tags(c.tags),
                    }).ToArray()),
                });
                if (choicesMade >= MaxChoices)
                {
                    events.Add(new JsonObject { ["type"] = "truncated", ["reason"] = "maxChoices" });
                    break;
                }
                var index = choicesMade < script.Count ? script[choicesMade] : 0;
                choicesMade++;
                events.Add(new JsonObject { ["type"] = "choose", ["index"] = index });
                story.ChooseChoiceIndex(index);
            }
        }
        catch (Exception e)
        {
            events.Add(new JsonObject { ["type"] = "exception", ["message"] = e.Message });
        }
        return (events, story.state.ToJson());
    }
}
