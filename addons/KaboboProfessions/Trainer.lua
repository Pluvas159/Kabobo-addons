-- Kabobo's Professions: reads what profession trainers teach.
--
-- The trainer API is only called while the trainer session is open. Every recipe a trainer
-- lists is added to the shared catalog (skill, level, cost, who teaches it), and the ones this
-- character has not learned are remembered, so the unlearned list works even when the
-- profession window does not list unlearned recipes.
--
-- The client only lists services the trainer filter lets through, so with the
-- trainerUnavailable setting on, the "available" and "unavailable" filters are switched on when
-- a profession trainer opens. That is the same call Blizzard's own filter menu makes.
local _, ns = ...
local T = ns:NewModule("Trainer")
local D = ns.Data

local KINDS = { available = true, unavailable = true, used = true, header = true }

local trainer = ns:Session("TRAINER_SHOW", "TRAINER_CLOSED")

-- Forever returns name, serviceType, texture, reqLevel, subText, category. Older clients (and
-- the wiki) have name, rank, category, expanded. Accept both: find the service type by value.
-- Returns name, kind, icon, reqLevel.
function T.ParseServiceInfo(...)
	local name, second, third, fourth = ...
	if KINDS[second] then
		return name, second, third, type(fourth) == "number" and fourth or nil
	elseif KINDS[third] then
		return name, third, nil, nil
	end
	return name, nil, nil, nil
end

-- 0/1 on old clients, booleans on the modern one.
local function isOn(v) return v == true or (type(v) == "number" and v ~= 0) end

local function isProfessionTrainer()
	return IsTradeskillTrainer and IsTradeskillTrainer() and true or false
end

function T:ApplyFilter()
	if not ns.db.settings.trainerUnavailable then return end
	if not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return end
	for _, kind in ipairs({ "available", "unavailable" }) do
		if not isOn(GetTrainerServiceTypeFilter(kind)) then
			SetTrainerServiceTypeFilter(kind, true)
		end
	end
end

-- Store one service. known = this character's professions (name -> info).
function T.Record(service, known)
	local key = D.Key(service.name)
	if not key or not service.prof then return end
	local catalog = D:Catalog(service.prof, true)
	local old = catalog[key] or {}
	catalog[key] = {
		n = service.name,
		s = service.skill or old.s,
		lv = (service.level and service.level > 1) and service.level or nil,
		c = (service.cost and service.cost > 0) and service.cost or nil,
		ic = service.icon or old.ic,
		w = service.npc or old.w,
		z = service.zone or old.z,
	}
	-- Only characters that have the profession get a list for it.
	if not known[service.prof] then return end
	local p = D:Prof(service.prof, true)
	if service.kind == "used" then
		D.Drop(p, nil, key)
	else
		p.tu[key] = true
	end
end

-- The profession a service belongs to.
local function serviceProfession(i)
	local prof = GetTrainerServiceSkillReq(i)
	if (not prof or prof == "") and GetTrainerServiceSkillLine then prof = GetTrainerServiceSkillLine(i) end
	if prof and prof ~= "" then return prof end
	return nil
end

function T:Read()
	if not trainer.open or not isProfessionTrainer() then return end
	local n = GetNumTrainerServices and GetNumTrainerServices() or 0
	if n == 0 then return end
	local known = ns:KnownProfessions()
	local npc = UnitName("npc")
	local zone = GetZoneText and GetZoneText() or nil
	local count = 0
	for i = 1, n do
		local name, kind, icon, level = T.ParseServiceInfo(GetTrainerServiceInfo(i))
		local prof = name and kind and kind ~= "header" and serviceProfession(i)
		if prof then
			local _, skill = GetTrainerServiceSkillReq(i)
			T.Record({
				name = name, kind = kind, icon = icon, level = level, prof = prof, skill = skill,
				cost = (GetTrainerServiceCost(i)), npc = npc, zone = zone,
			}, known)
			count = count + 1
		end
	end
	ns:Debug("trainer: recorded", count, "services")
	ns:Send("RecipesChanged")
end

-- The list updates several times while it fills; read once it settles.
local readSoon = ns:Debounce("Trainer read", 0.2, function() T:Read() end)

ns:On("TRAINER_SHOW", function()
	if not isProfessionTrainer() then return end
	T:ApplyFilter()
	readSoon()
end)
ns:On("TRAINER_UPDATE", function()
	if trainer.open then readSoon() end
end)
