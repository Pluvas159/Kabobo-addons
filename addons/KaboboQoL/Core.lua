-- Kabobo's QoL: saved variables and slash commands.
--
-- The runtime (events, addon messages, modules, error guards, identity) comes from
-- Libs/KaboboCore, the look from Libs/KaboboUI.
--
-- Addon messages:
--   ProgressChanged        experience or reputation was gained, or the watched faction changed
--   SettingChanged(key)    a slash toggle flipped a setting
local _, ns = ...

ns:Setup({
	title = "Kabobo's QoL",
	savedVariables = "KaboboQoLDB",
	dbVersion = 2,
	migrations = {
		[2] = function(db)
			for _, c in pairs(db.chars or {}) do
				ns.Rates.AddSince(c.xp, c.saved)
				ns.Rates.AddSince(c.rep, c.saved)
			end
		end,
	},
	defaults = {
		settings = {
			xp = true,  -- experience per hour and time to level on the experience bar
			rep = true, -- reputation per hour and time to the next standing on the reputation bar
		},
		-- [charKey] = { saved = time(), xp = tracker, rep = tracker, faction = factionID }
		-- (trackers: see Rates.lua).
		-- Kept so a /reload does not throw away the last 15 minutes (see Progress.lua).
		chars = {},
	},
})

ns:Slash({ "/kqol", "/kaboboqol" }, {
	{ cmd = "", help = "print your experience and reputation rates", run = function() ns.Progress:PrintStatus() end },
	{ cmd = "xp", toggle = "xp", help = "experience per hour on the experience bar" },
	{ cmd = "rep", toggle = "rep", help = "reputation per hour on the reputation bar" },
	{ cmd = "reset", help = "start counting from now", run = function()
		ns.Progress:Reset()
		ns:Print("rates reset.")
	end },
})
