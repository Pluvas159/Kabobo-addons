-- Pluvas' Auctions: AH mats cost, sale value and profit in the profession window.
--
-- Hooks the modern profession window (Blizzard_Professions, load-on-demand) with
-- hooksecurefunc only, and draws into a frame of our own, so nothing of Blizzard's is replaced.
local _, ns = ...
local PU = ns:NewModule("ProfessionsUI")
local C, P = ns.Crafting, ns.Pricing

local LABEL = "|cff22b8cf"
local GRAY, GREEN, RED = "|cff808080", "|cff40d040", "|cffff5050"

PU.MAX_MAT_LINES = 10

-- Lines for one craft, as { label, value, sub = mat line } entries, from a C.CraftSummary
-- result. Mat lines are left out when showMats is false.
function PU.BuildLines(summary, showMats)
	local lines = {}
	local per = ""
	if summary.yield and summary.yield ~= 1 then
		per = GRAY .. " (per craft, makes " .. string.format("%g", summary.yield) .. ")|r"
	end

	local cost
	if summary.cost then
		cost = ns.MoneyIcons(summary.cost)
		if summary.missing > 0 then
			cost = cost .. GRAY .. " (" .. summary.missing .. " mats unpriced)|r"
		end
	else
		cost = GRAY .. "no AH prices for mats|r"
	end
	lines[#lines + 1] = { "Mats cost (AH)" .. per, cost }

	-- The base mats behind that cost, most expensive first.
	local mats = summary.mats or {}
	if showMats == nil then showMats = true end
	if showMats then
		for i = 1, math.min(#mats, PU.MAX_MAT_LINES) do
			local m = mats[i]
			lines[#lines + 1] = {
				"   " .. C.FormatQty(m.qty) .. "x " .. P.ItemName(m.id),
				m.cost and ns.MoneyIcons(m.cost) or (GRAY .. "no price|r"),
				sub = true,
			}
		end
		if #mats > PU.MAX_MAT_LINES then
			lines[#lines + 1] = { "   +" .. (#mats - PU.MAX_MAT_LINES) .. " more", "", sub = true }
		end
	end

	if summary.value then
		lines[#lines + 1] = { "Sells for (AH)", ns.MoneyIcons(summary.value) }
		lines[#lines + 1] = { "After cut & deposit", ns.MoneyIcons(summary.net) }
		if summary.profit then
			local p = summary.profit
			local text
			if p > 0 then
				text = GREEN .. "+|r" .. ns.MoneyIcons(p)
			elseif p < 0 then
				text = RED .. "-|r" .. ns.MoneyIcons(-p)
			else
				text = ns.MoneyIcons(0)
			end
			lines[#lines + 1] = { "Profit", text }
		end
	else
		lines[#lines + 1] = { "Sells for (AH)", GRAY .. "no AH price yet|r" }
	end
	return lines
end

-- Summary for a recipe in the open window, or nil when it makes no item or has no basic mats.
function PU.SummaryFor(recipeID)
	local out, recipe = C:ReadSchematic(recipeID)
	if not out then return nil end
	return C.CraftSummary(recipe, C.MatPrice, C.RecipeOf, C.MatPrice(out))
end

-- Panel -------------------------------------------------------------------

local panel
local labels, values = {}, {}
local LINE_HEIGHT = 14

local FALLBACK_BOTTOM = 44   -- clears the Track Recipe checkbox if we cannot measure it

local function createPanel(form)
	panel = CreateFrame("Frame", nil, form)
	panel.form = form
	panel:SetSize(250, LINE_HEIGHT)
	panel:Hide()
end

-- Bottom left of the recipe details, lined up with the "Reagents:" column, growing upward,
-- and starting just above the Track Recipe checkbox that sits along the bottom edge.
local function placePanel()
	local form = panel.form
	local bottom = FALLBACK_BOTTOM
	local cb = form.TrackRecipeCheckbox
	if cb and cb.GetTop and cb:GetTop() and form:GetBottom() then
		bottom = cb:GetTop() - form:GetBottom() + 6
	end
	panel:ClearAllPoints()
	panel:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 28, bottom)
end

-- Font strings are made on demand, since the number of mats varies per recipe.
local function lineWidgets(i)
	if not labels[i] then
		local l = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(i - 1) * LINE_HEIGHT)
		l:SetJustifyH("LEFT")
		local v = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		v:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(i - 1) * LINE_HEIGHT)
		v:SetJustifyH("RIGHT")
		labels[i], values[i] = l, v
	end
	return labels[i], values[i]
end

function PU:Update(recipeInfo)
	if not panel then return end
	local summary = ns.db.settings.professionPanel and recipeInfo and PU.SummaryFor(recipeInfo.recipeID)
	if not summary then
		panel:Hide()
		return
	end
	local lines = PU.BuildLines(summary, ns.db.settings.matsList)
	for i = 1, #lines do
		local l, v = lineWidgets(i)
		local line = lines[i]
		l:SetText(line.sub and ("|cffd9d9d9" .. line[1] .. "|r") or (LABEL .. line[1] .. "|r"))
		v:SetText(line[2])
		l:Show(); v:Show()
	end
	for i = #lines + 1, #labels do
		labels[i]:Hide(); values[i]:Hide()
	end
	panel:SetHeight(#lines * LINE_HEIGHT)
	placePanel()
	panel:Show()
end

local hooked = false
function PU:Hook()
	if hooked then return end
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if not (form and form.Init) then
		ns:Debug("profession window not found, no profession panel")
		return
	end
	hooked = true
	createPanel(form)
	local update = ns:Guard("Profession panel", function(_, recipeInfo) PU:Update(recipeInfo) end)
	hooksecurefunc(form, "Init", update)
	-- Prices can change while the window is closed; redraw the shown recipe when it reopens.
	form:HookScript("OnShow", function(self)
		if self.GetRecipeInfo then update(self, self:GetRecipeInfo()) end
	end)
end

ns:On("ADDON_LOADED", function(name)
	if name == "Blizzard_Professions" then PU:Hook() end
end)

function PU:OnLogin()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Professions")
	if loaded then PU:Hook() end
end
