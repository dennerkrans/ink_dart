// Regenerate the conformance goldens with inkjs as the oracle.
//
// Usage: node tool/regen_goldens.mjs [filter]
//
// For every test/conformance/cases/**/<case>.ink (except include targets):
//   1. compile it with the pinned inkjs compiler to <case>.json;
//   2. play it in inkjs with a fixed seed and a fixed choice script;
//   3. write <case>.golden.json: every line with its tags, every choice
//      list, every chosen index, every error and warning in the order the
//      runtime reported it, and the final state.toJson() as a string.
//
// The choice script is the optional <case>.script.json, a JSON list of
// choice indices; once it runs out (or when there is none) the first choice
// is taken. The golden records every event, so the Dart side replays the
// golden, not the script.
//
// An optional [filter] limits regeneration to cases whose path contains it.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compileInk, Story } from "./ink.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const casesDir = path.resolve(here, "../test/conformance/cases");
const inkjsVersion = JSON.parse(
  fs.readFileSync(path.join(here, "node_modules/inkjs/package.json"), "utf-8"),
).version;

// Fixed for every case; the Dart runner sets the same seed.
export const seed = 42;
// Guards against stories that loop forever under the choice script.
const maxContinues = 1000;
const maxChoices = 100;

const errorKinds = ["author", "warning", "error"];

function listCases(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== "includes") out.push(...listCases(full));
    } else if (entry.name.endsWith(".ink")) {
      out.push(full);
    }
  }
  return out.sort();
}

function play(json, script) {
  const events = [];
  const record = (e) => events.push(e);
  let story;
  try {
    story = new Story(json);
  } catch (e) {
    record({ type: "exception", message: String(e.message ?? e) });
    return { events, finalState: null };
  }
  story.onError = (message, type) => {
    record({ type: errorKinds[type] ?? "error", message });
  };
  story.state.storySeed = seed;

  let continues = 0;
  let choicesMade = 0;
  try {
    record({ type: "globalTags", tags: story.globalTags ?? [] });
    outer: for (;;) {
      while (story.canContinue) {
        if (continues++ >= maxContinues) {
          record({ type: "truncated", reason: "maxContinues" });
          break outer;
        }
        const text = story.Continue();
        record({ type: "line", text, tags: [...story.currentTags] });
      }
      const choices = story.currentChoices;
      if (choices.length === 0) {
        record({ type: "end" });
        break;
      }
      record({
        type: "choices",
        choices: choices.map((c) => ({
          index: c.index,
          text: c.text,
          tags: c.tags ? [...c.tags] : [],
        })),
      });
      if (choicesMade >= maxChoices) {
        record({ type: "truncated", reason: "maxChoices" });
        break;
      }
      const index = script[choicesMade] ?? 0;
      choicesMade++;
      record({ type: "choose", index });
      story.ChooseChoiceIndex(index);
    }
  } catch (e) {
    record({ type: "exception", message: String(e.message ?? e) });
  }
  // Kept as the raw string: parsing would erase the int/float distinction
  // (a whole float is written `1.0`; see the SimpleJson patch in ink.mjs).
  return { events, finalState: story.state.toJson() };
}

const filter = process.argv[2] ?? "";
let written = 0;
const failures = [];

for (const inkPath of listCases(casesDir)) {
  const rel = path.relative(casesDir, inkPath).slice(0, -".ink".length);
  if (!rel.includes(filter)) continue;
  const base = inkPath.slice(0, -".ink".length);

  const { json, errors, warnings } = compileInk(inkPath);
  if (json === null) {
    failures.push(`${rel}: ${errors[0]}`);
    continue;
  }
  fs.writeFileSync(`${base}.json`, json + "\n");

  const scriptPath = `${base}.script.json`;
  const script = fs.existsSync(scriptPath)
    ? JSON.parse(fs.readFileSync(scriptPath, "utf-8"))
    : [];

  const { events, finalState } = play(json, script);
  const golden = {
    case: rel,
    inkjs: inkjsVersion,
    seed,
    compilerWarnings: warnings,
    events,
    finalState,
  };
  fs.writeFileSync(`${base}.golden.json`, JSON.stringify(golden, null, 2) + "\n");
  written++;
}

console.log(`wrote ${written} goldens (inkjs ${inkjsVersion}, seed ${seed})`);
if (failures.length > 0) {
  console.error(`\n${failures.length} cases failed to compile:`);
  for (const f of failures) console.error(`  ${f}`);
  process.exit(1);
}
