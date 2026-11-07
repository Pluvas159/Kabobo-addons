// Runs every addon's tests outside the game.
//
//   npm test                    all addons
//   npm test -- PluvasAuctions  only the named addon(s)
//
// For each addon in addons/<Name>/<Name>.toc:
//   1. every .lua file listed in the TOC is syntax-checked as Lua 5.1 (the game's dialect)
//   2. a fresh Lua VM (fengari) loads tests/lib/mocks.lua and tests/lib/harness.lua, then the
//      addon's files in TOC order with the usual (addonName, namespace) arguments
//   3. every tests/<Name>/*.lua file runs, in name order
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const repo = path.join(__dirname, "..");
const addonsDir = path.join(repo, "addons");
const libDir = path.join(__dirname, "lib");
const only = process.argv.slice(2);

function tocFiles(addon) {
  const toc = fs.readFileSync(path.join(addonsDir, addon, `${addon}.toc`), "utf8");
  return toc
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => l.replace(/\\/g, "/"));
}

function syntaxCheck(addon, files) {
  let ok = true;
  for (const f of files.filter((f) => f.endsWith(".lua"))) {
    try {
      luaparse.parse(fs.readFileSync(path.join(addonsDir, addon, f), "utf8"), { luaVersion: "5.1" });
    } catch (e) {
      ok = false;
      console.error(`  syntax error in ${addon}/${f}: ${e.message}`);
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

const addons = fs
  .readdirSync(addonsDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(addonsDir, d.name, `${d.name}.toc`)))
  .map((d) => d.name)
  .filter((name) => only.length === 0 || only.includes(name));

if (addons.length === 0) {
  console.error(only.length ? `no addon named ${only.join(", ")}` : "no addons found");
  process.exit(1);
}

let totalPassed = 0;
let totalFailed = 0;
let broken = false;

for (const addon of addons) {
  console.log(addon);
  const files = tocFiles(addon);
  if (!syntaxCheck(addon, files)) {
    broken = true;
    continue;
  }

  const testDir = path.join(__dirname, addon);
  const tests = fs.existsSync(testDir)
    ? fs.readdirSync(testDir).filter((f) => f.endsWith(".lua")).sort()
    : [];

  const L = newState();
  try {
    run(L, path.join(libDir, "mocks.lua"));
    run(L, path.join(libDir, "harness.lua"));
    const addonArgs = [
      () => lua.lua_pushstring(L, to_luastring(addon)),
      () => lua.lua_getglobal(L, to_luastring("_NS")),
    ];
    for (const f of files) {
      if (f.endsWith(".lua")) run(L, path.join(addonsDir, addon, f), addonArgs);
      else console.log(`  (skipped ${f}: only .lua files are loaded in tests)`);
    }
    for (const t of tests) run(L, path.join(testDir, t));
  } catch (e) {
    console.error(`  error: ${e.message}`);
    broken = true;
    continue;
  }

  const r = results(L);
  totalPassed += r.passed;
  totalFailed += r.failed;
  const note = tests.length === 0 ? " (no tests yet: add tests/" + addon + "/tests.lua)" : "";
  console.log(`  ${files.length} files ok, ${r.passed} passed, ${r.failed} failed${note}`);
}

console.log(`\n${addons.length} addon(s): ${totalPassed} passed, ${totalFailed} failed`);
if (broken || totalFailed > 0) process.exit(1);
