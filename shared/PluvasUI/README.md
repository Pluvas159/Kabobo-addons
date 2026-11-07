# PluvasUI

The shared UI library of every Pluvas addon: one look, one set of widgets, kept lightweight.

## How it ships

- **Edit it only here**, in `shared/PluvasUI`. Then run `npm run sync`, which copies the `.lua` and
  `.xml` files into every addon that embeds it (`addons/<Name>/Libs/PluvasUI`). `npm test` fails
  when a copy differs, so a hand edit in `Libs/` cannot slip through.
- An addon loads it first, with one TOC line: `Libs\PluvasUI\PluvasUI.xml`. The xml lists the files
  in load order, so adding a file here never touches the TOCs.
- Each copy attaches to its addon's namespace (`ns.PluvasUI`) and creates **no globals**. Two
  addons with different versions never clash, and each addon still ships on its own.
- New addons get it from `scripts/new-addon.ps1`. To add it to an existing addon:
  `node scripts/sync-shared.js --embed <Name>`.

```lua
local _, ns = ...
local PUI = ns.PluvasUI
local S = PUI.Sizes
```

## Style rules

Addon code never hard-codes the look. Everything comes from `Style.lua`:

| Token | Use |
| --- | --- |
| `PUI.Color(text, key)`, `PUI.RGB(key)` | `accent` (Pluvas blue), `gold` (headings), `text`, `soft`, `muted` (hints, no data), `good` (available, profit), `bad` (missing, loss) |
| `PUI.Fonts` | `title`, `heading`, `label`, `body`, `muted` |
| `PUI.Sizes` | `pad` 14, `contentTop` 30, `gap` 4, `row` 18, `icon` 16, `button` 22, `tab` 20 |
| `PUI.Templates` | the Blizzard templates behind windows and buttons |
| `PUI.Prefix(title)` | chat prefix `Addon Title:` in the accent color |

- Windows use the Blizzard frame look, so the addons sit naturally next to the game's own windows.
- **The Pluvas signature**: every window has a thin accent line under its title bar and a faded
  "Pluvas" wordmark in the bottom-right corner (`PUI.Signature`). Put footer text in
  `window:Footer()`, which stops short of the wordmark.
- Group headers are gold; hints and "no data" are muted; good/bad are green/red. Don't add other
  colors.
- A selected button keeps its highlight lit (`PUI.SetSelected`) instead of being disabled: a
  gray button reads as "unavailable".
- Docked panels sit to the right of the window they belong to, match its height, and close with
  it. Escape closes the host window (and the panel with it), not just the panel.

## Lightweight rules

- **Build on first open.** Create windows the first time they show, not at load.
- **Nothing per frame.** No `OnUpdate` scripts. Use events and `C_Timer`, and run tickers only while
  their window is open.
- **Visible work only.** `PUI.List` creates rows the first time they need to show, reuses them, and
  redraws only the visible rows when scrolling. Pass raw items to `SetItems` and format them in
  `update`, so off-screen items cost nothing. Return early from refreshes when nothing is shown.
- **Shared methods.** Widgets share one set of methods and scripts, with no closures per instance.
  Keep it that way when adding widgets.

## Widgets

### `PUI.Window(opts)`

```lua
local window = PUI.Window({
	name = "PluvasThingFrame",   -- must start with the addon name; needed for Escape
	title = "Pluvas' Thing",
	width = 340, height = 520,
	position = ns.db.settings.window,  -- optional: remembers where it was dragged
	onShow = function(w) end,
	onHide = function(w, reason) end,  -- "user", "host" (docked host closed), or Close(reason)
})
window:Show()            window:Close("user")     window:Toggle()
window:DockTo(frame, { x = 2, y = 0, matchHeight = true, minHeight = 200 })  -- false if hidden
window:Float()           window:IsDocked()        window:SetTitleText(text)
window:Footer():SetText("...")
```

Lay out content from `S.pad` on the sides and `S.contentTop` below the title.

### `PUI.List(parent, opts)`

```lua
local list = PUI.List(window, {
	kind = "icon",                -- or "columns" with columns = { { width = 90, justify = "LEFT" }, ... }
	update = function(row, item)  -- fill one visible row
		PUI.SetIconRow(row, { icon = item.icon, text = item.name, right = item.cost })
	end,
	onEnter = function(row, item) PUI.ShowTooltip(row, item.name, { "line", { text = "hint", color = "muted" } }) end,
	onClick = function(row, item, button) end,
	onScroll = function(list) end,
})
list:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -76)
list:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, 34)
list:SetItems(items, keepOffset)   list:SetEmptyText("Nothing yet.")
local first, last, total = list:Range()
```

The list fills its height with rows and refits when its size changes (docking, resizing).
`PUI.SetIconRow(row, { header = true, text, right })` draws a gold header without an icon.
`PUI.SetColumns(row, a, b, c)` fills column rows.

### Other widgets

```lua
PUI.Text(parent, "body", "LEFT", { wrap = true })
PUI.Button(parent, { text, width, height, name, onClick, rightClick = true, tooltip = { title, lines } })
PUI.SetSelected(button, true)
local tabs = PUI.TabBar(parent, { width = 312, maxTabWidth = 100, onSelect = function(key) end })
tabs:SetTabs({ "Tailoring", { key = "cook", text = "Cooking" } }, "Tailoring")
PUI.ShowTooltip(owner, title, lines)   PUI.SetTooltip(frame, title, lines)   PUI.HideTooltip()
```

Tooltip lines are strings (white, wrapped) or `{ text, color = key, wrap = false }`. `title` and
`lines` may be functions for tooltips that change.

## Adding to the library

Add the widget here with shared methods, add tests in `tests/shared/PluvasUI/tests.lua`, run
`npm run sync` and `npm test`. Check it in game: layout and looks are not covered by tests.
