-- Kabobo's Auctions: the crafts window (/ka crafts). This character's learned recipes, one tab per
-- profession, ranked by profit (or profit per day, with the Sort button): mats cost (AH or
-- vendor), what one craft sells for after the AH cut and deposit, the profit, how many leave the
-- AH per day (an estimate, see Sales), how many you sold in 30 days, and how many are listed.
--
-- Built on first open. Reads only saved data (recipes from Crafting, prices from Pricing and
-- Vendor) and never calls C_TradeSkillUI, so it can open anywhere. Listens to PricesChanged,
-- VendorPricesChanged and CraftsChanged, and does nothing while it is closed.
local _, ns = ...
local CW = ns:NewModule("CraftsWindow")
local C, P = ns.Crafting, ns.Pricing
local PUI = ns.KaboboUI
local S = PUI.Sizes
local Money, Signed = PUI.Money, PUI.SignedMoney

local WIDTH, HEIGHT = 720, 470
local ROWS = 17
local LIST_COLUMNS = {
	{ width = 200 }, { width = 90, justify = "RIGHT" }, { width = 90, justify = "RIGHT" },
	{ width = 90, justify = "RIGHT" }, { width = 70, justify = "RIGHT" }, { width = 70, justify = "RIGHT" },
	{ width = 60, justify = "RIGHT" },
}

local window
local selected   -- professionID of the open tab

-- One ranked recipe (see Crafting.Rank), formatted only when its row shows.
local function updateRow(row, s)
	local name = P.ItemName(s.id)
	local made = math.floor(s.yield + 0.5)
	if made > 1 then name = name .. PUI.Color(" x" .. made, "muted") end
	local cost = Money(s.cost)
	if s.cost and s.missing > 0 then cost = cost .. PUI.Color("*", "muted") end
	local listed = s.listed and tostring(math.floor(s.listed)) or PUI.Color("-", "muted")
	local gone = ns.Sales.Text(s.rate) or PUI.Color("-", "muted")
	local sold = ns.Sales:YouSold(s.id, 30)
	PUI.SetColumns(row, name, cost, Money(s.net), s.profit and Signed(s.profit) or Money(nil), gone,
		sold > 0 and tostring(sold) or PUI.Color("-", "muted"), listed)
end

-- The item's own tooltip, which our tooltip hook fills with prices and the mats list.
local function rowEnter(row, s)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(s.id)
	GameTooltip:Show()
end

local function build()
	window = PUI.Window({
		name = "KaboboAuctionsCraftsFrame",
		title = ns.title .. ": crafts",
		width = WIDTH,
		height = HEIGHT,
		position = ns.Ensure(ns.db.settings, "craftsWindow"),
		onShow = function() CW:Refresh() end,
	})
	local left = 18
	local top = -S.contentTop - 4

	window.tabs = PUI.TabBar(window, {
		width = WIDTH - 2 * left,
		maxTabWidth = 130,
		onSelect = function(key)
			selected = key
			CW:Refresh()
			window.list:ScrollToTop()
		end,
	})
	window.tabs:SetPoint("TOPLEFT", window, "TOPLEFT", left, top)

	window.infoLine = PUI.Text(window, "body")
	window.infoLine:SetWidth(WIDTH - 2 * left - 180)
	window.infoLine:SetPoint("TOPLEFT", window.tabs, "BOTTOMLEFT", 0, -8)

	window.sortButton = PUI.Button(window, {
		width = 170,
		onClick = function()
			local s = ns.db.settings
			s.craftsSort = s.craftsSort == "day" and "profit" or "day"
			CW:Refresh()
			window.list:ScrollToTop()
		end,
	})
	window.sortButton:SetPoint("RIGHT", window, "RIGHT", -left, 0)
	window.sortButton:SetPoint("TOP", window.infoLine, "TOP", 0, 5)

	window.list = PUI.List(window, {
		kind = "columns", columns = LIST_COLUMNS, headers = true, update = updateRow, onEnter = rowEnter,
		onClick = function(_, s) ns.ShopWindow:Open(s.id) end,
	})
	window.list:SetPoint("TOPLEFT", window.infoLine, "BOTTOMLEFT", 0, -8)
	window.list:SetPoint("RIGHT", window, "RIGHT", -left, 0)
	window.list:SetHeight((ROWS + 1) * S.row)
	window.list:SetHeaders("Item", "Mats cost", "After cut", "Profit", "Gone/day", "You sold", "Listed")

	window:Footer():SetText("Per craft. Gone/day: left the AH between two scans (sold, expired or cancelled). "
		.. "You sold: 30 days. Click a recipe to shop.")
end

local function shown()
	return window ~= nil and window:IsShown() and ns.realmKey ~= nil
end

function CW:Refresh()
	if not shown() then return end
	local profs = C:Professions()
	local valid = false
	for _, p in ipairs(profs) do
		if p.key == selected then valid = true end
	end
	if not valid then selected = profs[1] and profs[1].key or nil end
	window.tabs:SetTabs(profs, selected)

	local me = C:CharTable()
	local prof = selected ~= nil and me and me[selected]
	local sort = ns.db.settings.craftsSort
	window.sortButton:SetText(sort == "day" and "Sort: profit per day" or "Sort: profit per craft")
	local rateOf = function(id) return ns.Sales:RateOf(id) end
	local rows = prof and C.Rank(prof.r, C.MatPrice, C.RecipeOf, C.AHPrice, C.AHListed, rateOf, sort) or {}
	local profitable, unpriced = 0, 0
	for _, s in ipairs(rows) do
		if s.tier == 1 and s.profit > 0 then profitable = profitable + 1 end
		if s.tier == 3 then unpriced = unpriced + 1 end
	end
	window.list:SetItems(rows, true)

	if #profs == 0 then
		window.infoLine:SetText("")
		window.list:SetEmptyText("No recipes saved yet. Open each of your profession windows once.")
		return
	end
	window.infoLine:SetText(string.format("%d recipes   %s   %s", #rows,
		PUI.Color(profitable .. " profitable", "good"),
		PUI.Color(unpriced .. " without AH prices (listed last)", "muted")))
	window.list:SetEmptyText(#rows == 0 and "No recipes that make an item." or nil)
end

function CW:Close()
	if window and window:IsShown() then window:Close("user") end
end

-- Opens the window on a profession's tab (professionID; nil keeps the last one).
function CW:Open(professionID)
	if not window then build() end
	if professionID then selected = professionID end
	window:Show()
	CW:Refresh()
end

function CW:Toggle()
	if not window then build() end
	window:Toggle()
end

ns:On("PricesChanged", function() CW:Refresh() end)
ns:On("VendorPricesChanged", function() CW:Refresh() end)
ns:On("CraftsChanged", function() CW:Refresh() end)
