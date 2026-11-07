-- Pluvas' Professions: reads the open profession window.
--
-- On Forever, Blizzard's profession window never lists unlearned recipes: its Camelot code forces
-- C_TradeSkillUI.SetShowUnlearned(false) every time the list is built. The addon does not fight
-- that. It reads every recipe ID of the open profession itself and keeps the unlearned ones, with
-- Blizzard's source text ("Trainer", "Vendor: ...", "Drop: ..."), for its own list.
--
-- C_TradeSkillUI is only called between TRADE_SKILL_SHOW and TRADE_SKILL_CLOSE, and only for the
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

-- This character's professions: name -> { skill, max, line }, and whether any were listed.
-- Reads spellbook skill data only, which is safe at any time.
function R:KnownProfessions()
	local out, any = {}, false
	if not (GetProfessions and GetProfessionInfo) then return out, false end
	for _, index in pairs({ GetProfessions() }) do
		local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
		if name then
			out[name] = { skill = rank, max = maxRank, line = skillLine }
			any = true
		end
	end
	return out, any
end

-- Keep skill levels current and drop professions this character no longer has. Pruning only
-- runs when the client lists at least one profession, so an early call cannot wipe everything.
function R:SyncProfessions(prune)
	local char = D:Char(false)
	if not char then return end
	local known, any = R:KnownProfessions()
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
--   unlearned = { [recipeID] = { n, i, s } }, learned = { [lowercase name] = true }
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

local windowOpen = false
local scanning = false
local failures = 0
local lastScan = {}        -- [professionName] = time() of the last finished read

local function call(fn, ...)
	if not fn then return nil end
	local ok, a = pcall(fn, ...)
	if ok then return a end
	failures = failures + 1
	return nil
end

local function viewingOwnProfession(TS)
	if not TS or not windowOpen then return false end
	if call(TS.IsTradeSkillLinked) or call(TS.IsTradeSkillGuild) or call(TS.IsNPCCrafting) then
		return false
	end
	return true
end

-- Name of the open profession, as GetProfessionInfo spells it, so every source of data uses
-- the same key. Returns name, base info.
local function currentProfession(TS)
	local base = call(TS.GetBaseProfessionInfo)
	if not base or not base.professionID or base.professionID == 0 then return nil end
	local known = R:KnownProfessions()
	for name, k in pairs(known) do
		if name == base.professionName or (k.line and k.line == base.professionID) then
			return name, base
		end
	end
	return base.professionName, base
end

-- All recipe IDs of the open profession. The second value says whether the list includes
-- unlearned recipes for sure: GetFilteredRecipeIDs follows Blizzard's filters, which hide them.
local function recipeIDs(TS)
	local ids = call(TS.GetAllRecipeIDs)
	if type(ids) == "table" and #ids > 0 then return ids, true end
	ids = call(TS.GetFilteredRecipeIDs)
	if type(ids) == "table" then return ids, false end
	return nil, false
end

local function readRecipe(TS, id, unlearned, learned)
	local info = call(TS.GetRecipeInfo, id)
	if type(info) ~= "table" or not info.name or info.isDummyRecipe then return end
	if info.learned then
		local key = D.Key(info.name)
		if key then learned[key] = true end
		return
	end
	local source = call(TS.GetRecipeSourceText, id)
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

-- /pprof dump: prints what the client returns for a few unlearned recipes, to work out what
-- Forever offers in place of source text. Only runs while the profession window is open.
function R:Dump(count)
	local TS = C_TradeSkillUI
	if not viewingOwnProfession(TS) then
		ns:Print("open one of your profession windows first.")
		return
	end
	local ids, all = recipeIDs(TS)
	ns:Print(string.format("%s: %d recipe IDs (all = %s)", tostring((currentProfession(TS))), ids and #ids or 0, tostring(all)))
	if TS.IsAnyRecipeFromSource then
		local found = {}
		for i = 1, 20 do
			if call(TS.IsAnyRecipeFromSource, i) then
				found[#found + 1] = i .. "=" .. tostring(_G["BATTLE_PET_SOURCE_" .. i])
			end
		end
		print("  sources with recipes: " .. (#found > 0 and table.concat(found, ", ") or "none"))
	end
	local shown = 0
	for _, id in ipairs(ids or {}) do
		local info = call(TS.GetRecipeInfo, id)
		if type(info) == "table" and not info.learned then
			local fields = {}
			for k, v in pairs(info) do
				if type(v) ~= "table" then fields[#fields + 1] = k .. "=" .. tostring(v) end
			end
			table.sort(fields)
			local source = call(TS.GetRecipeSourceText, id)
			print(string.format("  |cffffd200%d %s|r source=%s", id, tostring(info.name), tostring(source)))
			print("    " .. table.concat(fields, " "))
			shown = shown + 1
			if shown >= (count or 3) then break end
		end
	end
end

function R:Scan(force)
	local TS = C_TradeSkillUI
	if scanning or not viewingOwnProfession(TS) then return end
	local name, base = currentProfession(TS)
	if not name then return end
	R.current = name
	if not force and lastScan[name] and time() - lastScan[name] < RESCAN_AFTER then return end
	failures = 0
	local ids, all = recipeIDs(TS)
	if not ids then return end

	scanning = true
	local unlearned, learned, i = {}, {}, 1
	local function batch()
		local stop = math.min(i + SCAN_BATCH - 1, #ids)
		for n = i, stop do readRecipe(TS, ids[n], unlearned, learned) end
		i = stop + 1
		return i <= #ids
	end
	local function step()
		-- The window can close between frames; drop the read rather than call the API closed.
		if not windowOpen then scanning = false; return end
		local ok, more = pcall(batch)
		if not ok then
			scanning = false
			geterrorhandler()("Recipe scan: " .. tostring(more))
		elseif more then
			C_Timer.After(0, step)
		else
			R.Store(name, base, unlearned, learned, all and failures == 0)
			lastScan[name] = time()
			scanning = false
			ns:Debug("recipes:", name, #ids, "recipes read,", failures, "failed calls, all =", tostring(all))
			ns.UI:Refresh()
		end
	end
	step()
end

local pending, pendingForce = false, false
local guardedScan = ns:Guard("Recipe scan", function(force) R:Scan(force) end)
local function scanSoon(force)
	pendingForce = pendingForce or force == true
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		local f = pendingForce
		pending, pendingForce = false, false
		guardedScan(f)
	end)
end

ns:On("TRADE_SKILL_SHOW", function()
	windowOpen = true
	scanSoon(true)
end)
-- Fires when the list changes, including switching to another profession in the window.
ns:On("TRADE_SKILL_LIST_UPDATE", function() scanSoon(false) end)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() scanSoon(true) end)
ns:On("TRADE_SKILL_CLOSE", function()
	windowOpen = false
	R.current = nil
	ns.UI:Refresh()
end)

-- Learned from a trainer, a recipe item or anywhere else: take it off the list straight away.
ns:On("NEW_RECIPE_LEARNED", function(recipeID)
	local name
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, recipeID)
		if ok then name = n end
	end
	D:Forget(recipeID, name)
	ns.UI:Refresh()
end)

ns:On("SKILL_LINES_CHANGED", function()
	R:SyncProfessions(false)
	ns.UI:Refresh()
end)

function R:OnLogin()
	R:SyncProfessions(true)
end
