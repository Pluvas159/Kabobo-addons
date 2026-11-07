// Runs every addon's tests outside the game.
//
//   npm test                    all addons and shared libraries
//   npm test -- PluvasAuctions  only the named addon(s) or library(ies)
//
// For each addon in addons/<Name>/<Name>.toc:
//   0. the TOC is checked for the shared metadata (Category "Pluvas' addons", Interface 16001, ...)
//   1. embedded shared libraries (addons/<Name>/Libs/<Lib>) must match shared/<Lib> exactly
//   2. every .lua file the TOC loads (directly or through an .xml include) is syntax-checked as
//      Lua 5.1 (the game's dialect)
//   3. a fresh Lua VM (fengari) loads tests/lib/mocks.lua and tests/lib/harness.lua, then the
//      addon's files in load order with the usual (addonName, namespace) arguments
//   4. every tests/<Name>/*.lua file runs, in name order
// Each shared library in shared/<Lib>/<Lib>.xml is loaded the same way on its own and runs
// tests/shared/<Lib>/*.lua.
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const repo = path.join(__dirname, "..");
const addonsDir = path.join(repo, "addons");
const sharedDir = path.join(repo, "shared");
const libDir = path.join(__dirname, "lib");
const only = process.argv.slice(2);

// Script files an .xml file includes (<Script file=.../> and nested <Include file=.../>), as
// paths relative to baseDir, in load order.
function xmlScripts(baseDir, xmlRel) {
  const xml = fs.readFileSync(path.join(baseDir, xmlRel), "utf8").replace(/<!--[\s\S]*?-->/g, "");
  const dir = path.posix.dirname(xmlRel.replace(/\\/g, "/"));
  const out = [];
  const re = /<(Script|Include)\s+file\s*=\s*"([^"]+)"/g;
  let m;
  while ((m = re.exec(xml))) {
    const rel = path.posix.normalize(path.posix.join(dir, m[2].replace(/\\/g, "/")));
    if (m[1] === "Include") out.push(...xmlScripts(baseDir, rel));
    else out.push(rel);
  }
  return out;
}

// Files the game loads for an addon, in order, with .xml includes expanded.
function loadFiles(baseDir, entries) {
  const out = [];
  for (const f of entries) {
    if (f.toLowerCase().endsWith(".xml")) out.push(...xmlScripts(baseDir, f));
    else out.push(f);
  }
  return out;
}

function tocEntries(addon) {
  const toc = fs.readFileSync(path.join(addonsDir, addon, `${addon}.toc`), "utf8");
  return toc
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => l.replace(/\\/g, "/"));
}

// Every addon must carry the same metadata so it targets Forever and shows up under the
// "Pluvas' addons" header in the in-game AddOns list.
const CATEGORY = "Pluvas' addons";
const FOREVER_INTERFACE = "16001";

function tocCheck(addon) {
  const text = fs.readFileSync(path.join(addonsDir, addon, `${addon}.toc`), "utf8");
  const meta = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^##\s*([\w-]+)\s*:\s*(.*?)\s*$/);
    if (m && !(m[1] in meta)) meta[m[1]] = m[2];
  }
  const problems = [];
  if (meta.Category !== CATEGORY) problems.push(`## Category must be "${CATEGORY}" (is ${JSON.stringify(meta.Category)})`);
  const interfaces = (meta.Interface || "").split(",").map((s) => s.trim());
  if (!interfaces.includes(FOREVER_INTERFACE)) problems.push(`## Interface must include ${FOREVER_INTERFACE}`);
  for (const key of ["Title", "Notes", "Author", "Version"]) {
    if (!meta[key]) problems.push(`## ${key} is missing`);
  }
  for (const p of problems) console.error(`  ${addon}.toc: ${p}`);
  return problems.length === 0;
}

// Shared libraries: shared/<Lib>/ with a <Lib>.xml load file. Only these file types ship.
const SHIPPED = /\.(lua|xml)$/i;
const sharedLibs = fs.existsSync(sharedDir)
  ? fs.readdirSync(sharedDir, { withFileTypes: true })
      .filter((d) => d.isDirectory() && fs.existsSync(path.join(sharedDir, d.name, `${d.name}.xml`)))
      .map((d) => d.name)
  : [];

function shippedFiles(dir) {
  return fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => SHIPPED.test(f)).sort() : [];
}

// An embedded copy must be byte-identical to shared/<Lib>, and the TOC must load it.
function libCheck(addon, entries) {
  let ok = true;
  for (const lib of sharedLibs) {
    const copyDir = path.join(addonsDir, addon, "Libs", lib);
    if (!fs.existsSync(copyDir)) continue;
    const want = shippedFiles(path.join(sharedDir, lib));
    const have = shippedFiles(copyDir);
    const stale = want.filter(
      (f) => !have.includes(f) ||
        !fs.readFileSync(path.join(copyDir, f)).equals(fs.readFileSync(path.join(sharedDir, lib, f)))
    );
    const extra = have.filter((f) => !want.includes(f));
    if (stale.length || extra.length) {
      ok = false;
      const what = [...stale.map((f) => `${f} differs or is missing`), ...extra.map((f) => `${f} is not in shared/${lib}`)];
      console.error(`  Libs/${lib} is out of date (${what.join(", ")}). Edit shared/${lib}, then run: npm run sync`);
    }
    const load = `Libs/${lib}/${lib}.xml`;
    if (!entries.includes(load)) {
      ok = false;
      console.error(`  ${addon}.toc must load ${load.replace(/\//g, "\\")} before the addon's own files`);
    }
  }
  return ok;
}

function syntaxCheck(label, baseDir, files) {
  let ok = true;
  for (const f of files.filter((f) => f.endsWith(".lua"))) {
    try {
      luaparse.parse(fs.readFileSync(path.join(baseDir, f), "utf8"), { luaVersion: "5.1" });
    } catch (e) {
      ok = false;
      console.error(`  syntax error in ${label}/${f}: ${e.message}`);
    }
  }
  return ok;
}

function newState() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  return L;
}

function run(L, file, pushArgs = []) {
  const src = fs.readFileSync(file);
  const chunkName = to_luastring("@" + path.relative(repo, file).replace(/\\/g, "/"));
  if (lauxlib.luaL_loadbuffer(L, src, null, chunkName) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
  for (const push of pushArgs) push();
  if (lua.lua_pcall(L, pushArgs.length, 0, 0) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}

function results(L) {
  lua.lua_getglobal(L, to_luastring("_RESULTS"));
  lua.lua_getfield(L, -1, to_luastring("passed"));
  const passed = lua.lua_tointeger(L, -1);
  lua.lua_getfield(L, -2, to_luastring("failed"));
  const failed = lua.lua_tointeger(L, -1);
  lua.lua_pop(L, 3);
  return { passed, failed };
}

// Load files into a fresh VM as addon `name`, then run every test file in testDir.
function runSuite(name, baseDir, files, testDir) {
  const tests = fs.existsSync(testDir)
    ? fs.readdirSync(testDir).filter((f) => f.endsWith(".lua")).sort()
    : [];
  const L = newState();
  run(L, path.join(libDir, "mocks.lua"));
  run(L, path.join(libDir, "harness.lua"));
  const args = [
    () => lua.lua_pushstring(L, to_luastring(name)),
    () => lua.lua_getglobal(L, to_luastring("_NS")),
  ];
  for (const f of files) {
    if (f.endsWith(".lua")) run(L, path.join(baseDir, f), args);
    else console.log(`  (skipped ${f}: only .lua files are loaded in tests)`);
  }
  for (const t of tests) run(L, path.join(testDir, t));
  return { ...results(L), count: tests.length };
}

const addons = fs
  .readdirSync(addonsDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(addonsDir, d.name, `${d.name}.toc`)))
  .map((d) => d.name)
  .filter((name) => only.length === 0 || only.includes(name));
const libs = sharedLibs.filter((name) => only.length === 0 || only.includes(name));

if (addons.length + libs.length === 0) {
  console.error(only.length ? `no addon or library named ${only.join(", ")}` : "no addons found");
  process.exit(1);
}

let totalPassed = 0;
let totalFailed = 0;
let broken = 0;

function report(label, files, r, testsPath) {
  totalPassed += r.passed;
  totalFailed += r.failed;
  const note = r.count === 0 ? ` (no tests yet: add ${testsPath})` : "";
  console.log(`  ${files.length} files ok, ${r.passed} passed, ${r.failed} failed${note}`);
}

for (const lib of libs) {
  console.log(`${lib} (shared library)`);
  const baseDir = path.join(sharedDir, lib);
  try {
    const files = xmlScripts(baseDir, `${lib}.xml`);
    if (!syntaxCheck(`shared/${lib}`, baseDir, files)) { broken++; continue; }
    const r = runSuite(`${lib}Test`, baseDir, files, path.join(__dirname, "shared", lib));
    report(lib, files, r, `tests/shared/${lib}/tests.lua`);
  } catch (e) {
    console.error(`  error: ${e.message}`);
    broken++;
  }
}

for (const addon of addons) {
  console.log(addon);
  const baseDir = path.join(addonsDir, addon);
  try {
    const entries = tocEntries(addon);
    const files = loadFiles(baseDir, entries);
    const tocOk = tocCheck(addon);
    const libsOk = libCheck(addon, entries);
    if (!syntaxCheck(addon, baseDir, files) || !tocOk || !libsOk) { broken++; continue; }
    const r = runSuite(addon, baseDir, files, path.join(__dirname, addon));
    report(addon, files, r, `tests/${addon}/tests.lua`);
  } catch (e) {
    console.error(`  error: ${e.message}`);
    broken++;
  }
}

const n = addons.length + libs.length;
const brokenNote = broken ? `, ${broken} BROKEN (see errors above)` : "";
console.log(`\n${n} suite(s): ${totalPassed} passed, ${totalFailed} failed${brokenNote}`);
if (broken || totalFailed > 0) process.exit(1);
