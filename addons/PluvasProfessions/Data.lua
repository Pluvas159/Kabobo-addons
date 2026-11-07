-- Pluvas' Professions: saved data and the pure logic behind the unlearned list.
-- Nothing in this file calls a profession or trainer API, so all of it can be tested.
--
-- Per character, per profession (db.chars[charKey][professionName]):
--   id    = professionID, skill = current skill, max = max skill, scanned = time()
--   u     = { [recipeID] = { n = name, i = icon, s = source text, g = grey at skill, t = source type } }
--           unlearned recipes, read from the profession window. On Forever s and t are always nil.
--   tu    = { [lowercase name] = true }
--           trainer recipes this character had not learned when it last saw a trainer for them.
--           They fill the list when the profession window does not list unlearned recipes.
local _, ns = ...
local D = ns:NewModule("Data")

local floor = math.floor

-- Text helpers --------------------------------------------------------------

-- Lowercase, trimmed name used to match recipes against trainer services.
function D.Key(name)
	if type(name) ~= "string" then return nil end
	name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil end
	return name
end

-- Removes color codes and textures, and turns |n into real line breaks.
function D.StripCodes(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|n", "\n")
	return text
end

-- Blizzard source text looks like "|cFFFFD200Vendor: |rSome Vendor|n|cFFFFD200Zone: |rStormwind".
-- Returns the label of the first source ("Vendor") and the whole text without color codes.
function D.ParseSource(text)
	local plain = D.StripCodes(text)
	if not plain then return nil, nil end
	plain = plain:gsub("^%s+", ""):gsub("%s+$", "")
	if plain == "" then return nil, nil end
	local first = plain:match("^([^\n]*)")
	local label = first:match("^(.-)%s*:") or first
	label = label:gsub("^%s+", ""):gsub("%s+$", "")
	if label == "" then label = nil end
	return label, plain
end

-- Source groups, in list order. Matching is on English words; other labels keep their own text
-- and sort after these.
local GROUPS = {
	{ key = "trainer", word = "trainer", text = "Trainer" },
	{ key = "vendor", word = "vendor", text = "Vendor" },
	{ key = "quest", word = "quest", text = "Quest" },
	{ key = "drop", word = "drop", text = "Drop" },
	{ key = "discovery", word = "discover", text = "Discovery" },
}
local OTHER_ORDER = #GROUPS + 1
local UNKNOWN_ORDER = OTHER_ORDER + 1

-- Returns groupKey, order, display text for a source label (nil label = unknown source).
function D.SourceGroup(label)
	if not label then return "unknown", UNKNOWN_ORDER, "No source info" end
	local lower = label:lower()
	for i, g in ipairs(GROUPS) do
		if lower:find(g.word, 1, true) then return g.key, i, g.text end
	end
	return "other:" .. lower, OTHER_ORDER, label
end

-- Money ---------------------------------------------------------------------

local COINS = { "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r" }

-- Colored "1g 2s 3c". Zero parts are left out.
function D.Money(copper)
	copper = floor((copper or 0) + 0.5)
	local g, s, c = floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. COINS[1] end
	if s > 0 then parts[#parts + 1] = s .. COINS[2] end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COINS[3] end
	return table.concat(parts, " ")
end

-- Saved data ----------------------------------------------------------------

-- This character's professions table, or nil before login.
function D:Char(create)
	if not ns.charKey or not ns.db then return nil end
	local chars = ns.db.chars
	if not chars[ns.charKey] and create then chars[ns.charKey] = {} end
	return chars[ns.charKey]
end

function D:Prof(name, create)
	if not name then return nil end
	local char = D:Char(create)
	if not char then return nil end
	local p = char[name]
	if not p and create then
		p = { u = {}, tu = {} }
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
	local t = ns.db.trainer[name]
	if not t and create then
		t = {}
		ns.db.trainer[name] = t
	end
	return t
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

-- A recipe was learned: drop it from every unlearned list of this character.
function D:Forget(recipeID, name)
	local char = D:Char(false)
	if not char then return end
	local key = D.Key(name)
	for _, p in pairs(char) do
		if p.u then
			local r = recipeID and p.u[recipeID]
			if r then
				key = key or D.Key(r.n)
				p.u[recipeID] = nil
			end
			if key then
				for id, rec in pairs(p.u) do
					if D.Key(rec.n) == key then p.u[id] = nil end
				end
			end
		end
		if key and p.tu then p.tu[key] = nil end
	end
end

-- Building the list -----------------------------------------------------------

local function byName(a, b)
	if a.name ~= b.name then return (a.name or "") < (b.name or "") end
	return (a.id or 0) < (b.id or 0)
end

local function bySkill(a, b)
	local sa = a.trainer and a.trainer.s or 0
	local sb = b.trainer and b.trainer.s or 0
	if sa ~= sb then return sa < sb end
	return byName(a, b)
end

-- By the skill where the recipe turns grey (lowest first, unknown last), then name. Forever gives
-- no "skill to learn" for recipes, and the grey level is the closest thing it offers.
local function byGrey(a, b)
	local ga, gb = a.grey or math.huge, b.grey or math.huge
	if ga ~= gb then return ga < gb end
	return byName(a, b)
end

-- Saved recipes in a stable order: ones with source text first, then by ID. Recipes can exist
-- once per faction under the same name; only the first of a name is shown.
local function sortedIDs(u)
	local ids = {}
	for id in pairs(u) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b)
		local sa, sb = u[a].s ~= nil, u[b].s ~= nil
		if sa ~= sb then return sa end
		return a < b
	end)
	return ids
end

-- Turns a profession entry into display rows.
--   prof    = profession entry (see top of file)
--   catalog = trainer catalog for the profession, or nil
--   opts    = { level = player level, hideUnknown = bool, collapsed = { [groupKey] = true },
--               vendors = vendor catalog (db.vendor) }
-- Returns rows, summary. Rows are { header = true, key, text, count, collapsed } or entries
-- { id, name, icon, label, source, trainer, vendor, grey, group, learnable }.
-- learnable is true (can learn now), false (needs more skill or level) or nil (not a trainer
-- recipe). summary = { total, learnable }.
function D.BuildRows(prof, catalog, opts)
	opts = opts or {}
	catalog = catalog or {}
	local vendors = opts.vendors or {}
	local skill = prof and prof.skill or 0
	local level = opts.level or 0
	local entries, seen = {}, {}

	local function add(e)
		local key, order, text = D.SourceGroup(e.label)
		-- No source text, but a trainer or vendor was seen with it: that is its source.
		if key == "unknown" and e.trainer then
			key, order, text = D.SourceGroup("Trainer")
		elseif key == "unknown" and e.vendor then
			key, order, text = D.SourceGroup("Vendor")
		end
		e.group, e.order, e.groupText = key, order, text
		if e.trainer and key == "trainer" then
			e.learnable = skill >= (e.trainer.s or 0) and level >= (e.trainer.lv or 0)
		end
		if not (opts.hideUnknown and key == "unknown") then
			entries[#entries + 1] = e
		end
	end

	if prof then
		local u = prof.u or {}
		for _, id in ipairs(sortedIDs(u)) do
			local r = u[id]
			local key = D.Key(r.n)
			if not (key and seen[key]) then
				if key then seen[key] = true end
				local label, plain = D.ParseSource(r.s)
				add({ id = id, name = r.n, icon = r.i, label = label, source = plain, grey = r.g,
					trainer = key and catalog[key], vendor = key and vendors[key] })
			end
		end
		for key in pairs(prof.tu or {}) do
			local t = catalog[key]
			if t and not seen[key] then
				seen[key] = true
				add({ name = t.n or key, icon = t.ic, label = "Trainer", trainer = t, vendor = vendors[key] })
			end
		end
	end

	-- Group, then order inside each group: trainer recipes by required skill, the rest by the
	-- skill where they turn grey.
	local groups, order = {}, {}
	for _, e in ipairs(entries) do
		local g = groups[e.group]
		if not g then
			g = { key = e.group, order = e.order, text = e.groupText, list = {} }
			groups[e.group] = g
			order[#order + 1] = g
		end
		g.list[#g.list + 1] = e
	end
	table.sort(order, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.text < b.text
	end)

	local collapsed = opts.collapsed or {}
	local rows, summary = {}, { total = #entries, learnable = 0 }
	for _, g in ipairs(order) do
		table.sort(g.list, g.key == "trainer" and bySkill or byGrey)
		local closed = collapsed[g.key] == true
		rows[#rows + 1] = { header = true, key = g.key, text = g.text, count = #g.list, collapsed = closed }
		for _, e in ipairs(g.list) do
			if not closed then rows[#rows + 1] = e end
			if e.learnable then summary.learnable = summary.learnable + 1 end
		end
	end
	return rows, summary
end
