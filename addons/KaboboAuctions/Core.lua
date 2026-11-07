-- Kabobo's Auctions: saved variables and slash commands.
--
-- The runtime (events, addon messages, modules, error guards, identity) comes from
-- Libs/KaboboCore, the look from Libs/KaboboUI.
--
-- Addon messages:
--   PricesChanged          price data was recorded or deleted
--   VendorPricesChanged    vendor prices were recorded from an open vendor window
--   ScanStateChanged       Scanner.state / progress, or the auction house opened or closed
--   LedgerChanged          a sale, purchase or gold balance was recorded, or the ledger reset
--   SettingChanged(key)    a slash toggle flipped a setting
local _, ns = ...

ns:Setup({
	title = "Kabobo's Auctions",
	savedVariables = "KaboboAuctionsDB",
	dbVersion = 1,
	defaults = {
		settings = {
			tooltip = true,         -- price lines in item tooltips
			tooltipHistory = true,  -- the 14-day average line
			tooltipLedger = true,   -- your own average sale price
			tooltipCraft = true,    -- AH/vendor cost of mats for items this character can craft
			professionPanel = true, -- mats cost and profit in the profession window
			matsList = true,        -- base mats listed under the mats cost
			historyDays = 60,       -- days of daily price history kept
			staleDays = 3,          -- prices not seen for longer are flagged as old
		},
		account = {
			lastReplicate = 0,      -- time() of the last full scan (one per account per 15 min)
		},
		realms = {},  -- [realmKey] = { items = { [itemKey] = entry }, lastScan = time }   (Pricing)
		ledger = {},  -- [realmKey] = { tx = { transaction, ... } }                        (Ledger)
		gold = {},    -- [realmKey] = { [charName] = { money, days = { [dayStart] = copper } } }
		vendor = {},  -- [itemID] = copper per unit, from vendor windows (all characters)   (Vendor)
		crafts = {},  -- [realmKey] = { [charName] = { [professionID] = { name, r = recipes } } }
	},
})

ns:Slash({ "/ka", "/kabobo" }, {
	{ cmd = "", help = "open or close the ledger window", run = function() ns.LedgerWindow:Toggle() end },
	{ cmd = "scan", help = "full auction house scan (AH open, once per 15 min)", run = function() ns.Scanner:FullScan() end },
	{ cmd = "price", args = "<item link>", help = "show stored prices for an item",
		run = function(rest) ns.Tooltip:PrintPrice(rest) end },
	{ cmd = "tooltip", toggle = "tooltip", help = "price lines in item tooltips" },
	{ cmd = "history", toggle = "tooltipHistory", help = "14-day average in tooltips" },
	{ cmd = "sold", toggle = "tooltipLedger", help = "your average sale price in tooltips" },
	{ cmd = "craft", toggle = "tooltipCraft", help = "mats cost in tooltips of items you can craft" },
	{ cmd = "mats", toggle = "matsList", help = "base mats listed under the mats cost" },
	{ cmd = "panel", toggle = "professionPanel", help = "mats cost and profit in the profession window" },
	{ cmd = "stale", args = "<days>", help = "flag prices not seen for this many days as old",
		run = function(rest) ns.Pricing:SetStaleDays(rest) end },
	{ cmd = "resetprices", help = "delete price data for this realm/faction", run = function() ns.Pricing:Reset() end },
	{ cmd = "resetledger", help = "delete sales history for this realm/faction", run = function() ns.Ledger:Reset() end },
})
