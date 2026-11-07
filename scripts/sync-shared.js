// Copies shared libraries into the addons that embed them.
//
//   npm run sync                                          refresh every embedded copy
//   node scripts/sync-shared.js --embed KaboboX           embed every shared library into an addon
//   node scripts/sync-shared.js --embed KaboboX KaboboUI  embed only the named ones
//
// shared/<Lib>/ is the only place a library is edited. Each addon carries its own copy in
// addons/<Name>/Libs/<Lib>/ so it still ships on its own; `npm test` fails when a copy differs.
// Only .lua and .xml files are copied (no README).
const fs = require("fs");
const path = require("path");

const repo = path.join(__dirname, "..");
const sharedDir = path.join(repo, "shared");
const addonsDir = path.join(repo, "addons");
const SHIPPED = /\.(lua|xml)$/i;

// Load order: KaboboCore (the runtime) first, then the rest by name.
const libs = fs.readdirSync(sharedDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(sharedDir, d.name, `${d.name}.xml`)))
  .map((d) => d.name)
  .sort((a, b) => (a === "KaboboCore" ? -1 : b === "KaboboCore" ? 1 : a.localeCompare(b)));

// Make dest hold exactly the shipped files of src. Returns the number of files changed.
function mirror(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  const want = fs.readdirSync(src).filter((f) => SHIPPED.test(f));
  let changed = 0;
  for (const f of want) {
    const from = path.join(src, f);
    const to = path.join(dest, f);
    if (!fs.existsSync(to) || !fs.readFileSync(to).equals(fs.readFileSync(from))) {
      fs.copyFileSync(from, to);
      changed++;
    }
  }
  for (const f of fs.readdirSync(dest)) {
    if (!want.includes(f)) {
      fs.rmSync(path.join(dest, f), { recursive: true, force: true });
      changed++;
    }
  }
  return changed;
}

// Add "Libs\<Lib>\<Lib>.xml" to the TOC if it is not there: after the libraries it already
// loads, or else before the first file line. Embedding in `libs` order keeps KaboboCore first.
function addToToc(addon, lib) {
  const tocPath = path.join(addonsDir, addon, `${addon}.toc`);
  const lines = fs.readFileSync(tocPath, "utf8").split("\n");
  const norm = (l) => l.trim().replace(/\//g, "\\");
  const entry = ["Libs", lib, `${lib}.xml`].join("\\");
  if (lines.some((l) => norm(l) === entry)) return false;
  let at = -1;
  lines.forEach((l, i) => { if (norm(l).startsWith("Libs\\")) at = i + 1; });
  if (at === -1) at = lines.findIndex((l) => l.trim() && !l.trim().startsWith("#"));
  if (at === -1) lines.push(entry);
  else lines.splice(at, 0, entry);
  fs.writeFileSync(tocPath, lines.join("\n"));
  return true;
}

const args = process.argv.slice(2);
if (args[0] === "--embed") {
  const addon = args[1];
  const wanted = args.length > 2 ? args.slice(2) : libs;
  if (!addon || !fs.existsSync(path.join(addonsDir, addon, `${addon}.toc`))) {
    console.error(`no addon named ${addon}`);
    process.exit(1);
  }
  const unknown = wanted.filter((l) => !libs.includes(l));
  if (unknown.length) {
    console.error(`no shared library named ${unknown.join(", ")}`);
    process.exit(1);
  }
  for (const lib of libs.filter((l) => wanted.includes(l))) {
    mirror(path.join(sharedDir, lib), path.join(addonsDir, addon, "Libs", lib));
    const added = addToToc(addon, lib);
    console.log(`${addon}: embedded ${lib}${added ? " and added it to the TOC" : ""}`);
  }
} else {
  let total = 0;
  for (const addon of fs.readdirSync(addonsDir)) {
    for (const lib of libs) {
      const dest = path.join(addonsDir, addon, "Libs", lib);
      if (!fs.existsSync(dest)) continue;
      const changed = mirror(path.join(sharedDir, lib), dest);
      total += changed;
      console.log(`${addon}: ${lib} ${changed ? `updated (${changed} file(s))` : "up to date"}`);
    }
  }
  if (total === 0) console.log("Everything up to date.");
}
