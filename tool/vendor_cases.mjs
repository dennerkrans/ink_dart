// One-off: copy inkjs's .ink test stories into packages/ink_dart/test/conformance/cases/,
// grouped by the phase whose runtime can run them.
//
// Usage: node tool/vendor_cases.mjs path/to/inkjs-checkout
//
// Stories that fail to compile are compiler tests (out of scope) and are
// listed, not copied. Compiler-only folders (`*/compiler/`) are skipped.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { compileInk, detectFeatures, phaseFor } from "./ink.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const casesDir = path.resolve(here, "../packages/ink_dart/test/conformance/cases");

const inkjsRoot = process.argv[2];
if (!inkjsRoot) {
  console.error("usage: node tool/vendor_cases.mjs path/to/inkjs-checkout");
  process.exit(64);
}
const original = path.join(inkjsRoot, "src/tests/inkfiles/original");
const upstreamCompiled = path.join(inkjsRoot, "src/tests/inkfiles/compiled");

const skipped = [];
const failed = [];
const mismatched = [];
const counts = {};

for (const category of fs.readdirSync(original).sort()) {
  const dir = path.join(original, category);
  if (!fs.statSync(dir).isDirectory()) continue;
  for (const entry of fs.readdirSync(dir).sort()) {
    const full = path.join(dir, entry);
    if (fs.statSync(full).isDirectory()) {
      if (entry !== "includes") skipped.push(`${category}/${entry}/`);
      continue;
    }
    if (!entry.endsWith(".ink")) continue;
    const name = entry.slice(0, -".ink".length);
    const { json, errors } = compileInk(full);
    if (json === null) {
      const error = (errors[0] ?? "no output").split(original).join("");
      failed.push(`${category}/${entry}: ${error}`);
      continue;
    }
    const upstream = path.join(upstreamCompiled, category, `${entry}.json`);
    if (fs.existsSync(upstream)) {
      const expected = fs.readFileSync(upstream, "utf-8").replace(/^\uFEFF/, "");
      // inkjs's checked-in JSON predates inkVersion 21; compare the rest.
      const strip = (s) => s.replace(/^\{"inkVersion":\d+,/, "{");
      if (strip(expected) !== strip(json)) {
        mismatched.push(`${category}/${entry}`);
      }
    }
    const phase = phaseFor(category, detectFeatures(JSON.parse(json)));
    const dest = path.join(casesDir, `phase${phase}`, category);
    fs.mkdirSync(dest, { recursive: true });
    fs.copyFileSync(full, path.join(dest, `${name}.ink`));
    const source = fs.readFileSync(full, "utf-8");
    if (/^\s*INCLUDE\b/m.test(source)) {
      fs.cpSync(path.join(dir, "includes"), path.join(dest, "includes"), {
        recursive: true,
      });
    }
    counts[`phase${phase}`] = (counts[`phase${phase}`] ?? 0) + 1;
  }
}

console.log("vendored:", counts);
console.log(`\nskipped folders (${skipped.length}):`);
for (const s of skipped) console.log(`  ${s}`);
console.log(`\nfailed to compile, not vendored (${failed.length}):`);
for (const f of failed) console.log(`  ${f}`);
console.log(`\ncompiled JSON differs from inkjs's checked-in JSON (${mismatched.length}):`);
for (const m of mismatched) console.log(`  ${m}`);
