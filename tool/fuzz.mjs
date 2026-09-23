// Differential fuzzer: random runs over the conformance corpus, played by
// the C# runtime (tool/oracle --runs) and by ink_dart
// (packages/ink_dart/test/fuzz/run_batch.dart); any difference in events or
// final save is a bug in the port.
//
// Usage: node tool/fuzz.mjs [runs=500] [seed=1]
//
// A run takes a random story, keeps the configuration ops of its script
// (external bindings, observers, fallbacks) so the story can play, then adds
// random ops: choose a random choice, continue, save and reload into a fresh
// story, jump to a random knot, switch flow, reset. Runs are deterministic in
// the seed, so a failure reproduces with the same arguments. Failures are
// written to tool/fuzz-failures/ (git-ignored) as a runs file that replays
// just them. Needs the .NET 10 SDK and the Dart SDK; not run in CI.

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const pkg = path.resolve(here, "../packages/ink_dart");
const casesDir = path.join(pkg, "test/conformance/cases");
const failuresDir = path.join(here, "fuzz-failures");

const runCount = Number(process.argv[2] ?? 500);
const fuzzSeed = Number(process.argv[3] ?? 1);

// mulberry32: small, seeded, good enough to pick ops.
function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const random = rng(fuzzSeed);
const int = (n) => Math.floor(random() * n);
const pick = (xs) => xs[int(xs.length)];

function listGoldens(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...listGoldens(full));
    else if (e.name.endsWith(".golden.json")) out.push(full);
  }
  return out.sort();
}

const configOps = new Set(["bind", "unbind", "observe", "allowExternalFunctionFallbacks"]);
const stories = listGoldens(casesDir).map((goldenPath) => {
  const base = goldenPath.slice(0, -".golden.json".length);
  const golden = JSON.parse(fs.readFileSync(goldenPath, "utf-8"));
  const compiled = JSON.parse(fs.readFileSync(`${base}.json`, "utf-8"));
  const named = compiled.root[compiled.root.length - 1] ?? {};
  const knots = Object.keys(named).filter((k) => !k.startsWith("#") && k !== "global decl");
  return {
    name: golden.case,
    story: `${base}.json`,
    config: (golden.script ?? []).filter((op) => configOps.has(op.op)),
    knots,
  };
});

function randomScript(story) {
  const ops = [...story.config, { op: "continueMaximally" }];
  const length = 5 + int(40);
  for (let i = 0; i < length; i++) {
    const r = random();
    if (r < 0.5) ops.push({ op: "chooseRandom", seed: int(0x7fffffff) });
    else if (r < 0.62) ops.push({ op: "continueMaximally" });
    else if (r < 0.7) ops.push({ op: "continue" });
    else if (r < 0.82) ops.push({ op: "saveReload" });
    else if (r < 0.9 && story.knots.length > 0) {
      ops.push({ op: "choosePathString", path: pick(story.knots), resetCallstack: random() < 0.8 });
    } else if (r < 0.95) {
      ops.push(random() < 0.3 ? { op: "switchToDefaultFlow" } : { op: "switchFlow", name: pick(["A", "B"]) });
    } else if (r < 0.98) ops.push({ op: "save", slot: "s" }, { op: "load", slot: "s" });
    else ops.push({ op: "resetState" });
    if (random() < 0.4) ops.push({ op: "continueMaximally" });
  }
  return ops;
}

const runs = [];
for (let i = 0; i < runCount; i++) {
  const story = pick(stories);
  runs.push({
    name: `${i}:${story.name}`,
    story: story.story,
    seed: int(0x7fffffff),
    script: randomScript(story),
  });
}

const tmp = fs.mkdtempSync(path.join(fs.realpathSync("/tmp"), "ink-fuzz-"));
const runsPath = path.join(tmp, "runs.json");
fs.writeFileSync(runsPath, JSON.stringify(runs));

function run(cmd, args, opts) {
  const r = spawnSync(cmd, args, { stdio: ["ignore", "inherit", "inherit"], ...opts });
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")} failed`);
}
const csOut = path.join(tmp, "cs.json");
const dartOut = path.join(tmp, "dart.json");
run("dotnet", ["run", "--project", path.join(here, "oracle"), "-c", "Release", "-v", "q", "--", "--runs", runsPath, csOut]);
run("dart", ["run", "test/fuzz/run_batch.dart", runsPath, dartOut], { cwd: pkg });

const cs = JSON.parse(fs.readFileSync(csOut, "utf-8"));
const dart = JSON.parse(fs.readFileSync(dartOut, "utf-8"));

const failures = [];
for (let i = 0; i < runs.length; i++) {
  const a = cs[i];
  const b = dart[i];
  const eventsA = a.events.map((e) => JSON.stringify(e));
  const eventsB = b.events.map((e) => JSON.stringify(e));
  let at = -1;
  for (let k = 0; k < Math.max(eventsA.length, eventsB.length); k++) {
    if (eventsA[k] !== eventsB[k]) {
      at = k;
      break;
    }
  }
  if (at >= 0 || a.finalState !== b.finalState) {
    failures.push({ run: runs[i], at, csharp: a.events[at], dart: b.events[at] });
  }
}

const eventCount = cs.reduce((n, r) => n + r.events.length, 0);
console.log(
  `${runs.length} runs, ${eventCount} events compared (seed ${fuzzSeed}): ` +
    `${failures.length} differ`,
);
if (failures.length > 0) {
  fs.mkdirSync(failuresDir, { recursive: true });
  const out = path.join(failuresDir, `seed-${fuzzSeed}.json`);
  fs.writeFileSync(out, JSON.stringify(failures, null, 1));
  for (const f of failures.slice(0, 10)) {
    console.log(`\n${f.run.name}: ${f.at < 0 ? "final state" : `event ${f.at}`}`);
    console.log(`  C#:   ${JSON.stringify(f.csharp)?.slice(0, 200)}`);
    console.log(`  Dart: ${JSON.stringify(f.dart)?.slice(0, 200)}`);
  }
  console.log(`\nwritten to ${path.relative(process.cwd(), out)}`);
  process.exitCode = 1;
}
fs.rmSync(tmp, { recursive: true });
