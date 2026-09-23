// Records saves made by inkjs, so the Dart suite can check that ink_dart
// loads them (the spec's cross-runtime save item).
//
// Usage: node tool/record_inkjs_saves.mjs
//
// For every unscripted case with a choice, inkjs 2.4.0 plays the compiled
// story with the golden's seed to the first choice and saves. The save is
// kept as <case>.inkjs-save.json only where it describes the same state as
// the C# runtime's checkpoint there (same JSON, numbers compared by value,
// since inkjs writes a whole float as an int; extra inkjs-only fields allowed). Elsewhere inkjs has already played
// differently (its floats and random numbers differ from C#), so the save
// can't be checked against the golden.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Story } from "inkjs/full";

const here = path.dirname(fileURLToPath(import.meta.url));
const casesDir = path.resolve(here, "../packages/ink_dart/test/conformance/cases");

function listGoldens(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...listGoldens(full));
    else if (e.name.endsWith(".golden.json")) out.push(full);
  }
  return out.sort();
}

// Whether inkjs's save [a] holds C#'s state [b]: numbers compared by value,
// and fields only inkjs writes (such as a choice's isInvisibleDefault) are
// allowed, since both loaders ignore them.
function same(a, b) {
  if (typeof a === "number" && typeof b === "number") return a === b;
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((x, i) => same(x, b[i]));
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    return Object.keys(b).every((k) => k in a && same(a[k], b[k]));
  }
  return a === b;
}

let kept = 0;
let differs = 0;
for (const goldenPath of listGoldens(casesDir)) {
  const base = goldenPath.slice(0, -".golden.json".length);
  const out = `${base}.inkjs-save.json`;
  if (fs.existsSync(out)) fs.rmSync(out);

  const golden = JSON.parse(fs.readFileSync(goldenPath, "utf-8"));
  if (golden.script) continue;
  const checkpoint = golden.events.find((e) => e.type === "checkpoint");
  if (!checkpoint) continue;

  let save;
  try {
    const story = new Story(fs.readFileSync(`${base}.json`, "utf-8"));
    story.onError = () => {};
    story.state.storySeed = golden.seed;
    while (story.canContinue) story.Continue();
    if (story.currentChoices.length === 0) continue;
    save = story.state.toJson();
  } catch {
    continue;
  }

  if (same(JSON.parse(save), JSON.parse(checkpoint.state))) {
    fs.writeFileSync(out, save + "\n");
    kept++;
  } else {
    differs++;
  }
}

console.log(`kept ${kept} inkjs saves; ${differs} differ from C#'s state`);
