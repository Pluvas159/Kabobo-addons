-- Pluvas' Professions: saved variables and slash commands.
--
-- The runtime (events, addon messages, modules, error guards, identity) comes from
-- Libs/PluvasCore, the look from Libs/PluvasUI.
--
-- Addon messages:
--   RecipesChanged         recipe, trainer or vendor data changed, or the open profession did
--   SettingChanged(key)    a slash toggle flipped a setting
local _, ns = ...

ns:Setup({
	title = "Pluvas' Professions",
	savedVariables = "PluvasProfessionsDB",
	dbVersion = 1,
	defaults = {
		settings = {
			panel = false,             -- open the unlearned list next to the profession window
			trainerUnavailable = true, -- make profession trainers list recipes you cannot learn yet
			hideUnknown = false,       -- leave out recipes the client gives no source for
			-- Collapsed groups in the list: [groupKey] = true. Expanding stores false, so the
			-- default below does not come back on the next load. Forever gives no source text for
			-- most recipes, so that pile starts collapsed.
			collapsed = { unknown = true },
			-- Disenchanting in item tooltips. Needs Pluvas' Auctions for prices.
			disenchant = true,         -- "worth disenchanting?" in tooltips of disenchantable items
			disenchantMats = true,     -- list what disenchanting may give under it
		},
		trainer = {},  -- trainer catalog, shared by every character (see Data.lua)
		vendor = {},   -- vendor catalog, shared by every character (see Data.lua)
		chars = {},    -- [charKey] = { [professionName] = profession entry (see Data.lua) }
	},
})

ns:Slash({ "/pprof", "/pluvasprof" }, {
	{ cmd = "", help = "open or close the list of recipes you have not learned", run = function() ns.Panel:Toggle() end },
	{ cmd = "auto", toggle = "panel", help = "open that list with the profession window" },
	{ cmd = "trainer", toggle = "trainerUnavailable", help = "trainers list recipes you cannot learn yet" },
	{ cmd = "unknown", toggle = "hideUnknown", help = "hide recipes with no known source" },
	{ cmd = "de", toggle = "disenchant", help = function()
		local help = "\"worth disenchanting?\" in item tooltips"
		if not ns.DisenchantTooltip.Available() then help = help .. " (needs Pluvas' Auctions for prices)" end
		return help
	end },
	{ cmd = "demats", toggle = "disenchantMats", help = "list what disenchanting may give in those tooltips" },
	{ cmd = "reset", help = "forget this character's recipe data", run = function() ns.Data:ResetChar() end },
	{ cmd = "dump", args = "[count]", help = "with a profession window open, print what the game returns for unlearned recipes",
		run = function(rest) ns.Recipes:Dump(tonumber(rest:match("^(%d+)")) or 3) end },
})
