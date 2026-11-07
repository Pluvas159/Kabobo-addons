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
4. **Its UI is built with PluvasUI**, the shared UI library embedded in `Libs/PluvasUI`, so every
   addon looks and behaves the same. See [UI](#ui) below.

`npm test` fails if rule 1 or 2 is broken, or if an embedded PluvasUI copy differs from
`shared/PluvasUI`. `scripts/new-addon.ps1` creates addons that already follow all four.

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
  Libs/PluvasUI/        embedded copy of shared/PluvasUI (generated: never edit here)
shared/
  PluvasUI/             the shared UI library: the only place to edit it (README = UI rules)
tests/
  run.js                test runner (Node + fengari Lua VM + luaparse)
  lib/mocks.lua         WoW API stand-ins shared by all addons
  lib/harness.lua       test(), eq(), near(), truthy()
  <Name>/*.lua          tests for one addon
  shared/<Lib>/*.lua    tests for a shared library
scripts/
  install.ps1           symlink every addon into the Forever client
  new-addon.ps1         scaffold a new addon + its tests
  sync-shared.js        copy shared libraries into the addons that embed them
docs/                   client notes and other docs
```

Only files listed in an addon's TOC are loaded by the game. Keep dev-only files (tests, notes,
build output) **out of** `addons/<Name>/`, since that folder is what gets installed and published.
The one exception is a short `README.md` for the addon.

## Commands

```sh
npm install                      # once: dev dependencies for tests
npm test                         # syntax-check + test every addon
npm test -- PluvasAuctions       # one addon (or library: npm test -- PluvasUI)
npm run sync                     # after editing shared/: refresh every embedded copy
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
- **Crash safety**: Lua errors never crash the game, but calling a Blizzard C function outside the
  context it was built for can (`pcall` cannot catch that; see docs/forever-client.md). Tooltips
  and other hot paths read only saved data and plain item info. Call system APIs
  (`C_AuctionHouse`, `C_TradeSkillUI`, ...) only while their window is open, from events.
  Wrap hooks and callbacks in `ns:Guard(name, fn)`, which turns a feature off after repeated
  errors.
- **Performance**: spread heavy loops (e.g. full AH scans) over frames with `C_Timer.After(0, ...)`.
- **Style**: tabs for Lua and TOC files (see `.editorconfig`). Comment why, not what. Keep pure
  logic (math, parsing, matching) in functions that do not read game state, so it can be tested.
- Timestamps: `time()`. Money: copper integers, formatted only for display.

## UI

Every window, button, list and tooltip is built with **PluvasUI** (`ns.PluvasUI`). The full API
and style rules are in [shared/PluvasUI/README.md](shared/PluvasUI/README.md). In short:

- **Edit only `shared/PluvasUI`**, then run `npm run sync`. Each addon carries its own copy in
  `Libs/PluvasUI` (loaded first via `LibsPluvasUIPluvasUI.xml` in the TOC), so it still ships on
  its own. Copies attach to the addon's `ns` and create no globals, so addons never clash.
- **No hard-coded look in addon code**: colors (`PUI.Color(text, "good")`), fonts, sizes and
  templates come from `Style.lua`. A restyle is a change to that file.
- **Use the widgets**: `PUI.Window` (dockable, Escape handling, remembered position, Pluvas
  signature, footer), `PUI.List`, `PUI.TabBar`, `PUI.Button`, `PUI.ShowTooltip`/`SetTooltip`.
  If a widget is missing, add it to the library (with tests) rather than building one in an addon.
- **Lightweight**: build UI the first time it opens, not at load; no `OnUpdate` scripts (events
  and `C_Timer` only, tickers only while their window is open); refresh only what is visible and
  return early when nothing is; format list rows in `update` (only visible rows), not up front.
- A selected button keeps its highlight lit (`PUI.SetSelected`) instead of being disabled.

## Testing

`npm test` does this for every addon:

1. It checks the TOC metadata against the rules above (category, interface, title, ...).
2. It checks that embedded shared libraries match `shared/` and are loaded by the TOC.
3. It parses each `.lua` file the TOC loads (directly or through an `.xml` include) as
   **Lua 5.1**, which catches syntax the game would reject.
4. It loads the addon into a fengari VM with `tests/lib/mocks.lua` and runs `tests/<Name>/*.lua`.

Each shared library is also loaded on its own and runs `tests/shared/<Lib>/*.lua`.

Notes:
- fengari is **Lua 5.3**, so a few behaviours differ from the game. `unpack` is aliased in the
  mocks. Float formatting differs (`1.0` vs `1`), so floor numbers before concatenating them.
- Add mocks to `tests/lib/mocks.lua` as needed. Keep them generic, since every addon shares them.
  Fire events with `_FIRE(event, ...)`. Timers run on a virtual clock via `_RUN_TIMERS()`.
- `CreateFrame` returns a generic stand-in: Show/Hide fire OnShow/OnHide, HookScript chains,
  anchors, sizes and text are recorded, named frames become globals. UI logic (what opens when,
  what a row shows) can be tested; layout and looks cannot. After UI changes, check in game:
  `/reload`, and run `/console scriptErrors 1` to see Lua errors (or use BugSack).

Run `npm test` before you report work as done. If you could not verify something in game, say so.

## Releasing an addon

- Bump `## Version` in the addon's TOC and note the change in its README.
- To publish, zip the `addons/<Name>` folder so the zip contains `<Name>/` at its root.
  Upload it to CurseForge or Wago with the game version set to WoW: Forever.

## Git

- The default branch is `master`. Use short, imperative commit messages that start with the
  addon name when the change is scoped, e.g. `PluvasAuctions: track expired deposits`.
- Never commit `node_modules/`.
