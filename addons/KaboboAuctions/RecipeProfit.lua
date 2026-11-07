-- Kabobo's Auctions: profit per craft beside each recipe in the profession window's recipe list,
-- and a "Profit ranking" button under the window that opens the crafts window on that profession.
--
-- The list is Blizzard's ScrollBox (ProfessionsFrame.CraftingPage.RecipeList.ScrollBox). Rows are
-- only decorated: a font string of our own on each row, refreshed when rows are acquired, the
-- list scrolls or its data changes, and when prices change. Nothing of Blizzard's is replaced.
local _, ns = ...
local RP = ns:NewModule("RecipeProfit")
local C = ns.Crafting
local PUI = ns.KaboboUI

RP.RIGHT_OFFSET = -4
RP.GAP = 6          -- between the recipe name and the label
RP.MIN_NAME = 60    -- the name keeps at least this much room

local labels = setmetatable({}, { __mode = "k" })   -- [row frame] = font string
local schematics = {}                               -- [recipeID] = { out, recipe } or false
local box

-- The output item and recipe string of a recipe in the open window, cached per recipeID (a
-- schematic does not change). nil for recipes that make no item.
local function recipeOf(recipeID)
	local cached = schematics[recipeID]
	if cached == nil then
		local out, recipe = C:ReadSchematic(recipeID)
		if not out then
			-- The window may not be readable yet; only cache a real answer.
			if C_TradeSkillUI and ProfessionsFrame and ProfessionsFrame:IsShown() then schematics[recipeID] = false end
			return nil
		end
		cached = { out = out, recipe = recipe }
		schematics[recipeID] = cached
	end
	return cached or nil
end

-- The text beside a recipe: its profit per craft, "*" when some mats have no price, and how
-- many sell per day when known (rate, solid: see Sales:RateOf). nil when the crafted item has no AH
-- price (or the recipe makes no item).
function RP.Text(summary, rate, solid)
	if not (summary and summary.profit) then return nil end
	local text = PUI.SignedMoney(summary.profit)
	if summary.missing and summary.missing > 0 then text = text .. PUI.Color("*", "muted") end
	local sold = ns.Sales.Text(rate)
	if sold then text = text .. PUI.Color("  " .. sold .. "/d", solid and "soft" or "muted") end
	return text
end

local function textFor(row)
	if not ns.db.settings.recipeProfit then return nil end
	local data = row.GetElementData and row:GetElementData()
	data = data and data.GetData and data:GetData()
	local info = data and data.recipeInfo
	if not (info and info.recipeID) then return nil end
	local r = recipeOf(info.recipeID)
	if not r then return nil end
	return RP.Text(C.CraftSummary(r.recipe, C.MatPrice, C.RecipeOf, C.AHPrice(r.out)), ns.Sales:RateOf(r.out))
end

-- How wide the recipe name may be so it ends before our label: the row's width, minus where the
-- name starts, the label and a gap. nil when it fits anyway or cannot be measured.
function RP.NameWidth(rowLeft, rowWidth, nameLeft, nameWidth, labelWidth)
	if not (rowLeft and rowWidth and nameLeft and nameWidth and labelWidth) or labelWidth <= 0 then return nil end
	local room = rowWidth - (nameLeft - rowLeft) - labelWidth - RP.GAP - math.abs(RP.RIGHT_OFFSET)
	if nameWidth <= room then return nil end
	return math.max(RP.MIN_NAME, room)
end

local function decorate(row)
	local text = textFor(row)
	local fs = labels[row]
	if not fs then
		if not text then return end
		fs = PUI.Text(row, "body", "RIGHT")
		fs:SetPoint("RIGHT", row, "RIGHT", RP.RIGHT_OFFSET, 0)
		labels[row] = fs
	end
	fs:SetText(text or "")
	-- Shorten the recipe name (it ends in "...") rather than draw over it. Blizzard sets the name's
	-- width again whenever it fills the row, so this is redone on every refresh.
	local name = row.Label
	if text and name and name.SetWidth and name.GetLeft and row.GetLeft then
		local width = RP.NameWidth(row:GetLeft(), row:GetWidth(), name:GetLeft(),
			name.GetStringWidth and name:GetStringWidth() or name:GetWidth(), fs:GetStringWidth())
		if width then name:SetWidth(width) end
	end
end

function RP:Refresh()
	if not (box and box.ForEachFrame and box:IsVisible()) then return end
	box:ForEachFrame(decorate)
end

local pending = false
function RP:RefreshSoon()
	if pending then return end
	pending = true
	C_Timer.After(0, ns:Guard("Recipe profit", function()
		pending = false
		RP:Refresh()
	end))
end

local function professionID()
	local TS = C_TradeSkillUI
	local base = TS and TS.GetBaseProfessionInfo and ns.Try(TS.GetBaseProfessionInfo)
	return base and base.professionID
end

function RP:Hook()
	local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
	box = list and list.ScrollBox
	if not box then
		ns:Debug("profession recipe list not found, no profit labels")
		return
	end
	local update = ns:Guard("Recipe profit", function() RP:Refresh() end)
	-- A row can be acquired before Blizzard fills it, so draw on the next frame.
	if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
		ScrollUtil.AddAcquiredFrameCallback(box, function() RP:RefreshSoon() end, RP, true)
	end
	if box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
		box:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, update, RP)
		if ScrollBoxListMixin.Event.OnDataRangeChanged then
			box:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, update, RP)
		end
	end
	box:HookScript("OnShow", update)

	local button = PUI.Button(ProfessionsFrame, {
		name = "KaboboAuctionsProfitButton",
		text = "Profit ranking",
		width = 130,
		onClick = function() ns.CraftsWindow:Open(professionID()) end,
	})
	-- Left of Kabobo's Professions' "Show unlearned" button (190 wide, at the right edge).
	button:SetPoint("TOPRIGHT", ProfessionsFrame, "BOTTOMRIGHT", -196, -2)
end

ns:WhenLoaded("Blizzard_Professions", function() RP:Hook() end)

-- The recipe list redraws its rows on a new profession; schematics are per recipeID, so they stay.
ns:On("TRADE_SKILL_LIST_UPDATE", function() RP:RefreshSoon() end)
ns:On("PricesChanged", function() RP:Refresh() end)
ns:On("VendorPricesChanged", function() RP:Refresh() end)
ns:On("SettingChanged", function(key) if key == "recipeProfit" then RP:Refresh() end end)
