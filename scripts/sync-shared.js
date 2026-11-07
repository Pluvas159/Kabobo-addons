// Copies shared libraries into the addons that embed them.
//
//   npm run sync                                   refresh every embedded copy
//   node scripts/sync-shared.js --embed PluvasX    embed PluvasUI into an addon (and its TOC)
//   node scripts/sync-shared.js --embed PluvasX OtherLib
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

const libs = fs.readdirSync(sharedDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(sharedDir, d.name, `${d.name}.xml`)))
  .map((d) => d.name);

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

// Add "Libs\<Lib>\<Lib>.xml" to the TOC, before the first file line, if it is not there.
function addToToc(addon, lib) {
  const tocPath = path.join(addonsDir, addon, `${addon}.toc`);
  const lines = fs.readFileSync(tocPath, "utf8").split("\n");
  const entry = `Libs\\${lib}\\${lib}.xml`;
  if (lines.some((l) => l.trim().replace(/\//g, "\\") === entry)) return false;
  const first = lines.findIndex((l) => l.trim() && !l.trim().startsWith("#"));
  if (first === -1) lines.push(entry);
  else lines.splice(first, 0, entry);
  fs.writeFileSync(tocPath, lines.join("\n"));
  return true;
}

const args = process.argv.slice(2);
if (args[0] === "--embed") {
  const addon = args[1];
  const lib = args[2] || "PluvasUI";
  if (!addon || !fs.existsSync(path.join(addonsDir, addon, `${addon}.toc`))) {
    console.error(`no addon named ${addon}`);
    process.exit(1);
  }
  if (!libs.includes(lib)) {
    console.error(`no shared library named ${lib}`);
    process.exit(1);
  }
  mirror(path.join(sharedDir, lib), path.join(addonsDir, addon, "Libs", lib));
  const added = addToToc(addon, lib);
  console.log(`${addon}: embedded ${lib}${added ? " and added it to the TOC" : ""}`);
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
