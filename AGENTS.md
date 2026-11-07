# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, ...) and humans working in this repo.

## What this is

**Pluvas' addons** is a monorepo of World of Warcraft addons for **World of Warcraft: Forever**,
written by Pluvas. Each addon is self-contained and ships on its own.

| Addon | Folder | What it does |
| --- | --- | --- |
| Pluvas' Auctions | `addons/PluvasAuctions` | AH price scanning and history in tooltips, plus a sales, profit and gold ledger |

Add new addons to this table.

## Rules every addon follows

1. **Its TOC sits in the "Pluvas' addons" category**: `## Category: Pluvas' addons`, spelled
   exactly like that. The in-game AddOns list then shows all our addons together under one
   collapsible "Pluvas' addons" header. Use `Category`, not `## Group:`, because a Group needs a
   main addon to hang the others under, and we do not have one.
2. **Its TOC carries the shared metadata**: `## Interface` including `16001`, plus `## Title`,
   `## Notes`, `## Author: Pluvas` and `## Version`.
3. **It is symlinked into the game.** `scripts/install.ps1` symlinks *every* addon in `addons/`
   into the Forever client's `Interface\AddOns`. Rerun it after adding, renaming or removing an
   addon.

`npm test` fails if rule 1 or 2 is broken. `scripts/new-addon.ps1` creates addons that already
follow all three.

## Target client: read this first

Forever looks like Classic but runs on the **modern Mainline 12.x (Midnight) client**:

- TOC: `## Interface: 16001` (game build 1.60.1).
- Use the **Retail API**: `C_AuctionHouse`, `C_Item`, `C_Container`, `C_AddOns`,
  `TooltipDataProcessor`. Classic Era APIs (`QueryAuctionItems`, `GetAuctionItemInfo`,
  `OnTooltipSetItem`, ...) do not exist here.
- Lua is 5.1: no `goto`, no `//`, no bitwise operators, no integer division.
- The combat log is closed and some combat values are "secret". AH posts, bids, buyouts and
  cancels each need a hardware event, so never automate them.
- An AH full scan (`ReplicateItems`) is allowed once per account every 15 minutes.

Details and API signatures are in [docs/forever-client.md](docs/forever-client.md). When you
confirm or disprove something about the client, update that file.

## Layout

```
addons/<Name>/          one folder per addon, installed into the game as-is
  <Name>.toc            folder name must equal the TOC name
  *.lua
tests/
  run.js                test runner (Node + fengari Lua VM + luaparse)
  lib/mocks.lua         WoW API stand-ins shared by all addons
  lib/harness.lua       test(), eq(), near(), truthy()
  <Name>/*.lua          tests for one addon
scripts/
  install.ps1           symlink every addon into the Forever client
  new-addon.ps1         scaffold a new addon + its tests
docs/                   client notes and other docs
```

Only files listed in an addon's TOC are loaded by the game. Keep dev-only files (tests, notes,
build output) **out of** `addons/<Name>/`, since that folder is what gets installed and published.
The one exception is a short `README.md` for the addon.

## Commands

```sh
npm install                      # once: dev dependencies for tests
npm test                         # syntax-check + test every addon
npm test -- PluvasAuctions       # one addon
powershell -ExecutionPolicy Bypass -File scripts/install.ps1          # symlink every addon into WoW
powershell -ExecutionPolicy Bypass -File scripts/install.ps1 -Status  # show what is installed
powershell -ExecutionPolicy Bypass -File scripts/new-addon.ps1 -Name PluvasThing -Title "Pluvas' Thing"
```

The install script defaults to `D:\World of Warcraft\_forever_`. Override it with `-WowPath` or
`WOW_FOREVER_PATH`. What it does:

- It creates directory **symbolic links** (`mklink /D`), which works without admin because
  Windows Developer Mode is on. If symlinks are not allowed, it falls back to junctions and says so.
- Running it again is safe. Correct links are left alone, junctions and wrong links are replaced,
  an old copied folder is moved to `Interface\AddOns.backup\`, and links to addons that no
  longer exist in the repo are removed.
- It never touches addons that do not come from this repo.
- Other options: `-Addon X` (only that addon), `-Copy` (copy the files), `-Uninstall`.

Edits are live after `/reload` in game. Newly added addon folders need a game restart.

## Code conventions

- **Namespace**: start each file with `local ADDON, ns = ...` (or `local _, ns = ...`). Share code
  through `ns`. The only globals allowed are SavedVariables, `SLASH_*`/`SlashCmdList` entries, and
  named frames, all prefixed with the addon name (`PluvasAuctionsDB`, `PluvasAuctionsFrame`).
- **Modules**: Pluvas' Auctions uses `ns:NewModule(name)` with optional `OnInit` (after
  SavedVariables load), `OnLogin` and `OnLogout`. Follow the same pattern in new addons when they
  grow past one file.
- **Events**: register through `ns:On(event, fn)`. It `pcall`s `RegisterEvent`, because unknown
  events raise errors on the modern client, and it `pcall`s handlers so one bug cannot break the
  rest.
- **Saved variables**: merge defaults on load, keep a `dbVersion` for migrations, and keep keys
  short in tables that grow per item (they are written to disk every logout).
- **Taint**: never overwrite Blizzard functions or secure frames. Use `hooksecurefunc` /
  `HookScript`. Do not touch protected actions in combat.
- **Performance**: spread heavy loops (e.g. full AH scans) over frames with `C_Timer.After(0, ...)`.
- **Style**: tabs for Lua and TOC files (see `.editorconfig`). Comment why, not what. Keep pure
  logic (math, parsing, matching) in functions that do not read game state, so it can be tested.
- Timestamps: `time()`. Money: copper integers, formatted only for display.

## Testing

`npm test` does three things for every addon:

1. It checks the TOC metadata against the rules above (category, interface, title, ...).
2. It parses each TOC-listed `.lua` file as **Lua 5.1**, which catches syntax the game would reject.
3. It loads the addon into a fengari VM with `tests/lib/mocks.lua` and runs `tests/<Name>/*.lua`.

Notes:
- fengari is **Lua 5.3**, so a few behaviours differ from the game. `unpack` is aliased in the
  mocks. Float formatting differs (`1.0` vs `1`), so floor numbers before concatenating them.
- Add mocks to `tests/lib/mocks.lua` as needed. Keep them generic, since every addon shares them.
  Fire events with `_FIRE(event, ...)`. Timers run on a virtual clock via `_RUN_TIMERS()`.
- UI frames are not covered. After UI changes, check in game: `/reload`, and run
  `/console scriptErrors 1` to see Lua errors (or use BugSack).

Run `npm test` before you report work as done. If you could not verify something in game, say so.

## Releasing an addon

- Bump `## Version` in the addon's TOC and note the change in its README.
- To publish, zip the `addons/<Name>` folder so the zip contains `<Name>/` at its root.
  Upload it to CurseForge or Wago with the game version set to WoW: Forever.

## Git

- The default branch is `master`. Use short, imperative commit messages that start with the
  addon name when the change is scoped, e.g. `PluvasAuctions: track expired deposits`.
- Never commit `node_modules/`.
