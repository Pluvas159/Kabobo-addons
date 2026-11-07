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
--   CraftsChanged          a profession's recipes were stored, or a dropped profession removed
--   ShoppingChanged        the shopping list, its current step, or the price advice changed
--   FullScanListings(g)    a full scan finished: { [itemKey] = { { unit, qty, yours, seller }, ... } }
--   UndercutsChanged       your auctions were read, or one was compared against other listings
--   SettingChanged(key)    a slash toggle flipped a setting
local _, ns = ...

ns:Setup({
	title = "Kabobo's Auctions",
	savedVariables = "KaboboAuctionsDB",
	dbVersion = 2,
	migrations = {
		-- Version 1 could record one mail twice: before its buyer/seller name loaded, and after.
		[2] = function(db)
			for realmKey, realm in pairs(db.ledger or {}) do
				if type(realm.tx) == "table" then
					local removed = ns.Ledger.Dedupe(realm.tx)
					if removed > 0 then
						-- ns.db is not set yet while migrations run, so log straight into db.
						db.log = type(db.log) == "table" and db.log or {}
						db.log[#db.log + 1] = "migration: removed " .. removed .. " duplicate ledger entries on " .. realmKey
					end
				end
			end
		end,
	},
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
			buyCap = 1.2,           -- shopping list pays at most this x market value per unit
			undercutAlerts = true,  -- chat line and sound when someone lists below or at your price
			auctionLabels = true,   -- undercut status beside your auctions in the Auctions tab
			recipeProfit = true,    -- profit per craft beside each recipe in the profession window
			craftsSort = "profit",  -- crafts window order: "profit" per craft or "day" (profit x sold/day)
		},
		account = {
			lastReplicate = 0,      -- time() of the last full scan (one per account per 15 min)
		},
		realms = {},  -- [realmKey] = { items = { [itemKey] = entry }, lastScan = time,  (Pricing)
		              --   sales = { [itemKey] = listings gone between full scans } }     (Sales)
		ledger = {},  -- [realmKey] = { tx = { transaction, ... } }                        (Ledger)
		gold = {},    -- [realmKey] = { [charName] = { money, days = { [dayStart] = copper } } }
		vendor = {},  -- [itemID] = copper per unit, from vendor windows (all characters)   (Vendor)
		crafts = {},  -- [realmKey] = { [charName] = { [professionID] = { name, r = recipes } } }
		mine = {},    -- [realmKey] = { [charName] = { [itemKey] = your auction + undercut status } }
	},
})

ns:Slash({ "/ka", "/kabobo" }, {
	{ cmd = "", help = "open or close the ledger window", run = function() ns.LedgerWindow:Toggle() end },
	{ cmd = "crafts", help = "learned recipes per profession, ranked by profit", run = function() ns.CraftsWindow:Toggle() end },
	{ cmd = "buycap", args = "<percent>",
		help = function() return "most the shopping list pays, in % of market value (now "
			.. math.floor((ns.db.settings.buyCap or 1.2) * 100 + 0.5) .. "%)" end,
		run = function(rest)
			local pct = tonumber(rest)
			if not pct or pct < 50 or pct > 300 then
				return ns:Print("usage: /ka buycap <50-300>, e.g. /ka buycap 120")
			end
			ns.db.settings.buyCap = pct / 100
			ns:Print("the shopping list now pays at most " .. math.floor(pct) .. "% of market value.")
			ns:Send("ShoppingChanged")
		end },
	{ cmd = "scan", help = "full auction house scan (AH open, once per 15 min)", run = function() ns.Scanner:FullScan() end },
	{ cmd = "price", args = "<item link>", help = "show stored prices for an item",
		run = function(rest) ns.Tooltip:PrintPrice(rest) end },
	{ cmd = "tooltip", toggle = "tooltip", help = "price lines in item tooltips" },
	{ cmd = "history", toggle = "tooltipHistory", help = "14-day average in tooltips" },
	{ cmd = "sold", toggle = "tooltipLedger", help = "your average sale price in tooltips" },
	{ cmd = "craft", toggle = "tooltipCraft", help = "mats cost in tooltips of items you can craft" },
	{ cmd = "mats", toggle = "matsList", help = "base mats listed under the mats cost" },
	{ cmd = "undercut", toggle = "undercutAlerts", help = "chat alert when someone lists below or at your auction's price" },
	{ cmd = "labels", toggle = "auctionLabels", help = "undercut status beside your auctions in the Auctions tab" },
	{ cmd = "panel", toggle = "professionPanel", help = "mats cost and profit in the profession window" },
	{ cmd = "stale", args = "<days>", help = "flag prices not seen for this many days as old",
		run = function(rest) ns.Pricing:SetStaleDays(rest) end },
	{ cmd = "listprofit", toggle = "recipeProfit", help = "profit beside each recipe in the profession window's list" },
	{ cmd = "resetprices", help = "delete price data for this realm/faction", run = function() ns.Pricing:Reset() end },
	{ cmd = "resetledger", help = "delete sales history for this realm/faction", run = function() ns.Ledger:Reset() end },
})
