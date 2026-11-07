-- Kabobo's Auctions: the ledger window (/ka). Sales, cut, purchases and profit per period, gold
-- across characters, price data status, and recent transactions or top items.
--
-- Built on first open with KaboboUI. Listens to LedgerChanged, PricesChanged and
-- ScanStateChanged, and does nothing while it is closed.
local _, ns = ...
local LW = ns:NewModule("LedgerWindow")
local PUI = ns.KaboboUI
local S = PUI.Sizes
local Money, Signed = PUI.Money, PUI.SignedMoney

local DAY = 86400
local WIDTH, HEIGHT = 620, 470
local ROWS = 12
local PERIODS = { "Today", "7 days", "30 days", "All time" }
local LIST_COLUMNS = {
	{ width = 90 }, { width = 230 }, { width = 130 }, { width = 130, justify = "RIGHT" },
}

local window
local mode = "recent"      -- recent | top

-- List rows -----------------------------------------------------------------------
--
-- Items are the raw transactions (or top-item entries); a row is formatted only when it shows,
-- so a long history costs nothing until it is scrolled to.

local function recentRow(row, e)
	local what = e.k == "s" and PUI.Color("Sold", "good") or PUI.Color("Bought", "bad")
	local qty = e.qty > 1 and PUI.Color(" x" .. e.qty, "muted") or ""
	local amount = e.k == "s" and Signed(e.gross - (e.cut or 0)) or Signed(-e.gross)
	PUI.SetColumns(row, date("%m-%d %H:%M", e.t), what .. " " .. e.item .. qty, e.who or "", amount)
end

local function topRow(row, it)
	local units = it.soldQty .. " sold"
	if it.boughtQty > 0 then units = units .. PUI.Color(" / " .. it.boughtQty .. " bought", "muted") end
	PUI.SetColumns(row, units, it.item, Money(it.net), Signed(it.profit))
end

local STATUS = {
	undercut = { "Undercut", "bad" }, matched = { "Undercut", "bad" }, lowest = { "Lowest", "good" },
}

local function mineRow(row, it)
	local e = it.e
	local st = STATUS[e.s]
	local status = st and PUI.Color(st[1], st[2]) or PUI.Color("Not checked", "muted")
	local qty = e.q and e.q > 1 and PUI.Color(" x" .. e.q, "muted") or ""
	local name = ns.Pricing.ItemName(tonumber(tostring(it.key):match("^(%d+)")))
	PUI.SetColumns(row, status, name .. qty, Money(e.u), Money(e.o))
end

local MODES = {
	recent = {
		headers = { "When", "Item", "Buyer / seller", "Amount" },
		row = recentRow,
		-- Newest first: a list of references, formatted only when shown.
		items = function(tx)
			local items, n = {}, #tx
			for i = n, 1, -1 do items[n - i + 1] = tx[i] end
			return items
		end,
		empty = "No auction sales or purchases recorded yet. Open your mailbox to read them.",
	},
	top = {
		headers = { "Units", "Item", "Net sales", "Profit" },
		row = topRow,
		items = function(tx) return ns.Ledger.TopItems(tx, time() - 30 * DAY) end,
		empty = "Nothing sold or bought in the last 30 days.",
	},
	mine = {
		headers = { "Status", "Item", "Your price", "Cheapest other" },
		row = mineRow,
		items = function() return ns.Undercut:List() end,
		empty = "No auctions of yours known yet. Open the auction house to read them; a full scan or a search compares them.",
	},
}

local function updateRow(row, item)
	MODES[mode].row(row, item)
end

-- The item name behind a row of any mode.
local function rowItemName(it)
	if it.key then return ns.Pricing.ItemName(tonumber(tostring(it.key):match("^(%d+)"))) end
	return it.item
end

-- Clicking a row puts its item in the auction house search box.
local function rowClick(_, it)
	local name = rowItemName(it)
	if not name then return end
	local problem = ns.Shopping.FillSearch(name)
	if problem then ns:Print(problem) end
end

-- Window --------------------------------------------------------------------------

local function build()
	window = PUI.Window({
		name = "KaboboAuctionsFrame",
		title = ns.title,
		width = WIDTH,
		height = HEIGHT,
		position = ns.Ensure(ns.db.settings, "ledgerWindow"),
		onShow = function() LW:Refresh() end,
	})
	local left = 18
	local top = -S.contentTop - 4

	window.grid = PUI.Grid(window, {
		columns = PERIODS,
		rows = { "Sales", "AH cut", "Purchases", "Profit" },
		labelWidth = 102,
		cellWidth = 115,
	})
	window.grid:SetPoint("TOPLEFT", window, "TOPLEFT", left, top)

	window.goldLine = PUI.Text(window, "body")
	window.goldLine:SetWidth(WIDTH - 2 * left)
	window.goldLine:SetPoint("TOPLEFT", window.grid, "BOTTOMLEFT", 0, -8)
	window.dataLine = PUI.Text(window, "body")
	window.dataLine:SetWidth(WIDTH - 2 * left)
	window.dataLine:SetPoint("TOPLEFT", window.goldLine, "BOTTOMLEFT", 0, -6)

	local function modeButton(label, key, width)
		return PUI.Button(window, {
			text = label,
			width = width,
			onClick = function()
				mode = key
				LW:Refresh()
			end,
		})
	end
	window.recentButton = modeButton("Recent", "recent", 110)
	window.recentButton:SetPoint("TOPLEFT", window.dataLine, "BOTTOMLEFT", -2, -12)
	window.topButton = modeButton("Top items (30d)", "top", 130)
	window.topButton:SetPoint("LEFT", window.recentButton, "RIGHT", S.gap, 0)
	window.mineButton = modeButton("My auctions", "mine", 110)
	window.mineButton:SetPoint("LEFT", window.topButton, "RIGHT", S.gap, 0)
	window.craftsButton = PUI.Button(window, {
		text = "Crafts by profit",
		width = 130,
		onClick = function() ns.CraftsWindow:Toggle() end,
	})
	window.craftsButton:SetPoint("TOP", window.recentButton, "TOP", 0, 0)
	window.craftsButton:SetPoint("RIGHT", window, "RIGHT", -left, 0)

	window.list = PUI.List(window, {
		kind = "columns", columns = LIST_COLUMNS, headers = true, update = updateRow, onClick = rowClick,
	})
	window.list:SetPoint("TOPLEFT", window.recentButton, "BOTTOMLEFT", 2, -8)
	window.list:SetPoint("RIGHT", window, "RIGHT", -left, 0)
	window.list:SetHeight((ROWS + 1) * S.row)

	window:Footer():SetText("Click an item to search it in the auction house. Sales are read from auction mail.")
end

local function shown()
	return window ~= nil and window:IsShown() and ns.realmKey ~= nil
end

-- Price data status: cheap, so it follows every scan state change.
function LW:RefreshScanInfo()
	if not shown() then return end
	local now = time()
	local count, last = ns.Pricing:Summary()
	local cd = ns.Scanner:CooldownRemaining()
	window.dataLine:SetText(string.format("Prices tracked: %d items   Last full scan: %s   Next full scan: %s",
		count, last > 0 and (PUI.Age(now - last) .. " ago") or "never",
		cd > 0 and ("in " .. PUI.Clock(cd)) or "ready"))
end

function LW:Refresh()
	if not shown() then return end
	local L = ns.Ledger
	local tx = L:Transactions()
	local now = time()

	local since = { ns.DayStart(now), now - 7 * DAY, now - 30 * DAY, nil }
	for c = 1, #PERIODS do
		local s = L.Summarize(tx, since[c])
		window.grid:Set(1, c, Money(s.sales))
		window.grid:Set(2, c, Signed(-s.cut))
		window.grid:Set(3, c, Signed(-s.bought))
		window.grid:Set(4, c, Signed(s.profit))
	end

	local total, change = L:GoldSummary()
	window.goldLine:SetText("Gold on " .. ns.realmKey .. " (all characters): " .. Money(total)
		.. "   since yesterday: " .. Signed(change))
	LW:RefreshScanInfo()

	local m = MODES[mode]
	local items = m.items(tx)
	window.list:SetHeaders(unpack(m.headers))
	window.list:SetItems(items, true)
	window.list:SetEmptyText(#items == 0 and m.empty or nil)
	PUI.SetSelected(window.recentButton, mode == "recent")
	PUI.SetSelected(window.topButton, mode == "top")
	PUI.SetSelected(window.mineButton, mode == "mine")
end

function LW:Toggle()
	if not window then build() end
	window:Toggle()
end

ns:On("LedgerChanged", function() LW:Refresh() end)
ns:On("UndercutsChanged", function() if mode == "mine" then LW:Refresh() end end)
ns:On("PricesChanged", function() LW:RefreshScanInfo() end)
ns:On("ScanStateChanged", function() LW:RefreshScanInfo() end)
