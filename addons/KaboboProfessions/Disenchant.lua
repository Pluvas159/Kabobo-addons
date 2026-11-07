-- Kabobo's Professions: what disenchanting an item gives, and whether that beats selling it.
--
-- Pure: nothing here calls a game API. The outcome tables are Classic's (disenchanting by item
-- level, quality and weapon or armor), which Forever guides list unchanged. They are rules, not
-- a list of items, so items new in Forever are covered as long as they have a normal item level
-- and quality. Not yet checked against real disenchants, so the tooltip calls its numbers
-- expected values. Forever dropped Classic's skill requirement: any Enchanter can disenchant
-- any item (from a Forever guide, not checked in game).
local _, ns = ...
local DE = ns:NewModule("Disenchant")

local floor = math.floor

DE.ENCHANTING_LINE = 333   -- skill line of Enchanting, from GetProfessionInfo
DE.WEAPON, DE.ARMOR = 2, 4 -- Enum.ItemClass.Weapon / Armor
local UNCOMMON, RARE, EPIC = 2, 3, 4
local TOP = 1000           -- the last band of each table covers every higher item level

-- Item names for while the client has not cached the mats yet.
DE.NAMES = {
	[10940] = "Strange Dust", [11083] = "Soul Dust", [11137] = "Vision Dust",
	[11176] = "Dream Dust", [16204] = "Illusion Dust",
	[10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence",
	[10998] = "Lesser Astral Essence", [11082] = "Greater Astral Essence",
	[11134] = "Lesser Mystic Essence", [11135] = "Greater Mystic Essence",
	[11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence",
	[16202] = "Lesser Eternal Essence", [16203] = "Greater Eternal Essence",
	[10978] = "Small Glimmering Shard", [11084] = "Large Glimmering Shard",
	[11138] = "Small Glowing Shard", [11139] = "Large Glowing Shard",
	[11177] = "Small Radiant Shard", [11178] = "Large Radiant Shard",
	[14343] = "Small Brilliant Shard", [14344] = "Large Brilliant Shard",
	[20725] = "Nexus Crystal",
}

-- Uncommon items: dust, essence or (rarely) a shard. These chances are for armor; weapons swap
-- the dust and essence chances.
local UNCOMMON_BANDS = {
	{ to = 15, dust = { 10940, 1, 2 }, ess = { 10938, 1, 2 }, essP = 0.20 },
	{ to = 20, dust = { 10940, 2, 3 }, ess = { 10939, 1, 2 }, essP = 0.20, shard = 10978, shardP = 0.05 },
	{ to = 25, dust = { 10940, 4, 6 }, ess = { 10998, 1, 2 }, essP = 0.15, shard = 10978, shardP = 0.10 },
	{ to = 30, dust = { 11083, 1, 2 }, ess = { 11082, 1, 2 }, essP = 0.20, shard = 11084, shardP = 0.05 },
	{ to = 35, dust = { 11083, 2, 5 }, ess = { 11134, 1, 2 }, essP = 0.20, shard = 11138, shardP = 0.05 },
	{ to = 40, dust = { 11137, 1, 2 }, ess = { 11135, 1, 2 }, essP = 0.20, shard = 11139, shardP = 0.05 },
	{ to = 45, dust = { 11137, 2, 5 }, ess = { 11174, 1, 2 }, essP = 0.20, shard = 11177, shardP = 0.05 },
	{ to = 50, dust = { 11176, 1, 2 }, ess = { 11175, 1, 2 }, essP = 0.20, shard = 11178, shardP = 0.05 },
	{ to = 55, dust = { 11176, 2, 5 }, ess = { 16202, 1, 2 }, essP = 0.20, shard = 14343, shardP = 0.05 },
	{ to = 60, dust = { 16204, 1, 2 }, ess = { 16203, 1, 2 }, essP = 0.20, shard = 14344, shardP = 0.05 },
	{ to = TOP, dust = { 16204, 2, 5 }, ess = { 16203, 2, 3 }, essP = 0.20, shard = 14344, shardP = 0.05 },
}

-- Rare items: one shard, and from item level 56 a small chance of a Nexus Crystal instead.
local RARE_BANDS = {
	{ to = 25, shard = 10978 }, { to = 30, shard = 11084 },
	{ to = 35, shard = 11138 }, { to = 40, shard = 11139 },
	{ to = 45, shard = 11177 }, { to = 50, shard = 11178 },
	{ to = 55, shard = 14343 }, { to = TOP, shard = 14344, nexusP = 0.005 },
}

-- Epic items: several shards, or Nexus Crystals from item level 56.
local EPIC_BANDS = {
	{ to = 45, mat = { 11177, 2, 4 } }, { to = 50, mat = { 11178, 2, 4 } },
	{ to = 55, mat = { 14343, 2, 4 } }, { to = 60, mat = { 20725, 1, 1 } },
	{ to = TOP, mat = { 20725, 1, 2 } },
}

local function band(bands, level)
	for i = 1, #bands do
		if level <= bands[i].to then return i, bands[i] end
	end
end

local function outcome(id, chance, lo, hi)
	return { id = id, chance = chance, min = lo or 1, max = hi or lo or 1 }
end

local function build(quality, b, weapon)
	local out = {}
	if quality == UNCOMMON then
		local shardP = b.shardP or 0
		local dustP, essP = 1 - b.essP - shardP, b.essP
		if weapon then dustP, essP = essP, dustP end
		out[#out + 1] = outcome(b.dust[1], dustP, b.dust[2], b.dust[3])
		out[#out + 1] = outcome(b.ess[1], essP, b.ess[2], b.ess[3])
		if b.shard then out[#out + 1] = outcome(b.shard, shardP) end
	elseif quality == RARE then
		local nexusP = b.nexusP or 0
		out[#out + 1] = outcome(b.shard, 1 - nexusP)
		if nexusP > 0 then out[#out + 1] = outcome(20725, nexusP) end
	else
		out[#out + 1] = outcome(b.mat[1], 1, b.mat[2], b.mat[3])
	end
	-- Likeliest first, which is also how the tooltip lists them.
	table.sort(out, function(x, y) return x.chance > y.chance end)
	return out
end

-- Whether an item can be disenchanted, from its GetItemInfo fields: uncommon to epic weapons
-- and armor that can be worn. Shirts and tabards cannot.
function DE.Disenchantable(classID, quality, equipLoc)
	if classID ~= DE.WEAPON and classID ~= DE.ARMOR then return false end
	if type(quality) ~= "number" or quality < UNCOMMON or quality > EPIC then return false end
	if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then
		return false
	end
	return true
end

-- What disenchanting one item may give: a list of { id, chance, min, max }, likeliest first.
-- nil for qualities that cannot be disenchanted. The lists are shared: do not change them.
local cache = {}
function DE.Outcomes(quality, level, weapon)
	local bands = (quality == UNCOMMON and UNCOMMON_BANDS) or (quality == RARE and RARE_BANDS)
		or (quality == EPIC and EPIC_BANDS)
	if not bands or type(level) ~= "number" then return nil end
	local i, b = band(bands, level)
	if not i then return nil end
	-- Only uncommon items care about weapon or armor.
	local key = quality .. ":" .. i .. ((quality == UNCOMMON and weapon) and "w" or "")
	if not cache[key] then cache[key] = build(quality, b, weapon) end
	return cache[key]
end

-- Average amount of one outcome.
function DE.Average(o)
	return (o.min + o.max) / 2
end

-- Expected AH value of disenchanting one item: sum of chance x average amount x unit price,
-- with price(itemID) giving a unit price or nil, and optionally when that price was last seen.
-- Returns copper (before the AH cut), how many outcomes had no price, and when the oldest price
-- used was last seen (nil when price gives no times).
function DE.Value(outcomes, price)
	local sum, missing, oldest = 0, 0, nil
	for _, o in ipairs(outcomes) do
		local unit, seen = price(o.id)
		if unit then
			sum = sum + o.chance * DE.Average(o) * unit
			if type(seen) == "number" and (not oldest or seen < oldest) then oldest = seen end
		else
			missing = missing + 1
		end
	end
	return floor(sum + 0.5), missing, oldest
end

-- "yes" when disenchanting is worth more than selling (sell = the best of AH and vendor, nil
-- when it sells for nothing), "no" when it is not, "unknown" when unpriced mats leave it open.
function DE.Verdict(value, missing, sell)
	sell = sell or 0
	if value > sell then return "yes" end
	if missing > 0 then return "unknown" end
	return "no"
end
