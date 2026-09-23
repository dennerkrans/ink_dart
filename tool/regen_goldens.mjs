// Regenerate the conformance goldens with inkle's reference C# runtime.
//
// Usage: node tool/regen_goldens.mjs [filter]
//
// Thin wrapper around tool/oracle (needs the .NET 10 SDK). For every
// packages/ink_dart/test/conformance/cases/**/<case>.ink it writes the compiled <case>.json and
// the <case>.golden.json transcript; see tool/oracle/Program.cs. An optional
// [filter] limits regeneration to cases whose path contains it.

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const casesDir = path.resolve(here, "../packages/ink_dart/test/conformance/cases");
const filter = process.argv[2] ?? "";

const result = spawnSync(
  "dotnet",
  ["run", "--project", path.join(here, "oracle"), "-c", "Release", "-v", "q",
    "--", casesDir, filter],
  { stdio: "inherit" },
);
if (result.error) {
  console.error(`could not run dotnet: ${result.error.message}`);
  process.exit(1);
}
process.exit(result.status ?? 1);
