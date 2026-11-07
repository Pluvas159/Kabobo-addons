# PluvasCore

The runtime every Pluvas addon shares: error guards, events and addon messages, modules, saved
variables, identity, slash commands, and helpers for reading game windows safely. Its
companion, [PluvasUI](../PluvasUI), provides the look.

## How it ships

Like PluvasUI: **edit it only here**, then run `npm run sync`. Each addon embeds a copy in
`Libs/PluvasCore`, loaded first by the TOC line `Libs\PluvasCore\PluvasCore.xml`. A copy installs
its functions on its own addon's `ns` and creates no globals, apart from the SavedVariables and
slash command globals the addon asks for. `npm test` fails when an addon does not embed it, or when
a copy differs.

## An addon's Core.lua

```lua
local _, ns = ...

ns:Setup({
	title = "Pluvas' Thing",            -- fallback; the TOC's ## Title wins in game
	savedVariables = "PluvasThingDB",   -- from ## SavedVariables
	dbVersion = 2,
	defaults = { settings = { tooltip = true }, items = {} },
	migrations = { [2] = function(db) db.items = db.oldItems; db.oldItems = nil end },
})

ns:Slash({ "/pt", "/pluvasthing" }, {
	{ cmd = "", help = "open the window", run = function() ns.Window:Toggle() end },
	{ cmd = "price", args = "<item link>", help = "print a price", run = function(rest) end },
	{ cmd = "tooltip", toggle = "tooltip", help = "lines in item tooltips" },
})
```

- **Saved variables**: at `ADDON_LOADED` the saved table is created if needed, migrations run
  from its `dbVersion` up to the current one, then `defaults` fill in missing keys. A new table
  starts at the current version.
- **Slash commands**: help is generated (`/pt help`, or any unknown command). A `toggle` flips
  `ns.db.settings[key]`, prints its state and sends `SettingChanged(key, value)`. A hidden
  `debug` toggle turns on `ns:Debug` output.

## API

| | |
| --- | --- |
| `ns:NewModule(name)` | A table at `ns[name]`, with optional `OnInit` (saved variables loaded), `OnLogin` (identity known) and `OnLogout` |
| `ns:On(name, fn)` | Game event (`ALL_CAPS`) or addon message (`CamelCase`). Every handler is guarded on its own |
| `ns:Send(message, ...)` | Runs the message's handlers right away |
| `ns:Guard(name, fn)` | Wraps fn: reports errors, and turns fn off after 3 errors until `/reload` |
| `ns:WhenLoaded(addon, fn)` | Runs fn once that addon is loaded (now, if it already is) |
| `ns:Print(...)`, `ns:Debug(...)` | Chat output with the addon's prefix |
| `ns.title`, `ns.version` | From the TOC |
| `ns.realmKey`, `ns.charKey`, `ns.charName`, `ns.realm`, `ns.faction` | Set at `PLAYER_LOGIN`. `realmKey` = realm-faction (one auction house), `charKey` = realm-character |
| `ns:Session(openEvent, closeEvent)` | `{ open }` that follows a game window. Call its API only while `open` |
| `ns.MerchantItems()` | Every item the open vendor window sells (`link`, `id`, `name`, `price` per purchase of `quantity`, `extended`, `available`). Only while a merchant session is open |
| `ns.NewCaller()` | `caller:Call(fn, ...)` turns errors into nil and counts them in `caller.failures` |
| `ns:Debounce(name, delay, fn)` | A trigger that runs fn once per burst |
| `ns:Spread(opts)` | A long loop spread over frames (`count`, `size`, `step`, `alive`, `progress`, `done`) |
| `ns.Ensure(t, k1, k2, ...)` | Walks and creates nested tables; nil if a key is nil |
| `ns.ApplyDefaults`, `ns.Split`, `ns.DayStart`, `ns.Try` | Small helpers |
| `ns:KnownProfessions()` | This character's professions from the spellbook (safe at any time) |

## Reading a game window

Calling a window's client functions while the window is closed can crash the client, and `pcall`
cannot catch that. The helpers make the safe way the short way:

```lua
local trade = ns:Session("TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE")   -- before the module's own handlers

local function scan()
	local api = ns.NewCaller()
	if not trade.open then return end
	local ids = api:Call(C_TradeSkillUI.GetAllRecipeIDs)
	ns:Spread({
		name = "Recipe scan", count = #ids, size = 30,
		alive = function() return trade.open end,      -- stops if the window closes mid-scan
		step = function(i) local info = api:Call(C_TradeSkillUI.GetRecipeInfo, ids[i]) end,
		done = function(ok) if ok and api.failures == 0 then --[[ replace saved data ]] end end,
	})
end

local scanSoon = ns:Debounce("Recipe scan", 0.5, scan)   -- lists fire many updates while they fill
ns:On("TRADE_SKILL_LIST_UPDATE", scanSoon)
```

## Adding to the library

Add the function here, add tests in `tests/shared/PluvasCore/tests.lua`, run `npm run sync`, then
`npm test`.
