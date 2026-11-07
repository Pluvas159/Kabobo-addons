-- Pluvas' Professions: the unlearned-recipes panel and its button under the profession window.
--
-- Built with PluvasUI (Libs/PluvasUI). The panel docks to the right of ProfessionsFrame when the
-- profession window is open, and floats on its own when opened with /pprof. It only reads saved
-- data, never a game API, so it works the same with the profession window closed.
local _, ns = ...
local Panel = ns:NewModule("Panel")
local D, Rows = ns.Data, ns.Rows
local PUI = ns.PluvasUI
local S = PUI.Sizes

local WIDTH, HEIGHT = 340, 520
local LIST_TOP, LIST_BOTTOM = 76, 34

local window, list, tabs, summaryText, toggleButton
local selected            -- profession shown in the panel
local follow = true       -- while docked, show whichever profession the window has open

local function contains(items, value)
	for _, v in ipairs(items) do
		if v == value then return true end
	end
	return false
end

local function playerLevel()
	return UnitLevel and UnitLevel("player") or 0
end

local function buildRows(name)
	local prof = name and D:Prof(name, false)
	return Rows.Build(prof, D:Catalog(name, false), {
		level = playerLevel(),
		hideUnknown = ns.db.settings.hideUnknown,
		collapsed = ns.db.settings.collapsed,
		vendors = ns.db.vendor,
	})
end

local function shown()
	return window ~= nil and window:IsShown()
end

local function dockedShown()
	return shown() and window:IsDocked()
end

-- Rows ----------------------------------------------------------------------------

-- Right column: required skill (red until reached) and cost for trainer recipes, price for vendor
-- recipes, else the grey level the group is sorted by.
local function rightText(e)
	local t = e.trainer
	if e.group == "vendor" and e.vendor then
		return e.vendor.c and PUI.Money(e.vendor.c) or ""
	end
	if not t or e.group ~= "trainer" then
		return e.grey and PUI.Color(e.grey, "muted") or ""
	end
	local right = ""
	if t.s then right = e.learnable and tostring(t.s) or PUI.Color(t.s, "bad") end
	if t.c then right = right .. "  " .. PUI.Money(t.c) end
	return right
end

local function updateRow(row, e)
	if e.header then
		PUI.SetIconRow(row, {
			header = true,
			text = (e.collapsed and "+ " or "- ") .. e.text,
			right = PUI.Color(e.count, "muted"),
		})
		return
	end
	local name = e.name or "?"
	if e.learnable then
		name = PUI.Color(name, "good")
	elseif e.learnable == false then
		name = PUI.Color(name, "muted")
	end
	PUI.SetIconRow(row, { icon = e.icon, text = name, right = rightText(e), desaturate = e.learnable == false })
end

local function place(v)
	return (v.v or "a vendor") .. (v.z and (" (" .. v.z .. ")") or "")
end

local function tooltipLines(e)
	local lines = {}
	local function add(text, color) lines[#lines + 1] = { text = text, color = color } end
	if e.header then
		if e.key == "unknown" then
			add("Forever gives no source for these recipes, and some may not be in the game yet. "
				.. "Trainers and vendors you visit move their recipes out of this group.")
			add("The gray number is the skill where a recipe turns grey.", "muted")
		end
		add(e.collapsed and "Click to show." or "Click to hide.", "muted")
		return lines
	end
	if e.source then
		for line in e.source:gmatch("[^\n]+") do add(line, "soft") end
	end
	local t = e.trainer
	if t then
		if #lines > 0 then add(" ") end
		if t.w then add("Trainer: " .. place({ v = t.w, z = t.z }), "gold") end
		local prof = D:Prof(selected, false)
		if t.s then
			add("Requires " .. selected .. " (" .. t.s .. ")", (prof and prof.skill or 0) >= t.s and "good" or "bad")
		end
		if t.lv then add("Requires level " .. t.lv, playerLevel() >= t.lv and "good" or "bad") end
		if t.c then add("Cost: " .. PUI.Money(t.c)) end
		if e.learnable then add("You can learn this now.", "good") end
	end
	local v = e.vendor
	if v then
		if #lines > 0 then add(" ") end
		add("Sold by " .. place(v), "gold")
		if v.it then add(v.it) end
		if v.c then add("Cost: " .. PUI.Money(v.c) .. (v.lim and "  (limited supply)" or "")) end
	end
	if not (e.source or t or v) then
		add("No source known yet. Trainers and vendors you visit fill this in.", "muted")
	end
	if e.grey then add("Turns grey at skill " .. e.grey .. ".", "muted") end
	return lines
end

local function rowEnter(row, e)
	PUI.ShowTooltip(row, e.header and e.text or (e.name or "?"), tooltipLines(e))
end

local function rowClick(row, e)
	if not (e.header and e.key) then return end
	-- false, not nil, so the collapsed-by-default groups stay open after a reload.
	ns.db.settings.collapsed[e.key] = not e.collapsed
	Panel:Refresh()
	-- The row now holds the refreshed header; update its tooltip.
	if row.item then rowEnter(row, row.item) end
end

-- Panel -------------------------------------------------------------------------

local function updateFooter()
	local first, last, total = list:Range()
	if total > last - first + 1 then
		window:Footer():SetText(string.format("%d-%d of %d rows. Scroll with the mouse wheel.", first, last, total))
	else
		window:Footer():SetText("Hover a recipe to see where to learn it.")
	end
end

local function build()
	window = PUI.Window({
		name = "PluvasProfessionsFrame",
		title = "Unlearned recipes",
		width = WIDTH,
		height = HEIGHT,
		-- While docked, showing or hiding the panel is the player's choice for the next time a
		-- profession window opens, however it happens (button, close button, /pprof). Closing
		-- because the profession window itself closed ("host") does not count.
		onShow = function(w)
			if w:IsDocked() then ns.db.settings.panel = true end
			Panel:Refresh()
		end,
		onHide = function(w, reason)
			if w:IsDocked() and reason ~= "host" then ns.db.settings.panel = false end
			Panel:Refresh()
		end,
	})

	tabs = PUI.TabBar(window, {
		width = WIDTH - 2 * S.pad,
		onSelect = function(name)
			selected = name
			follow = false
			Panel:Refresh()
		end,
	})
	tabs:SetPoint("TOPLEFT", window, "TOPLEFT", S.pad, -S.contentTop)

	summaryText = PUI.Text(window, "label", "LEFT")
	summaryText:SetPoint("TOPLEFT", window, "TOPLEFT", S.pad, -56)
	summaryText:SetPoint("RIGHT", window, "RIGHT", -S.pad, 0)

	list = PUI.List(window, {
		update = updateRow,
		onEnter = rowEnter,
		onClick = rowClick,
		onScroll = updateFooter,
	})
	list:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -LIST_TOP)
	list:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -12, LIST_BOTTOM)
end

-- Cheap when nothing is visible: the list is only built for a panel or button that shows it.
function Panel:Refresh()
	if not shown() then
		Panel:UpdateToggleButton()
		return
	end

	local names = D:ProfNames()
	if window:IsDocked() and follow and ns.Recipes.current and contains(names, ns.Recipes.current) then
		selected = ns.Recipes.current
	end
	if not selected or not contains(names, selected) then selected = names[1] end
	tabs:SetTabs(names, selected)

	local rows, summary = buildRows(selected)
	Panel:UpdateToggleButton(selected, summary)
	local prof = selected and D:Prof(selected, false)
	if not prof then
		summaryText:SetText("")
	else
		local line = selected
		if prof.skill and prof.max and prof.max > 0 then line = line .. " " .. prof.skill .. "/" .. prof.max end
		line = line .. "   " .. summary.total .. " not learned"
		if summary.learnable > 0 then line = line .. "   " .. PUI.Color(summary.learnable .. " to learn now", "good") end
		summaryText:SetText(line)
	end

	list:SetItems(rows, true)

	local hasTrainer = false
	for _, r in ipairs(rows) do
		if r.header and r.key == "trainer" then hasTrainer = true end
	end
	if not selected then
		list:SetEmptyText("No recipe data yet.\n\nOpen each of your profession windows once, "
			.. "and visit your trainers, to fill this list.")
	elseif #rows == 0 then
		list:SetEmptyText("No unlearned recipes found.\n\nVisit a trainer for this profession to add "
			.. "the recipes it teaches.")
	elseif not hasTrainer then
		list:SetEmptyText("Visit a " .. selected .. " trainer: the recipes it teaches move into a "
			.. "Trainer group here, with the skill they need and what they cost.")
	else
		list:SetEmptyText(nil)
	end
	updateFooter()
end

-- Forever's profession tabs hang off ProfessionsFrame's right edge (anchored to its TOPRIGHT), so
-- dock past them.
local function dockOffset()
	local tab = ProfessionsFrame.ProfessionsOverviewTab
	local width = tab and tab.GetWidth and tab:GetWidth() or 0
	if width <= 0 then width = 48 end
	return width + 6
end

-- Opens the panel, docked to the profession window when that is open.
function Panel:Open()
	if not window then build() end
	local docked = ProfessionsFrame ~= nil and window:DockTo(ProfessionsFrame, { x = dockOffset(), minHeight = 300 })
	if docked then
		follow = true
		-- onShow records the choice, but a panel that was already floating gets no OnShow when it
		-- docks, so record it here too.
		ns.db.settings.panel = true
	else
		window:Float()
	end
	window:Show()
	list:ScrollToTop()
	Panel:Refresh()
end

function Panel:Toggle()
	if shown() then window:Close("user") else Panel:Open() end
end

-- Button under the profession window ----------------------------------------------

-- known: rows summary of the panel's profession, reused when it is the open one, so a refresh
-- builds the list once.
function Panel:UpdateToggleButton(knownName, knownSummary)
	-- Hidden with the profession window: nothing to update, and no list to build.
	if not toggleButton or not toggleButton:IsVisible() then return end
	if dockedShown() then
		toggleButton:SetText("Hide unlearned")
		return
	end
	local current = ns.Recipes.current
	local summary = knownName == current and knownSummary or select(2, buildRows(current))
	if current and summary.total > 0 then
		local label = "Show unlearned (" .. summary.total .. ")"
		if summary.learnable > 0 then label = label .. " " .. PUI.Color("+" .. summary.learnable, "good") end
		toggleButton:SetText(label)
	else
		toggleButton:SetText("Show unlearned")
	end
end

local function createToggleButton()
	if toggleButton or not ProfessionsFrame then return end
	toggleButton = PUI.Button(ProfessionsFrame, {
		name = "PluvasProfessionsToggleButton",
		width = 190,
		-- The panel's onShow/onHide remember the choice.
		onClick = function()
			if dockedShown() then window:Close("user") else Panel:Open() end
		end,
		tooltip = {
			title = ns.title,
			lines = {
				"List the recipes you have not learned yet, and where to learn them.",
				{ text = "The green number is how many a trainer can teach you right now.", color = "muted" },
				{ text = "Your choice is remembered for the next time you open a profession.", color = "muted" },
			},
		},
	})
	toggleButton:SetPoint("TOPRIGHT", ProfessionsFrame, "BOTTOMRIGHT", 0, -2)

	-- On Forever the window can stay open on its overview page after the trade skill closes, so
	-- follow the frame itself rather than TRADE_SKILL_SHOW / TRADE_SKILL_CLOSE. Closing with it
	-- is handled by the docked window.
	ProfessionsFrame:HookScript("OnShow", ns:Guard("Professions OnShow", function()
		if ns.db.settings.panel and not dockedShown() then Panel:Open() else Panel:Refresh() end
	end))
	return true
end

local setUp
setUp = ns:Guard("Professions window", function(retry)
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
		-- Not loaded or not shown yet: try once more a little later.
		if retry then C_Timer.After(0.3, function() setUp(false) end) end
		return
	end
	-- The first time, the frame is already showing before the OnShow hook exists.
	if createToggleButton() and ns.db.settings.panel then Panel:Open() end
	Panel:Refresh()
end)

ns:On("TRADE_SKILL_SHOW", function()
	-- ProfessionsFrame loads on demand and shows in the same frame; set up on the next one.
	C_Timer.After(0, function() setUp(true) end)
end)

ns:On("RecipesChanged", function() Panel:Refresh() end)
ns:On("SettingChanged", function(key)
	if key == "hideUnknown" or key == "panel" then Panel:Refresh() end
end)
