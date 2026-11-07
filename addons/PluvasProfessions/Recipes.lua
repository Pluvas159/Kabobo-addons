-- Pluvas' Professions: reads the open profession window.
--
-- On Forever, Blizzard's profession window never lists unlearned recipes: its Camelot code forces
-- C_TradeSkillUI.SetShowUnlearned(false) every time the list is built. The addon does not fight
-- that. It reads every recipe ID of the open profession itself and keeps the unlearned ones, with
-- Blizzard's source text ("Trainer", "Vendor: ...", "Drop: ..."), for its own list.
--
-- C_TradeSkillUI is only called while the trade skill session is open, and only for the
-- character's own professions (not linked, guild or NPC crafting views).
local _, ns = ...
local R = ns:NewModule("Recipes")
local D = ns.Data

local SCAN_BATCH = 30      -- recipes read per frame
-- Seconds before a list update rereads the same profession. The list updates constantly while
-- crafting; opening the window or switching profession always rereads, and NEW_RECIPE_LEARNED
-- covers recipes learned in between.
local RESCAN_AFTER = 60

R.current = nil            -- name of the profession open in the window

local trade = ns:TradeSkillSession()
local scanning = false
local lastScan = {}        -- [professionName] = time() of the last finished read

-- Keep skill levels current and drop professions this character no longer has. Pruning only
-- runs when the client lists at least one profession, so an early call cannot wipe everything.
function R:SyncProfessions(prune)
	local char = D:Char(false)
	if not char then return end
	local known, any = ns:KnownProfessions()
	for name, p in pairs(char) do
		local k = known[name]
		if k then
			p.skill, p.max = k.skill or p.skill, k.max or p.max
		elseif prune and any then
			char[name] = nil
		end
	end
end

-- Merge one read of a profession into its saved entry.
--   unlearned = { [recipeID] = { n, i, s, g, t } }, learned = { [lowercase name] = true }
--   complete  = every recipe was read without errors, so the read can replace the saved list
function R.Store(name, info, unlearned, learned, complete)
	local p = D:Prof(name, true)
	if not p then return end
	if info then
		p.id = info.professionID or p.id
		p.skill = info.skillLevel or p.skill
		p.max = info.maxSkillLevel or p.max
	end
	p.scanned = time()
	if complete then
		p.u = unlearned
	else
		for id, r in pairs(unlearned) do p.u[id] = r end
	end
	for id, r in pairs(p.u) do
		if learned[D.Key(r.n) or ""] then p.u[id] = nil end
	end
	for key in pairs(learned) do p.tu[key] = nil end
end

-- Reading the window ----------------------------------------------------------

-- All recipe IDs of the open profession. The second value says whether the list includes
-- unlearned recipes for sure: GetFilteredRecipeIDs follows Blizzard's filters, which hide them.
local function recipeIDs(TS, api)
	local ids = api:Call(TS.GetAllRecipeIDs)
	if type(ids) == "table" and #ids > 0 then return ids, true end
	ids = api:Call(TS.GetFilteredRecipeIDs)
	if type(ids) == "table" then return ids, false end
	return nil, false
end

local function readRecipe(TS, api, id, unlearned, learned)
	local info = api:Call(TS.GetRecipeInfo, id)
	if type(info) ~= "table" or not info.name or info.isDummyRecipe then return end
	if info.learned then
		local key = D.Key(info.name)
		if key then learned[key] = true end
		return
	end
	local source = api:Call(TS.GetRecipeSourceText, id)
	unlearned[id] = {
		n = info.name,
		i = info.icon,
		s = (type(source) == "string" and source ~= "") and source or nil,
		-- Skill at which the recipe turns grey; sorts recipes that have no known source.
		g = type(info.maxTrivialLevel) == "number" and info.maxTrivialLevel > 0 and info.maxTrivialLevel or nil,
		-- Raw source type number, if a later client fills it (Forever build 70862 does not).
		t = type(info.sourceType) == "number" and info.sourceType or nil,
	}
end

function R:Scan(force)
	local TS = C_TradeSkillUI
	local api = ns.NewCaller()
	if scanning or not ns:ViewingOwnProfession(api) then return end
	local name, base = ns:OpenProfession(api)
	if not name then return end
	if R.current ~= name then
		R.current = name
		ns:Send("RecipesChanged")
	end
	if not force and lastScan[name] and time() - lastScan[name] < RESCAN_AFTER then return end
	local ids, all = recipeIDs(TS, api)
	if not ids then return end

	scanning = true
	local unlearned, learned = {}, {}
	ns:Spread({
		name = "Recipe scan",
		count = #ids,
		size = SCAN_BATCH,
		-- The window can close between frames; drop the read rather than call the API closed.
		alive = function() return trade.open end,
		step = function(i) readRecipe(TS, api, ids[i], unlearned, learned) end,
		done = function(ok)
			scanning = false
			if not ok then return end
			R.Store(name, base, unlearned, learned, all and api.failures == 0)
			lastScan[name] = time()
			ns:Debug("recipes:", name, #ids, "recipes read,", api.failures, "failed calls, all =", tostring(all))
			ns:Send("RecipesChanged")
		end,
	})
end

-- Opening the window or switching profession forces a reread; list updates while crafting do
-- not. A burst of events is read once it settles, forced if any of them asked for it.
local forceNext = false
local scanSoon = ns:Debounce("Recipe scan", 0.5, function()
	local force = forceNext
	forceNext = false
	R:Scan(force)
end)
local function requestScan(force)
	forceNext = forceNext or force
	scanSoon()
end

ns:On("TRADE_SKILL_SHOW", function() requestScan(true) end)
-- Fires when the list changes, including switching to another profession in the window.
ns:On("TRADE_SKILL_LIST_UPDATE", function() requestScan(false) end)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() requestScan(true) end)
ns:On("TRADE_SKILL_CLOSE", function()
	R.current = nil
	ns:Send("RecipesChanged")
end)

-- Learned from a trainer, a recipe item or anywhere else: take it off the list straight away.
ns:On("NEW_RECIPE_LEARNED", function(recipeID)
	D:Forget(recipeID, C_Spell and ns.Try(C_Spell.GetSpellName, recipeID))
end)

ns:On("SKILL_LINES_CHANGED", function()
	R:SyncProfessions(false)
	ns:Send("RecipesChanged")
end)

function R:OnLogin()
	R:SyncProfessions(true)
end

-- /pprof dump ---------------------------------------------------------------------

-- Prints what the client returns for a few unlearned recipes, to work out what Forever offers in
-- place of source text. Only runs while the profession window is open.
function R:Dump(count)
	local TS, api = C_TradeSkillUI, ns.NewCaller()
	if not ns:ViewingOwnProfession(api) then
		ns:Print("open one of your profession windows first.")
		return
	end
	local ids, all = recipeIDs(TS, api)
	ns:Print(string.format("%s: %d recipe IDs (all = %s)", tostring((ns:OpenProfession(api))),
		ids and #ids or 0, tostring(all)))
	if TS.IsAnyRecipeFromSource then
		local found = {}
		for i = 1, 20 do
			if api:Call(TS.IsAnyRecipeFromSource, i) then
				found[#found + 1] = i .. "=" .. tostring(_G["BATTLE_PET_SOURCE_" .. i])
			end
		end
		print("  sources with recipes: " .. (#found > 0 and table.concat(found, ", ") or "none"))
	end
	local shown = 0
	for _, id in ipairs(ids or {}) do
		local info = api:Call(TS.GetRecipeInfo, id)
		if type(info) == "table" and not info.learned then
			local fields = {}
			for k, v in pairs(info) do
				if type(v) ~= "table" then fields[#fields + 1] = k .. "=" .. tostring(v) end
			end
			table.sort(fields)
			local source = api:Call(TS.GetRecipeSourceText, id)
			print(string.format("  %s source=%s", ns.PluvasUI.Color(id .. " " .. tostring(info.name), "gold"), tostring(source)))
			print("    " .. table.concat(fields, " "))
			shown = shown + 1
			if shown >= (count or 3) then break end
		end
	end
end
