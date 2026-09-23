// Shared helpers for the conformance tooling: compile .ink with the pinned
// inkjs compiler, and classify a compiled story by the phase that can run it.

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

// The unbundled CommonJS build, not `inkjs/full`: compiler, runtime and
// SimpleJson must share one module instance for the patch below to reach
// both the compiled story JSON and state.toJson().
const require = createRequire(import.meta.url);
const { SimpleJson } = require("inkjs/engine/SimpleJson");
export const { Compiler, CompilerOptions, Story } = require(
  "inkjs/compiler/Compiler",
);

// inkjs 2.4.0's SimpleJson.Writer.WriteFloat hands the number to
// JSON.stringify, so a whole float comes out as `3`, not `3.0`; inkjs's own
// Reader then loads it as an int. The compiler turns `7 / 3.0` into integer
// division, and saves drop the type of whole float variables. The C#
// reference (SimpleJson.cs WriteFloat) appends ".0", as did the inklecate
// output inkjs's test suite checks in; this patch restores that, so the
// oracle is inkjs's runtime writing C#-compatible JSON.
const floatMarker = "\u0001inkfloat:";
const Writer = SimpleJson.Writer;
const writeFloat = Writer.prototype.WriteFloat;
Writer.prototype.WriteFloat = function (value) {
  if (value !== null && Number.isFinite(value)) {
    const text = String(value);
    if (!/[.e]/.test(text)) {
      this.StartNewObject(false);
      this._addToCurrentObject(`${floatMarker}${text}.0`);
      return;
    }
  }
  return writeFloat.call(this, value);
};
const writerToString = Writer.prototype.toString;
Writer.prototype.toString = function () {
  return writerToString
    .call(this)
    .replace(/"\\u0001inkfloat:([^"]+)"/g, "$1");
};

// Stories inkjs's own test suite compiles with `-c` (count all visits).
export const countAllVisitsFiles = new Set([
  "visit_counts_when_choosing.ink",
  "turns_since_with_variable_target.ink",
  "read_count_variable_target.ink",
  "tests.ink",
]);

// Compiles the .ink file at [inkPath]. Returns `{json, errors, warnings}`;
// `json` is null when compilation failed.
export function compileInk(inkPath) {
  const errors = [];
  const warnings = [];
  const dir = path.dirname(inkPath);
  const fileHandler = {
    ResolveInkFilename: (filename) => path.resolve(dir, filename),
    LoadInkFileContents: (filename) => fs.readFileSync(filename, "utf-8"),
  };
  const errorHandler = (message, type) => {
    // ErrorType: Author = 0, Warning = 1, Error = 2.
    if (type === 2) errors.push(message);
    else warnings.push(message);
  };
  const options = new CompilerOptions(
    inkPath,
    [],
    countAllVisitsFiles.has(path.basename(inkPath)),
    errorHandler,
    fileHandler,
  );
  const source = fs.readFileSync(inkPath, "utf-8").replace(/^\uFEFF/, "");
  let json = null;
  try {
    const story = new Compiler(source, options).Compile();
    if (story && errors.length === 0) json = story.ToJson();
  } catch (e) {
    errors.push(String(e && e.message ? e.message : e));
  }
  return { json, errors, warnings };
}

const listCommands = new Set(["listInt", "range", "lrnd"]);
const listFunctions = new Set([
  "L^", "LIST_MIN", "LIST_MAX", "LIST_ALL", "LIST_COUNT", "LIST_VALUE",
  "LIST_INVERT",
]);

// Walks the compiled JSON and reports which runtime features it uses.
export function detectFeatures(compiled) {
  const features = new Set();
  const lists = compiled.listDefs;
  if (lists && Object.keys(lists).length > 0) features.add("lists");
  const walk = (token) => {
    if (typeof token === "string") {
      if (token === "thread") features.add("threads");
      else if (listCommands.has(token) || listFunctions.has(token)) {
        features.add("lists");
      } else if (token === "#" || token === "/#") features.add("tags");
    } else if (Array.isArray(token)) {
      token.forEach(walk);
    } else if (token && typeof token === "object") {
      if ("list" in token) features.add("lists");
      if ("#" in token) features.add("tags");
      if ("x()" in token) features.add("externals");
      for (const v of Object.values(token)) walk(v);
    }
  };
  walk(compiled.root);
  return features;
}

// Phase a category belongs to by default (see CLAUDE.md "Phases").
export const categoryPhase = {
  bindings: 2,
  tags: 2,
  inkjs: 2,
  lists: 3,
  threads: 3,
  multiflow: 4,
};

// The first phase whose runtime can run a story with [features].
export function phaseFor(category, features) {
  let phase = categoryPhase[category] ?? 1;
  if (features.has("tags") || features.has("externals")) {
    phase = Math.max(phase, 2);
  }
  if (features.has("lists") || features.has("threads")) {
    phase = Math.max(phase, 3);
  }
  return phase;
}
