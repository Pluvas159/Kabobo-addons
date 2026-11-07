-- Kabobo's Professions: the saved recipe data. Nothing here calls a game API.
--
-- Per character, per profession (db.chars[charKey][professionName]):
--   id    = professionID, skill = current skill, max = max skill, scanned = time()
--   u     = { [recipeID] = { n = name, i = icon, s = source text, g = grey at skill, t = source type } }
--           unlearned recipes, read from the profession window. On Forever s and t are always nil.
--   tu    = { [lowercase name] = true }
--           trainer recipes this character had not learned when it last saw a trainer for them.
--           They fill the list when the profession window does not list unlearned recipes.
-- Shared by every character:
--   db.trainer[professionName][lowercase name] = { n, s = skill, lv = level, c = copper,
--     ic = icon, w = trainer, z = zone }                                         (Trainer.lua)
--   db.vendor[lowercase name] = { v = vendor, z = zone, c = copper, it = item name,
--     lim = limited supply }                                                     (Vendor.lua)
--
-- Every change sends the addon message RecipesChanged, which the panel listens to.
local _, ns = ...
local D = ns:NewModule("Data")

-- Lowercase, trimmed name: recipes are matched by name across the profession window, trainers
-- and vendors (the same recipe can exist under several IDs, one per faction).
function D.Key(name)
	if type(name) ~= "string" then return nil end
	name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil end
	return name
end

-- This character's professions table, or nil before login.
function D:Char(create)
	if not ns.charKey or not ns.db then return nil end
	local chars = ns.db.chars
	if not chars[ns.charKey] and create then chars[ns.charKey] = {} end
	return chars[ns.charKey]
end

-- One profession of this character, or nil. create = true makes it.
function D:Prof(name, create)
	if not name then return nil end
	local char = D:Char(create)
	if not char then return nil end
	local p = char[name]
	if not p and create then
		p = {}
		char[name] = p
	end
	if p then
		p.u = p.u or {}
		p.tu = p.tu or {}
	end
	return p
end

-- Trainer catalog for a profession (shared by all characters).
function D:Catalog(name, create)
	if not name or not ns.db then return nil end
	if create then return ns.Ensure(ns.db.trainer, name) end
	return ns.db.trainer[name]
end

-- Professions this character has data for, sorted by name.
function D:ProfNames()
	local char, names = D:Char(false), {}
	if char then
		for name in pairs(char) do names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

-- Removes a recipe from every unlearned list of this character, by ID and by name.
local function drop(p, recipeID, key)
	local r = recipeID and p.u[recipeID]
	if r then
		key = key or D.Key(r.n)
		p.u[recipeID] = nil
	end
	if key then
		for id, rec in pairs(p.u) do
			if D.Key(rec.n) == key then p.u[id] = nil end
		end
		p.tu[key] = nil
	end
	return key
end
D.Drop = drop

-- A recipe was learned: drop it from every unlearned list of this character.
function D:Forget(recipeID, name)
	local char = D:Char(false)
	if not char then return end
	local key = D.Key(name)
	for profName in pairs(char) do
		key = drop(D:Prof(profName), recipeID, key)
	end
	ns:Send("RecipesChanged")
end

function D:ResetChar()
	ns.db.chars[ns.charKey] = nil
	ns:Print("recipe data for " .. ns.charKey .. " deleted. Open your profession windows to read it again.")
	ns:Send("RecipesChanged")
end
