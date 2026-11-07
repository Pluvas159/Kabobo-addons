-- Kabobo's Professions: turns saved recipe data into the rows of the unlearned list.
-- Pure: takes tables, returns tables, reads no game state, so all of it is unit tested.
local _, ns = ...
local Rows = ns:NewModule("Rows")
local Key = ns.Data.Key

-- Source text ---------------------------------------------------------------------

-- Removes color codes and textures, and turns |n into real line breaks.
function Rows.StripCodes(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	text = text:gsub("|n", "\n")
	return text
end

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Blizzard source text looks like "|cFFFFD200Vendor: |rSome Vendor|n|cFFFFD200Zone: |rStormwind".
-- Returns the label of the first source ("Vendor") and the whole text without color codes.
function Rows.ParseSource(text)
	local plain = Rows.StripCodes(text)
	if not plain then return nil, nil end
	plain = trim(plain)
	if plain == "" then return nil, nil end
	local first = plain:match("^([^\n]*)")
	local label = trim(first:match("^(.-)%s*:") or first)
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
function Rows.SourceGroup(label)
	if not label then return "unknown", UNKNOWN_ORDER, "No source info" end
	local lower = label:lower()
	for i, g in ipairs(GROUPS) do
		if lower:find(g.word, 1, true) then return g.key, i, g.text end
	end
	return "other:" .. lower, OTHER_ORDER, label
end

-- Sorting -------------------------------------------------------------------------

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

-- Building the list ---------------------------------------------------------------

-- Every unlearned recipe of a profession as an entry, once per name.
local function collect(prof, catalog, vendors)
	local entries, seen = {}, {}
	if not prof then return entries end
	local u = prof.u or {}
	for _, id in ipairs(sortedIDs(u)) do
		local r = u[id]
		local key = Key(r.n)
		if not (key and seen[key]) then
			if key then seen[key] = true end
			local label, plain = Rows.ParseSource(r.s)
			entries[#entries + 1] = { id = id, name = r.n, icon = r.i, label = label, source = plain,
				grey = r.g, trainer = key and catalog[key], vendor = key and vendors[key] }
		end
	end
	for key in pairs(prof.tu or {}) do
		local t = catalog[key]
		if t and not seen[key] then
			seen[key] = true
			entries[#entries + 1] = { name = t.n or key, icon = t.ic, label = "Trainer", trainer = t,
				vendor = vendors[key] }
		end
	end
	return entries
end

-- Puts an entry in its source group. No source text, but a trainer or vendor was seen with it:
-- that is its source.
local function classify(e, skill, level)
	local label = e.label
	if not label and e.trainer then
		label = "Trainer"
	elseif not label and e.vendor then
		label = "Vendor"
	end
	e.group, e.order, e.groupText = Rows.SourceGroup(label)
	if e.trainer and e.group == "trainer" then
		e.learnable = skill >= (e.trainer.s or 0) and level >= (e.trainer.lv or 0)
	end
end

-- Turns a profession entry into display rows.
--   prof    = profession entry (see Data.lua)
--   catalog = trainer catalog for the profession, or nil
--   opts    = { level = player level, hideUnknown = bool, collapsed = { [groupKey] = true },
--               vendors = vendor catalog (db.vendor) }
-- Returns rows, summary. Rows are { header = true, key, text, count, collapsed } or entries
-- { id, name, icon, label, source, trainer, vendor, grey, group, learnable }.
-- learnable is true (can learn now), false (needs more skill or level) or nil (not a trainer
-- recipe). summary = { total, learnable }.
function Rows.Build(prof, catalog, opts)
	opts = opts or {}
	local skill, level = prof and prof.skill or 0, opts.level or 0

	-- Group, then order inside each group: trainer recipes by required skill, the rest by the
	-- skill where they turn grey.
	local groups, order, total = {}, {}, 0
	for _, e in ipairs(collect(prof, catalog or {}, opts.vendors or {})) do
		classify(e, skill, level)
		if not (opts.hideUnknown and e.group == "unknown") then
			total = total + 1
			local g = groups[e.group]
			if not g then
				g = { key = e.group, order = e.order, text = e.groupText, list = {} }
				groups[e.group] = g
				order[#order + 1] = g
			end
			g.list[#g.list + 1] = e
		end
	end
	table.sort(order, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.text < b.text
	end)

	local collapsed = opts.collapsed or {}
	local rows, summary = {}, { total = total, learnable = 0 }
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
