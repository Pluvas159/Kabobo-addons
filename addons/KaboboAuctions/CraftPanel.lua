-- Kabobo's Auctions: mats cost (AH or vendor), sale value and profit in the profession window.
--
-- Hooks the modern profession window (Blizzard_Professions, load-on-demand) with hooksecurefunc
-- only, and draws into a PUI.LinePanel of our own, so nothing of Blizzard's is replaced.
local _, ns = ...
local CP = ns:NewModule("CraftPanel")
local C, Lines = ns.Crafting, ns.Lines
local PUI = ns.KaboboUI

local FALLBACK_BOTTOM = 44   -- clears the Track Recipe checkbox if we cannot measure it

local panel

-- Summary for a recipe in the open window, or nil when it makes no item or has no basic mats.
-- With Kabobo's Professions loaded, it also says what the item would disenchant for.
function CP.SummaryFor(recipeID)
	local out, recipe = C:ReadSchematic(recipeID)
	if not out then return nil end
	local summary = C.CraftSummary(recipe, C.MatPrice, C.RecipeOf, C.AHPrice(out))   -- price, seen
	-- Asked every time: Kabobo's Professions may load after this addon, or not at all.
	local professions = ns:Peer("KaboboProfessions")
	if professions and professions.DisenchantValue then
		C.AddDisenchant(summary, professions.DisenchantValue(out, C.AHPrice))
	end
	return summary
end

-- Bottom left of the recipe details, lined up with the "Reagents:" column, growing upward, and
-- starting just above the Track Recipe checkbox that sits along the bottom edge.
local function place()
	local form = panel:GetParent()
	local bottom = FALLBACK_BOTTOM
	local cb = form.TrackRecipeCheckbox
	if cb and cb.GetTop and cb:GetTop() and form.GetBottom and form:GetBottom() then
		bottom = cb:GetTop() - form:GetBottom() + 6
	end
	panel:ClearAllPoints()
	panel:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 28, bottom)
end

function CP:Update(recipeInfo)
	if not panel then return end
	local s = ns.db.settings
	local summary = s.professionPanel and recipeInfo and CP.SummaryFor(recipeInfo.recipeID)
	if not summary then
		panel:Hide()
		return
	end
	panel:SetLines(Lines.Craft(summary, s.matsList, time()))
	place()
	panel:Show()
end

function CP:Hook()
	if panel then return end
	local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
	if not (form and form.Init) then
		ns:Debug("profession window not found, no profession panel")
		return
	end
	panel = PUI.LinePanel(form, { width = 250 })
	local update = ns:Guard("Profession panel", function(_, recipeInfo) CP:Update(recipeInfo) end)
	hooksecurefunc(form, "Init", update)
	-- Prices can change while the window is closed; redraw the shown recipe when it reopens.
	form:HookScript("OnShow", function(self)
		if self.GetRecipeInfo then update(self, self:GetRecipeInfo()) end
	end)
end

ns:WhenLoaded("Blizzard_Professions", function() CP:Hook() end)
