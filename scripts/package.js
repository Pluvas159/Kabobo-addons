// Builds release zips from the last commit (not the working tree), into dist/.
//
//   npm run package
//
// For each addon: dist/<Name>-<version>.zip with <Name>/ at its root, the layout CurseForge,
// Wago and Interface\AddOns expect. Plus dist/kabobo-addons-<release>.zip with every addon, for
// friends who want them all in one go. <version> comes from the addon's TOC; <release> is the
// first argument, or the highest addon version.
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const repo = path.join(__dirname, "..");
const addonsDir = path.join(repo, "addons");
const dist = path.join(repo, "dist");
const git = (...args) => execFileSync("git", args, { cwd: repo, encoding: "utf8" }).trim();

if (git("status", "--porcelain", "--", "addons")) {
  console.warn("warning: addons/ has uncommitted changes; the zips hold the last commit only.\n");
}

const addons = fs.readdirSync(addonsDir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && fs.existsSync(path.join(addonsDir, d.name, `${d.name}.toc`)))
  .map((d) => {
    const toc = fs.readFileSync(path.join(addonsDir, d.name, `${d.name}.toc`), "utf8");
    const version = (toc.match(/^##\s*Version:\s*(\S+)/m) || [])[1];
    if (!version) throw new Error(`${d.name}.toc has no ## Version`);
    return { name: d.name, version };
  });

const newer = (a, b) => {
  const pa = a.split(".").map(Number), pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0);
  }
  return false;
};
const release = process.argv[2] || addons.map((a) => a.version).reduce((a, b) => (newer(b, a) ? b : a));

fs.mkdirSync(dist, { recursive: true });
const made = [];
for (const a of addons) {
  const out = path.join(dist, `${a.name}-${a.version}.zip`);
  git("archive", "--format=zip", `--prefix=${a.name}/`, "-o", out, `HEAD:addons/${a.name}`);
  made.push(out);
}
const all = path.join(dist, `kabobo-addons-${release}.zip`);
git("archive", "--format=zip", "-o", all, "HEAD:addons");
made.push(all);

for (const f of made) console.log(`${path.relative(repo, f)}  (${Math.round(fs.statSync(f).size / 1024)} KB)`);
