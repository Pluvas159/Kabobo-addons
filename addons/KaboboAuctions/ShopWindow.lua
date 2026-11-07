-- Kabobo's Auctions: the shopping list window. Opens from a recipe in the crafts window, docks
-- beside the auction house while it is open. Lists the mats to buy, then a Craft section with
-- the intermediate crafts (Copper Bar, ...) and the recipe itself. The main button walks the
-- steps: Find puts a mat in the auction house search box (bought with Buy Now), Craft puts a
-- recipe in the profession window's search box (made with Create). Clicking a row picks that step.
--
-- Draws Shopping's list and state; never calls C_AuctionHouse itself. Listens to
-- ShoppingChanged and does nothing while it is closed.
local _, ns = ...
local SW = ns:NewModule("ShopWindow")
local SH, P, C = ns.Shopping, ns.Pricing, ns.Crafting
local PUI = ns.KaboboUI
local S = PUI.Sizes

-- The columns plus the list's 6 px gaps (470) fit the content width (WIDTH - 2 x 18 = 504).
local WIDTH, HEIGHT = 540, 520
local ROWS = 14
local LIST_COLUMNS = {
	{ width = 170 }, { width = 40, justify = "RIGHT" }, { width = 40, justify = "RIGHT" },
	{ width = 50, justify = "RIGHT" }, { width = 50, justify = "RIGHT" }, { width = 90, justify = "RIGHT" },
}

local window

local function head(text) return PUI.Color(text, "accent") end

-- The header row above the craft steps, in the columns' place: what each column means there.
local CRAFT_HEADER = { header = true }

local function updateRow(row, m)
	if m.header then
		PUI.SetColumns(row, head("Craft"), head("Crafts"), head("Have"), head("Made"), head("Left"), head("Worth"))
		return
	end
	local name = P.ItemName(m.id)
	if SH.current == m and SH.state ~= "done" then name = PUI.Color("> " .. name, "accent") end
	if m.kind == "craft" then
		local left = SH.Remaining(m) == 0 and PUI.Color("done", "good")
			or (SH.Skipped(m.id) and PUI.Color("skipped", "bad")) or tostring(SH.Remaining(m))
		local makes = m.makes and m.makes > 1 and PUI.Color(" (x" .. C.FormatQty(m.makes) .. ")", "muted") or ""
		local cost = SH.MatCost(m)
		PUI.SetColumns(row, name .. makes, tostring(m.crafts), m.have > 0 and tostring(m.have) or "",
			tostring(SH.Made(m.id)), left, cost and PUI.Money(cost) or "")
		return
	end
	local left
	if m.vendor then
		left = PUI.Color("vendor", "muted")
	elseif SH.Remaining(m) == 0 then
		left = PUI.Color("done", "good")
	elseif SH.Skipped(m.id) then
		left = PUI.Color("skipped", "bad")
	else
		left = tostring(SH.Remaining(m))
	end
	local cost = SH.MatCost(m)
	PUI.SetColumns(row, name, tostring(m.need), tostring(m.have), tostring(SH.Bought(m.id)), left,
		cost and PUI.Money(cost) or PUI.Color("?", "muted"))
end

local function rowEnter(row, m)
	if m.header then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(m.id)
	GameTooltip:Show()
end

local function changeCrafts(delta)
	if SH.list then SH:SetCrafts(SH.list.crafts + delta) end
end

local function build()
	window = PUI.Window({
		name = "KaboboAuctionsShopFrame",
		title = "Shopping list",
		width = WIDTH,
		height = HEIGHT,
		position = ns.Ensure(ns.db.settings, "shopWindow"),
		onShow = function() SW:Refresh() end,
		-- Closing with the auction house keeps the list; closing it yourself drops it.
		onHide = function(_, reason) if reason ~= "host" then SH:Clear() end end,
	})
	local left = 18
	local top = -S.contentTop - 4

	window.itemLine = PUI.Text(window, "heading")
	window.itemLine:SetWidth(WIDTH - 2 * left - 120)
	window.itemLine:SetPoint("TOPLEFT", window, "TOPLEFT", left, top - 4)

	window.plusButton = PUI.Button(window, { text = "+", width = 24, onClick = function() changeCrafts(1) end })
	window.plusButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -left, top)
	window.craftsText = PUI.Text(window, "body", "CENTER")
	window.craftsText:SetWidth(60)
	window.craftsText:SetPoint("RIGHT", window.plusButton, "LEFT", -S.gap, 0)
	window.minusButton = PUI.Button(window, { text = "-", width = 24, onClick = function() changeCrafts(-1) end })
	window.minusButton:SetPoint("RIGHT", window.craftsText, "LEFT", -S.gap, 0)

	window.list = PUI.List(window, {
		kind = "columns", columns = LIST_COLUMNS, headers = true, update = updateRow, onEnter = rowEnter,
		onClick = function(_, m) SH:Find(m) end,
	})
	window.list:SetPoint("TOPLEFT", window, "TOPLEFT", left, top - 34)
	window.list:SetPoint("RIGHT", window, "RIGHT", -left, 0)
	window.list:SetHeight((ROWS + 1) * S.row)
	window.list:SetHeaders("Mat", "Need", "Have", "Bought", "Left", "Cost")

	-- Totals: mats cost, what the crafts sell for, profit.
	window.costLine = PUI.Text(window, "body", "LEFT")
	window.costLine:SetWidth(WIDTH - 2 * left)
	window.costLine:SetPoint("TOPLEFT", window.list, "BOTTOMLEFT", 0, -8)
	window.profitLine = PUI.Text(window, "body", "LEFT")
	window.profitLine:SetWidth(WIDTH - 2 * left)
	window.profitLine:SetPoint("TOPLEFT", window.costLine, "BOTTOMLEFT", 0, -4)

	window.statusLine = PUI.Text(window, "body", "LEFT", { wrap = true })
	window.statusLine:SetWidth(WIDTH - 2 * left)
	window.statusLine:SetPoint("TOPLEFT", window.profitLine, "BOTTOMLEFT", 0, -10)

	window.buyButton = PUI.Button(window, {
		text = "Find",
		width = 240,
		height = 28,
		onClick = function() SH:Find() end,
	})
	window.buyButton:SetPoint("TOP", window.statusLine, "BOTTOM", 0, -10)
	window.buyButton:SetPoint("LEFT", window, "LEFT", (WIDTH - 240) / 2, 0)

	window.craftsButton = PUI.Button(window, {
		text = "Crafts",
		width = 80,
		onClick = function() ns.CraftsWindow:Toggle() end,
	})
	window.craftsButton:SetPoint("RIGHT", window.buyButton, "LEFT", -12, 0)

	window.skipButton = PUI.Button(window, {
		text = "Skip",
		width = 80,
		onClick = function() SH:Skip() end,
	})
	window.skipButton:SetPoint("LEFT", window.buyButton, "RIGHT", 12, 0)

	window:Footer():SetText("You buy and craft with the game's buttons. Click a row to pick it.")
end

local function shown()
	return window ~= nil and window:IsShown()
end

local function dock()
	if AuctionHouseFrame and AuctionHouseFrame:IsShown() then window:DockTo(AuctionHouseFrame, { x = 2, y = 0 }) end
end

function SW:Refresh()
	if not shown() then return end
	local list = SH.list
	if not list then
		window.itemLine:SetText("")
		window.list:SetItems({})
		window.list:SetEmptyText("Click a recipe in the crafts window (/ka crafts).")
		window.statusLine:SetText("")
		window.costLine:SetText("")
		window.profitLine:SetText("")
		window.buyButton:Disable()
		window.skipButton:Disable()
		return
	end
	window.itemLine:SetText(P.ItemName(list.output))
	window.craftsText:SetText(list.crafts .. (list.crafts == 1 and " craft" or " crafts"))
	-- Buy rows, then the craft section.
	local items = {}
	for _, m in ipairs(list.mats) do items[#items + 1] = m end
	if list.steps and #list.steps > 0 then
		items[#items + 1] = CRAFT_HEADER
		for _, m in ipairs(list.steps) do items[#items + 1] = m end
	end
	window.list:SetItems(items, true)
	window.list:SetEmptyText(#items == 0 and "This recipe has no mats to buy." or nil)

	local t = SH.Totals(list)
	local unpriced = t.missing > 0 and PUI.Color(" + " .. t.missing .. " mats without a price", "muted") or ""
	window.costLine:SetText("Mats worth: " .. PUI.Money(t.cost) .. unpriced
		.. PUI.Color("  (incl. what you have)   still to buy: " .. PUI.Money(t.left), "muted"))
	if t.net then
		local profit = PUI.SignedMoney(t.profit)
		if t.missing > 0 then profit = profit .. PUI.Color(" (too high: some mats unpriced)", "muted") end
		local sold = ns.Sales.Text(ns.Sales:RateOf(list.output))
		local yours = ns.Sales:YouSold(list.output, 30)
		local demand = (sold and ("  " .. sold .. "/day leave the AH") or "")
			.. (yours > 0 and ("  you sold " .. yours .. " in 30d") or "")
		window.profitLine:SetText("Sells for " .. PUI.Money(t.net) .. " after the AH cut.  Profit: " .. profit
			.. (demand ~= "" and PUI.Color(" ·" .. demand, "muted") or ""))
	else
		window.profitLine:SetText("Profit: " .. PUI.Color("no AH price for " .. P.ItemName(list.output) .. " yet", "muted"))
	end

	local cap = math.floor((ns.db.settings.buyCap or 1.2) * 100 + 0.5)
	local status = SH.message or ("Pays at most " .. cap .. "% of market value. Bags were counted when the list was made.")
	local crafting = SH.current and SH.current.kind == "craft"
	if not ns.Scanner:IsOpen() and SH.state ~= "done" and not crafting then status = "Open the auction house to buy." end
	window.statusLine:SetText(status)
	window.buyButton:SetText(SH:ButtonText())
	local active = SH.state ~= "done" and SH.current ~= nil and (crafting or ns.Scanner:IsOpen())
	window.buyButton:SetEnabled(active)
	window.skipButton:SetEnabled(active)
end

-- Shopping list for `crafts` (default 1) crafts of the item.
function SW:Open(outputItemID, crafts)
	if not SH:Start(outputItemID, crafts or 1) then
		ns:Print("this character cannot craft that item.")
		return
	end
	-- The crafts window would sit on top of the list; the Crafts button brings it back.
	ns.CraftsWindow:Close()
	if not window then build() end
	window:Show()
	dock()
	SW:Refresh()
end

ns:On("ShoppingChanged", function() SW:Refresh() end)
-- A list that closed with the auction house comes back with it. The frame may show a moment
-- after the event, so dock on the next frame.
ns:On("AUCTION_HOUSE_SHOW", function()
	if not window or not SH.list then return end
	if not shown() then window:Show() end
	C_Timer.After(0, function() if shown() then dock() end end)
	SW:Refresh()
end)
ns:On("AUCTION_HOUSE_CLOSED", function() SW:Refresh() end)
