// Records the unit-test data behind test/unit/prng_test.dart and
// test/unit/float32_test.dart:
//   prng_cases.json:    new System.Random(seed).Next() sequences, the only
//                       Random call the ink runtime makes;
//   float32_cases.json: float.ToString(InvariantCulture), ink's
//                       SimpleJson.Writer.Write(float) and float.TryParse
//                       (NumberStyles.Float, InvariantCulture) results.
//
// Usage: dotnet run --project tool/oracle_unit -- <output dir>

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using Ink.Runtime;
using Path = System.IO.Path;

static class OracleUnit
{
    static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("usage: OracleUnit <output dir>");
            return 64;
        }
        var outDir = args[0];
        Write(Path.Combine(outDir, "prng_cases.json"), PrngCases());
        Write(Path.Combine(outDir, "float32_cases.json"), FloatCases());
        return 0;
    }

    static void Write(string path, JsonNode node) =>
        File.WriteAllText(path, node.ToJsonString(JsonOptions).Replace("\r\n", "\n") + "\n");

    static JsonNode PrngCases()
    {
        var seeds = new List<int> { 0, 1, 2, 42, 99, -1, -42, 12345, 1000000,
            int.MaxValue, int.MaxValue - 1, int.MinValue, int.MinValue + 1 };
        var rng = new Random(7);
        for (var i = 0; i < 20; i++) seeds.Add(rng.Next(int.MinValue, int.MaxValue));
        var cases = new JsonArray();
        foreach (var seed in seeds)
        {
            var r = new Random(seed);
            var values = new JsonArray();
            for (var i = 0; i < 60; i++) values.Add(r.Next());
            cases.Add(new JsonObject { ["seed"] = seed, ["next"] = values });
        }
        return new JsonObject { ["cases"] = cases };
    }

    static string JsonFloat(float f)
    {
        var w = new SimpleJson.Writer();
        w.WriteArrayStart();
        w.Write(f);
        w.WriteArrayEnd();
        var s = w.ToString();
        return s.Substring(1, s.Length - 2);
    }

    static JsonNode FloatCases()
    {
        var values = new List<float>();
        void Add(float f) => values.Add(f);

        foreach (var f in new[] { 0f, -0f, 1f, -1f, 0.5f, 0.1f, 0.2f, 0.3f,
            0.1f + 0.2f, 7f / 3f, 1f / 3f, 2f / 3f, 2.5f, -2.5f, 1.5f, 3f, 6f,
            100f, 1000f, 1e6f, 1e7f, 1e8f, 123456789f, 16777216f, 16777217f,
            float.MaxValue, float.MinValue, float.Epsilon, -float.Epsilon,
            1.17549435e-38f, float.PositiveInfinity, float.NegativeInfinity,
            float.NaN, MathF.PI, MathF.E, MathF.Sqrt(2f), 0.000001f, 0.00001f,
            0.0001f, 1e-7f, 3.4e38f, 1.4142135f, 0.75f })
            Add(f);
        for (var e = -45; e <= 38; e++)
        {
            Add((float)Math.Pow(10, e));
            Add(-(float)Math.Pow(10, e));
            Add((float)(1.5 * Math.Pow(10, e)));
            Add((float)(1.2345678 * Math.Pow(10, e)));
        }
        for (var i = -20; i <= 20; i++) Add(i / 2f);
        for (var n = 9_999_990; n <= 10_000_010; n++) Add(n);
        foreach (var n in new[] { 99_999_990, 100_000_000, 999_999_900,
            1_000_000_000, 123_456_780, 987_654_321, 4_294_967_296L })
            Add(n);
        for (var k = 0; k < 64; k++)
        {
            Add((float)Math.Pow(2, k));
            Add((float)Math.Pow(2, -k - 100));
        }
        // Ties in the last shortest digit: .NET picks the even digit.
        for (var n = 1048576; n < 1048576 + 64; n++)
        {
            Add(n + 0.25f);
            Add(n + 0.75f);
        }
        var rng = new Random(1234);
        var bits = new byte[4];
        while (values.Count < 3000)
        {
            rng.NextBytes(bits);
            var f = BitConverter.ToSingle(bits, 0);
            Add(f);
        }

        var format = new JsonArray();
        foreach (var f in values)
        {
            format.Add(new JsonObject
            {
                ["bits"] = BitConverter.SingleToInt32Bits(f),
                ["toString"] = f.ToString(CultureInfo.InvariantCulture),
                ["json"] = JsonFloat(f),
            });
        }

        var inputs = new List<string> { "0", "1", "-1", "+1", "1.5", ".5",
            "5.", "-.5", "1e5", "1E5", "1e+5", "1e-5", "1E-06", "2.3333333",
            "0.33333334", "123456789", "3.4E+38", "3.5E+38", "1e39", "-1e39",
            "1e-46", "1.401298E-45", "Infinity", "-Infinity", "infinity",
            "∞", "-∞", "NaN", "nan", " 1.5", "1.5 ", " 1.5 ", "\t2\n", "",
            " ", "abc", "1,5", "1,000", "0x10", "1.5f", "--1", "1e", "e5",
            ".", "-", "+", "1.2.3", "٣", "1_000", "00012.500", "1e0005",
            "0.1", "0.30000001", "16777217", "3.14159265358979323846",
            "1.00000005960464477539", "1.0000000596046448", "7.038531e-26",
            "+Infinity", "-0", "-0.0", "-NaN", "1.000000059604644775390625",
            "1.000000059604644775390626", "1.000000178813934326171875",
            "340282356779733661637539395458142568448",
            "340282356779733661637539395458142568447", "1e-45", "7e-46", "7.1e-46" };
        var parse = new JsonArray();
        foreach (var s in inputs)
        {
            var ok = float.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var f);
            parse.Add(new JsonObject
            {
                ["input"] = s,
                ["bits"] = ok ? BitConverter.SingleToInt32Bits(f) : null,
            });
        }
        return new JsonObject { ["format"] = format, ["parse"] = parse };
    }
}
