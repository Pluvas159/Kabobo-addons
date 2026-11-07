-- Pluvas' Auctions: ledger window and the scan button on the auction house frame.
-- Built with PluvasUI (Libs/PluvasUI), the shared look of every Pluvas addon.
local _, ns = ...
local UI = ns:NewModule("UI")
local PUI = ns.PluvasUI
local S = PUI.Sizes

local WIDTH, HEIGHT = 620, 470
local ROWS = 12
local COLS = { "Today", "7 days", "30 days", "All time" }
local LIST_COLUMNS = {
	{ width = 90 }, { width = 230 }, { width = 130 }, { width = 130, justify = "RIGHT" },
}

local window, list, header
local mode = "recent"      -- recent | top

local function signedMoney(c)
	if c > 0 then return PUI.Color("+", "good") .. ns.Money(c) end
	if c < 0 then return PUI.Color("-", "bad") .. ns.Money(-c) end
	return ns.Money(0)
end

-- List rows -----------------------------------------------------------------------
--
-- Items are the raw transactions (or top-item entries); a row is formatted only when it shows,
-- so a long history costs nothing until it is scrolled to.

local function recentRow(row, e)
	local what = e.k == "s" and PUI.Color("Sold", "good") or PUI.Color("Bought", "bad")
	local qty = e.qty > 1 and PUI.Color(" x" .. e.qty, "muted") or ""
	local amount = e.k == "s" and signedMoney(e.gross - (e.cut or 0)) or signedMoney(-e.gross)
	PUI.SetColumns(row, date("%m-%d %H:%M", e.t), what .. " " .. e.item .. qty, e.who or "", amount)
end

local function topRow(row, it)
	local units = it.soldQty .. " sold"
	if it.boughtQty > 0 then units = units .. PUI.Color(" / " .. it.boughtQty .. " bought", "muted") end
	PUI.SetColumns(row, units, it.item, ns.Money(it.net), signedMoney(it.profit))
end

local function updateRow(row, item)
	if mode == "top" then topRow(row, item) else recentRow(row, item) end
end

-- Window --------------------------------------------------------------------------

local function build()
	ns.db.settings.ledgerWindow = ns.db.settings.ledgerWindow or {}
	window = PUI.Window({
		name = "PluvasAuctionsFrame",
		title = "Pluvas' Auctions",
		width = WIDTH,
		height = HEIGHT,
		position = ns.db.settings.ledgerWindow,
		onShow = function() UI:Refresh() end,
	})

	-- Summary grid
	local top = -S.contentTop - 4
	window.cells = {}
	for c, label in ipairs(COLS) do
		local h = PUI.Text(window, "heading", "RIGHT")
		h:SetWidth(115)
		h:SetPoint("TOPLEFT", window, "TOPLEFT", 120 + (c - 1) * 120, top)
		h:SetText(label)
	end
	local rowLabels = { "Sales", "AH cut", "Purchases", "Profit" }
	for r, label in ipairs(rowLabels) do
		local y = top - 6 - r * S.row
		local l = PUI.Text(window, "label")
		l:SetPoint("TOPLEFT", window, "TOPLEFT", 18, y)
		l:SetText(label)
		window.cells[r] = {}
		for c = 1, #COLS do
			local cell = PUI.Text(window, "body", "RIGHT")
			cell:SetWidth(115)
			cell:SetPoint("TOPLEFT", window, "TOPLEFT", 120 + (c - 1) * 120, y)
			window.cells[r][c] = cell
		end
	end

	-- Info lines
	window.goldLine = PUI.Text(window, "body")
	window.goldLine:SetWidth(WIDTH - 36)
	window.goldLine:SetPoint("TOPLEFT", window, "TOPLEFT", 18, top - 6 - 5 * S.row - 8)
	window.dataLine = PUI.Text(window, "body")
	window.dataLine:SetWidth(WIDTH - 36)
	window.dataLine:SetPoint("TOPLEFT", window.goldLine, "BOTTOMLEFT", 0, -6)

	-- List mode buttons
	local function modeButton(label, key, width)
		return PUI.Button(window, {
			text = label,
			width = width,
			onClick = function()
				mode = key
				UI:Refresh()
			end,
		})
	end
	window.recentButton = modeButton("Recent", "recent", 110)
	window.recentButton:SetPoint("TOPLEFT", window.dataLine, "BOTTOMLEFT", -2, -12)
	window.topButton = modeButton("Top items (30d)", "top", 130)
	window.topButton:SetPoint("LEFT", window.recentButton, "RIGHT", S.gap, 0)

	-- Column headers, then the list under them
	header = {}
	local x = 0
	for i, col in ipairs(LIST_COLUMNS) do
		local fs = PUI.Text(window, "label", col.justify)
		fs:SetWidth(col.width)
		fs:SetPoint("TOPLEFT", window.recentButton, "BOTTOMLEFT", 2 + x, -8)
		header[i] = fs
		x = x + col.width + 6
	end

	list = PUI.List(window, { kind = "columns", columns = LIST_COLUMNS, update = updateRow })
	list:SetPoint("TOPLEFT", header[1], "BOTTOMLEFT", 0, -4)
	list:SetPoint("RIGHT", window, "RIGHT", -18, 0)
	list:SetHeight(ROWS * S.row)

	window:Footer():SetText("Sales are read from auction mail when you open your mailbox. Scroll the list with the mouse wheel.")
end

local function setHeader(a, b, c, d)
	header[1]:SetText(a); header[2]:SetText(b); header[3]:SetText(c); header[4]:SetText(d)
end

local function fillRecent(tx)
	setHeader("When", "Item", "Buyer / seller", "Amount")
	-- Newest first: a list of references, formatted only when shown.
	local items, n = {}, #tx
	for i = n, 1, -1 do items[n - i + 1] = tx[i] end
	list:SetItems(items, true)
	list:SetEmptyText(n == 0 and "No auction sales or purchases recorded yet. Open your mailbox to read them." or nil)
end

local function fillTop(tx)
	setHeader("Units", "Item", "Net sales", "Profit")
	local items = ns.Ledger.TopItems(tx, time() - 30 * 86400)
	list:SetItems(items, true)
	list:SetEmptyText(#items == 0 and "Nothing sold or bought in the last 30 days." or nil)
end

function UI:Refresh()
	if not window or not window:IsShown() or not ns.realmKey then return end
	local L = ns.Ledger
	local tx = L:Transactions()
	local now = time()

	-- Summary grid
	local since = { ns.DayStart(now), now - 7 * 86400, now - 30 * 86400, nil }
	for c = 1, #COLS do
		local s = L.Summarize(tx, since[c])
		window.cells[1][c]:SetText(ns.Money(s.sales))
		window.cells[2][c]:SetText(s.cut > 0 and (PUI.Color("-", "bad") .. ns.Money(s.cut)) or ns.Money(0))
		window.cells[3][c]:SetText(s.bought > 0 and (PUI.Color("-", "bad") .. ns.Money(s.bought)) or ns.Money(0))
		window.cells[4][c]:SetText(signedMoney(s.profit))
	end

	-- Gold and data info
	local total, change = L:GoldSummary()
	window.goldLine:SetText("Gold on " .. ns.realmKey .. " (all characters): " .. ns.Money(total)
		.. "   since yesterday: " .. signedMoney(change))

	local realm = ns.db.realms[ns.realmKey]
	local count = 0
	if realm then for _ in pairs(realm.items) do count = count + 1 end end
	local last = realm and realm.lastScan or 0
	local scanText = last > 0 and (ns.Age(now - last) .. " ago") or "never"
	local cd = ns.Scanner:CooldownRemaining()
	window.dataLine:SetText(string.format("Prices tracked: %d items   Last full scan: %s   Next full scan: %s",
		count, scanText, cd > 0 and ("in " .. ns.Clock(cd)) or "ready"))

	-- List
	if mode == "top" then fillTop(tx) else fillRecent(tx) end
	PUI.SetSelected(window.recentButton, mode == "recent")
	PUI.SetSelected(window.topButton, mode == "top")
end

function UI:Toggle()
	if not window then build() end
	window:Toggle()
end

-- Auction house button -------------------------------------------------------

local scanButton, ticker

local function updateScanButton()
	if not scanButton then return end
	local scanner = ns.Scanner
	if scanner.state == "waiting" then
		scanButton:SetText("Waiting for AH...")
		scanButton:Disable()
	elseif scanner.state == "processing" then
		scanButton:SetText(string.format("Scanning %d%%", scanner.progress * 100))
		scanButton:Disable()
	else
		local cd = scanner:CooldownRemaining()
		if cd > 0 then
			scanButton:SetText("Full scan in " .. ns.Clock(cd))
			scanButton:Disable()
		else
			scanButton:SetText("Full scan")
			scanButton:Enable()
		end
	end
end

local function createScanButton()
	if scanButton or not AuctionHouseFrame then return end
	scanButton = PUI.Button(AuctionHouseFrame, {
		name = "PluvasAuctionsScanButton",
		width = 150,
		height = 24,
		rightClick = true,
		onClick = function(_, button)
			if button == "RightButton" then UI:Toggle() else ns.Scanner:FullScan() end
		end,
		tooltip = {
			title = "Pluvas' Auctions",
			lines = {
				"Scan every auction and update the price data.",
				{ text = "The server allows one full scan every 15 minutes.", color = "muted" },
				{ text = "Right-click to open the ledger.", color = "muted" },
			},
		},
	})
	scanButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, -2)
end

ns:On("AUCTION_HOUSE_SHOW", function()
	createScanButton()
	if not scanButton then
		-- The Blizzard AH UI may still be loading; try again next frame.
		C_Timer.After(0, function() createScanButton(); updateScanButton() end)
	end
	updateScanButton()
	if ticker then ticker:Cancel() end
	-- Once a second only while the AH is open, for the cooldown countdown.
	ticker = C_Timer.NewTicker(1, updateScanButton)
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
	if ticker then ticker:Cancel(); ticker = nil end
end)

function UI:OnLogin()
	ns.Scanner:OnStateChanged(function()
		updateScanButton()
		UI:Refresh()
	end)
end
