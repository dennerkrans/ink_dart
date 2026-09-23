// One-off: copy the stories inline in ink's C# test suite (tests/Tests.cs in
// inkle/ink) into test/conformance/cases/, grouped by phase, skipping any
// whose test name inkjs's corpus already covers.
//
// Usage: node tool/vendor_ink_tests.mjs path/to/ink-checkout
//
// A test's story is each `CompileString(@"...")` in its method (a second
// one gets a `_2` suffix). `CompileStringWithoutRuntime` tests are compiler
// tests and are skipped, as are stories that fail to compile, use INCLUDE,
// or build the story from pieces rather than one literal.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compileInk, detectFeatures, phaseFor } from "./ink.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const casesDir = path.resolve(here, "../test/conformance/cases");
const category = "ink-tests";

const inkRoot = process.argv[2];
if (!inkRoot) {
  console.error("usage: node tool/vendor_ink_tests.mjs path/to/ink-checkout");
  process.exit(64);
}
const source = fs.readFileSync(path.join(inkRoot, "tests/Tests.cs"), "utf-8");

// Stories already in the corpus, by name (ignoring underscores) and by
// content (ignoring whitespace), from any phase and category.
const squash = (name) => name.replace(/_/g, "");
const normalise = (ink) => ink.replace(/\s+/g, " ").trim();
const existing = new Set();
const existingContent = new Set();
(function walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full);
    else if (e.name.endsWith(".ink") && !e.name.startsWith(".")) {
      existing.add(squash(e.name.slice(0, -4)));
      existingContent.add(normalise(fs.readFileSync(full, "utf-8")));
    }
  }
})(casesDir);

const snake = (name) =>
  name
    .replace(/^Test/, "")
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z])([A-Z][a-z])/g, "$1_$2")
    .toLowerCase();

// Reads a C# verbatim string starting at the opening quote.
function readVerbatim(text, start) {
  let out = "";
  for (let i = start + 1; i < text.length; i++) {
    if (text[i] === '"') {
      if (text[i + 1] === '"') {
        out += '"';
        i++;
      } else {
        return out;
      }
    } else {
      out += text[i];
    }
  }
  return null;
}

const methods = [...source.matchAll(/public void (Test\w+)\s*\(\)/g)];
const report = { vendored: {}, covered: [], skipped: [], failed: [] };

for (let m = 0; m < methods.length; m++) {
  const name = methods[m][1];
  const body = source.slice(
    methods[m].index,
    m + 1 < methods.length ? methods[m + 1].index : source.length,
  );
  const base = snake(name);

  if (existing.has(squash(base))) {
    report.covered.push(base);
    continue;
  }
  if (!/\bCompileString\s*\(/.test(body)) {
    report.skipped.push(`${base}: compiler-only test`);
    continue;
  }
  // Every verbatim literal in the method: stories are either passed straight
  // to CompileString or held in a variable first.
  const stories = [...body.matchAll(/@"/g)]
    .map((c) => readVerbatim(body, c.index + 1))
    .filter((ink) => ink !== null && ink.trim().length > 0)
    .filter((ink) => !existingContent.has(normalise(ink)));
  if (stories.length === 0) {
    report.skipped.push(`${base}: story already in the corpus`);
    continue;
  }

  stories.forEach((ink, i) => {
    const caseName = i === 0 ? base : `${base}_${i + 1}`;
    if (/^\s*INCLUDE\b/m.test(ink)) {
      report.skipped.push(`${caseName}: uses INCLUDE`);
      return;
    }
    const tmp = path.join(casesDir, `.${caseName}.ink`);
    fs.writeFileSync(tmp, ink.replace(/^\n/, ""));
    const { json, errors } = compileInk(tmp);
    if (json === null) {
      fs.rmSync(tmp);
      report.failed.push(`${caseName}: ${errors[0] ?? "no output"}`);
      return;
    }
    const phase = phaseFor(category, detectFeatures(JSON.parse(json)));
    const dest = path.join(casesDir, `phase${phase}`, category);
    fs.mkdirSync(dest, { recursive: true });
    fs.renameSync(tmp, path.join(dest, `${caseName}.ink`));
    report.vendored[`phase${phase}`] = (report.vendored[`phase${phase}`] ?? 0) + 1;
  });
}

console.log("vendored:", report.vendored);
console.log(`already covered by inkjs's corpus: ${report.covered.length}`);
console.log(`\nskipped (${report.skipped.length}):`);
for (const s of report.skipped) console.log(`  ${s}`);
console.log(`\nfailed to compile, not vendored (${report.failed.length}):`);
for (const f of report.failed) console.log(`  ${f.split("\n")[0].slice(0, 160)}`);
