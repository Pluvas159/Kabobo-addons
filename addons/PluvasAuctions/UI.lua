-- Pluvas' Auctions: ledger window and the scan button on the auction house frame.
local _, ns = ...
local UI = ns:NewModule("UI")

local WIDTH, HEIGHT = 620, 470
local ROWS = 12
local ROW_HEIGHT = 18
local COLS = { "Today", "7 days", "30 days", "All time" }
local GREEN, RED, GRAY = "|cff40d040", "|cffff5050", "|cff808080"

local frame
local mode = "recent"      -- recent | top
local offset = 0

local function signedMoney(c)
	if c > 0 then return GREEN .. "+|r" .. ns.Money(c) end
	if c < 0 then return RED .. "-|r" .. ns.Money(-c) end
	return ns.Money(0)
end

local function text(parent, template, justify, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	if width then fs:SetWidth(width) end
	fs:SetWordWrap(false)
	return fs
end

-- Window ------------------------------------------------------------------

local function build()
	frame = CreateFrame("Frame", "PluvasAuctionsFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "PluvasAuctionsFrame") -- close with Escape

	local title = frame.TitleText or text(frame, "GameFontHighlight", "CENTER")
	if not frame.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("Pluvas' Auctions")

	-- Summary grid
	local top = -34
	frame.cells = {}
	for c, label in ipairs(COLS) do
		local h = text(frame, "GameFontNormal", "RIGHT", 115)
		h:SetPoint("TOPLEFT", 120 + (c - 1) * 120, top)
		h:SetText(label)
	end
	local rowLabels = { "Sales", "AH cut", "Purchases", "Profit" }
	for r, label in ipairs(rowLabels) do
		local y = top - 6 - r * 18
		local l = text(frame, "GameFontNormalSmall")
		l:SetPoint("TOPLEFT", 18, y)
		l:SetText(label)
		frame.cells[r] = {}
		for c = 1, #COLS do
			local cell = text(frame, "GameFontHighlightSmall", "RIGHT", 115)
			cell:SetPoint("TOPLEFT", 120 + (c - 1) * 120, y)
			frame.cells[r][c] = cell
		end
	end

	-- Info lines
	frame.goldLine = text(frame, "GameFontHighlightSmall", "LEFT", WIDTH - 36)
	frame.goldLine:SetPoint("TOPLEFT", 18, top - 6 - 5 * 18 - 8)
	frame.dataLine = text(frame, "GameFontHighlightSmall", "LEFT", WIDTH - 36)
	frame.dataLine:SetPoint("TOPLEFT", frame.goldLine, "BOTTOMLEFT", 0, -6)

	-- List mode buttons
	local function modeButton(label, key, anchor)
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		b:SetSize(110, 22)
		if anchor then
			b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
		else
			b:SetPoint("TOPLEFT", frame.dataLine, "BOTTOMLEFT", -2, -12)
		end
		b:SetText(label)
		b:SetScript("OnClick", function()
			mode = key
			offset = 0
			UI:Refresh()
		end)
		return b
	end
	frame.recentButton = modeButton("Recent", "recent")
	frame.topButton = modeButton("Top items (30d)", "top", frame.recentButton)
	frame.topButton:SetWidth(130)

	-- List
	local list = CreateFrame("Frame", nil, frame)
	list:SetPoint("TOPLEFT", frame.recentButton, "BOTTOMLEFT", 2, -8)
	list:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
	list:SetHeight(ROWS * ROW_HEIGHT + ROW_HEIGHT)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		offset = math.max(0, offset - delta * 3)
		UI:Refresh()
	end)
	frame.list = list

	local widths = { 90, 230, 130, 130 }
	local justify = { "LEFT", "LEFT", "LEFT", "RIGHT" }
	local function makeRow(y, template)
		local row, x = {}, 0
		for i = 1, 4 do
			local fs = text(list, template, justify[i], widths[i])
			fs:SetPoint("TOPLEFT", x, y)
			row[i] = fs
			x = x + widths[i] + 6
		end
		return row
	end
	frame.header = makeRow(0, "GameFontNormalSmall")
	frame.rows = {}
	for i = 1, ROWS do
		frame.rows[i] = makeRow(-i * ROW_HEIGHT, "GameFontHighlightSmall")
	end

	frame.empty = text(list, "GameFontDisableSmall", "CENTER", WIDTH - 60)
	frame.empty:SetPoint("TOP", 0, -3 * ROW_HEIGHT)

	frame.footer = text(frame, "GameFontDisableSmall", "LEFT", WIDTH - 36)
	frame.footer:SetPoint("BOTTOMLEFT", 18, 12)
	frame.footer:SetText("Sales are read from auction mail when you open your mailbox. Scroll the list with the mouse wheel.")

	frame:SetScript("OnShow", function() UI:Refresh() end)
end

local function setRow(row, a, b, c, d)
	row[1]:SetText(a or "")
	row[2]:SetText(b or "")
	row[3]:SetText(c or "")
	row[4]:SetText(d or "")
end

local function fillRecent(tx)
	setRow(frame.header, "When", "Item", "Buyer / seller", "Amount")
	local n = #tx
	offset = math.min(offset, math.max(0, n - ROWS))
	for i = 1, ROWS do
		local e = tx[n - offset - i + 1]
		if e then
			local what = e.k == "s" and (GREEN .. "Sold|r ") or (RED .. "Bought|r ")
			local qty = e.qty > 1 and (GRAY .. " x" .. e.qty .. "|r") or ""
			local amount = e.k == "s" and signedMoney(e.gross - (e.cut or 0)) or signedMoney(-e.gross)
			setRow(frame.rows[i], date("%m-%d %H:%M", e.t), what .. e.item .. qty, e.who or "", amount)
		else
			setRow(frame.rows[i])
		end
	end
	frame.empty:SetText(n == 0 and "No auction sales or purchases recorded yet. Open your mailbox to read them." or "")
end

local function fillTop(tx)
	setRow(frame.header, "Units", "Item", "Net sales", "Profit")
	local items = ns.Ledger.TopItems(tx, time() - 30 * 86400)
	local n = #items
	offset = math.min(offset, math.max(0, n - ROWS))
	for i = 1, ROWS do
		local it = items[offset + i]
		if it then
			local units = it.soldQty .. " sold"
			if it.boughtQty > 0 then units = units .. GRAY .. " / " .. it.boughtQty .. " bought|r" end
			setRow(frame.rows[i], units, it.item, ns.Money(it.net), signedMoney(it.profit))
		else
			setRow(frame.rows[i])
		end
	end
	frame.empty:SetText(n == 0 and "Nothing sold or bought in the last 30 days." or "")
end

function UI:Refresh()
	if not frame or not frame:IsShown() or not ns.realmKey then return end
	local L = ns.Ledger
	local tx = L:Transactions()
	local now = time()

	-- Summary grid
	local since = { ns.DayStart(now), now - 7 * 86400, now - 30 * 86400, nil }
	for c = 1, #COLS do
		local s = L.Summarize(tx, since[c])
		frame.cells[1][c]:SetText(ns.Money(s.sales))
		frame.cells[2][c]:SetText(s.cut > 0 and (RED .. "-|r" .. ns.Money(s.cut)) or ns.Money(0))
		frame.cells[3][c]:SetText(s.bought > 0 and (RED .. "-|r" .. ns.Money(s.bought)) or ns.Money(0))
		frame.cells[4][c]:SetText(signedMoney(s.profit))
	end

	-- Gold and data info
	local total, change = L:GoldSummary()
	frame.goldLine:SetText("Gold on " .. ns.realmKey .. " (all characters): " .. ns.Money(total)
		.. "   since yesterday: " .. signedMoney(change))

	local realm = ns.db.realms[ns.realmKey]
	local count = 0
	if realm then for _ in pairs(realm.items) do count = count + 1 end end
	local last = realm and realm.lastScan or 0
	local scanText = last > 0 and (ns.Age(now - last) .. " ago") or "never"
	local cd = ns.Scanner:CooldownRemaining()
	frame.dataLine:SetText(string.format("Prices tracked: %d items   Last full scan: %s   Next full scan: %s",
		count, scanText, cd > 0 and ("in " .. ns.Clock(cd)) or "ready"))

	-- List
	if mode == "top" then fillTop(tx) else fillRecent(tx) end
	frame.recentButton:SetEnabled(mode ~= "recent")
	frame.topButton:SetEnabled(mode ~= "top")
end

function UI:Toggle()
	if not frame then build() end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Auction house button -------------------------------------------------------

local scanButton, ticker

local function updateScanButton()
	if not scanButton then return end
	local S = ns.Scanner
	if S.state == "waiting" then
		scanButton:SetText("Waiting for AH...")
		scanButton:Disable()
	elseif S.state == "processing" then
		scanButton:SetText(string.format("Scanning %d%%", S.progress * 100))
		scanButton:Disable()
	else
		local cd = S:CooldownRemaining()
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
	scanButton = CreateFrame("Button", "PluvasAuctionsScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
	scanButton:SetSize(150, 24)
	scanButton:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, -2)
	scanButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Pluvas' Auctions")
		GameTooltip:AddLine("Scan every auction and update the price data.", 1, 1, 1, true)
		GameTooltip:AddLine("The server allows one full scan every 15 minutes.", 0.7, 0.7, 0.7, true)
		GameTooltip:AddLine("Right-click to open the ledger.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	scanButton:SetScript("OnLeave", GameTooltip_Hide)
	scanButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	scanButton:SetScript("OnClick", function(_, button)
		if button == "RightButton" then UI:Toggle() else ns.Scanner:FullScan() end
	end)
end

ns:On("AUCTION_HOUSE_SHOW", function()
	createScanButton()
	if not scanButton then
		-- The Blizzard AH UI may still be loading; try again next frame.
		C_Timer.After(0, function() createScanButton(); updateScanButton() end)
	end
	updateScanButton()
	if ticker then ticker:Cancel() end
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
