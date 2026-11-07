# AGENTS.md

Instructions for AI coding agents (Claude Code, Codex, Cursor, ...) and humans working in this repo.

## What this is

**Pluvas' addons** is a monorepo of World of Warcraft addons for **World of Warcraft: Forever**,
written by Pluvas. Each addon is self-contained and ships on its own.

| Addon | Folder | What it does |
| --- | --- | --- |
| Pluvas' Auctions | `addons/PluvasAuctions` | AH price scanning and history in tooltips, plus a sales, profit and gold ledger |
| Pluvas' Professions | `addons/PluvasProfessions` | Lists unlearned recipes and where to learn them, beside the profession window and from trainers; disenchant advice in tooltips (with Pluvas' Auctions) |

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
4. **It runs on PluvasCore and its UI is built with PluvasUI**, the shared libraries embedded in
   `Libs/PluvasCore` and `Libs/PluvasUI`, so every addon is put together, looks and behaves the
   same. See [Code conventions](#code-conventions) and [UI](#ui) below.

`npm test` fails if rule 1 or 2 is broken, or if an addon does not embed every shared library or a
copy differs from `shared/`. `scripts/new-addon.ps1` creates addons that already follow all four.

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
  Libs/PluvasCore/      embedded copies of shared/ libraries (generated: never edit here)
  Libs/PluvasUI/
shared/
  PluvasCore/           the shared runtime: events, modules, saved variables, slash, tasks
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
npm run package                  # release zips into dist/ (see Releasing)
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
  named frames, all prefixed with the addon name (`PluvasAuctionsDB`, `PluvasAuctionsFrame`),
  plus the `PluvasAddons` table that PluvasCore keeps for addons to share APIs.
- **Addons working together**: an addon may use another Pluvas addon when both are loaded, but
  must still work alone. The addon with the data publishes an API with `ns:Expose` (e.g.
  `PluvasAuctions/Api.lua`); the other asks `ns:Peer(name)` each time the feature runs and turns
  the feature off when it gets nil. Never read another addon's saved variables directly.
- **Runtime**: every addon runs on **PluvasCore** (`shared/PluvasCore`, API in its
  [README](shared/PluvasCore/README.md)). An addon's `Core.lua` only declares its saved variables
  (`ns:Setup`) and slash commands (`ns:Slash`); everything else lives in modules. Never copy
  runtime code into an addon: add it to PluvasCore, with tests.
- **Modules**: one file per concern, made with `ns:NewModule(name)`, with optional `OnInit`
  (saved variables loaded), `OnLogin` (identity known) and `OnLogout`. Keep data modules (reading,
  storing, computing) apart from UI modules (windows, panels, buttons).
- **Events and messages**: register through `ns:On(name, fn)`, which guards every handler.
  Data modules announce changes with addon messages (`ns:Send("LedgerChanged")`) and UI modules
  listen to them; a data module never calls into the UI. List an addon's messages at the top of
  its `Core.lua`.
- **Saved variables**: declare `defaults` and `dbVersion` in `ns:Setup`. When a layout changes,
  bump `dbVersion` and add a migration rather than patching data on the fly. Keep keys short in
  tables that grow per item (they are written to disk every logout).
- **Taint**: never overwrite Blizzard functions or secure frames. Use `hooksecurefunc` /
  `HookScript`. Do not touch protected actions in combat.
- **Crash safety**: Lua errors never crash the game, but calling a Blizzard C function outside the
  context it was built for can (`pcall` cannot catch that; see docs/forever-client.md). Tooltips
  and other hot paths read only saved data and plain item info. Call system APIs
  (`C_AuctionHouse`, `C_TradeSkillUI`, ...) only while their window is open: track it with
  `ns:Session`, read through `ns.NewCaller()`, and check `session.open` before every batch.
  Wrap hooks and callbacks in `ns:Guard(name, fn)`, which turns a feature off after repeated
  errors.
- **Performance**: spread heavy loops (full AH scans, recipe reads) over frames with `ns:Spread`,
  and debounce bursts of list updates with `ns:Debounce`. Cache what hot paths (tooltips) would
  otherwise recompute, and drop the cache when the data changes.
- **Style**: tabs for Lua and TOC files (see `.editorconfig`). Comment why, not what. Keep pure
  logic (math, parsing, matching) in functions that do not read game state, so it can be tested.
- Timestamps: `time()`. Money: copper integers, formatted only for display.

## UI

Every window, button, list and tooltip is built with **PluvasUI** (`ns.PluvasUI`). The full API
and style rules are in [shared/PluvasUI/README.md](shared/PluvasUI/README.md). In short:

- **Edit only `shared/PluvasUI`**, then run `npm run sync`. Each addon carries its own copy in
  `Libs/PluvasUI` (loaded right after PluvasCore via `Libs\PluvasUI\PluvasUI.xml` in the TOC), so
  it still ships on its own. Copies attach to the addon's `ns` and create no globals, so addons never clash.
- **No hard-coded look in addon code**: colors (`PUI.Color(text, "good")`), fonts, sizes and
  templates come from `Style.lua`. Money and time go through `PUI.Money`/`MoneyIcons`/
  `SignedMoney`/`Age`/`Clock`. A restyle is a change to the library.
- **Use the widgets**: `PUI.Window` (dockable, Escape handling, remembered position, Pluvas
  signature, footer), `PUI.List` (optionally with column headers), `PUI.Grid`, `PUI.TabBar`,
  `PUI.Button`, `PUI.ShowTooltip`/`SetTooltip`, and label/value lines (`PUI.AddTooltipLines`,
  `PUI.LinePanel`) for item tooltips and info panels.
  If a widget is missing, add it to the library (with tests) rather than building one in an addon.
- **Lightweight**: build UI the first time it opens, not at load; no `OnUpdate` scripts (events
  and `C_Timer` only, tickers only while their window is open); refresh only what is visible and
  return early when nothing is; format list rows in `update` (only visible rows), not up front.
- A selected button keeps its highlight lit (`PUI.SetSelected`) instead of being disabled.

## Testing

`npm test` does this for every addon:

1. It checks the TOC metadata against the rules above (category, interface, title, ...).
2. It checks that the addon embeds every shared library, that each copy matches `shared/`, and
   that the TOC loads it.
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

- Bump `## Version` in the addon's TOC and note the change in its README. Commit.
- `npm run package` builds the zips into `dist/` from the last commit: one
  `<Name>-<version>.zip` per addon (with `<Name>/` at its root) and `pluvas-addons-<release>.zip`
  with every addon.
- Publish them as a GitHub release (`gh release create v<release> dist/*.zip`), and/or upload
  an addon's zip to CurseForge or Wago with the game version set to WoW: Forever.

## Git

- The default branch is `master`. Use short, imperative commit messages that start with the
  addon name when the change is scoped, e.g. `PluvasAuctions: track expired deposits`.
- Never commit `node_modules/`.
