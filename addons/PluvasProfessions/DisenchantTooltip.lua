-- Pluvas' Professions: "worth disenchanting?" lines in the tooltip of every disenchantable item.
--
-- Prices come from Pluvas' Auctions (ns:Peer("PluvasAuctions")). Without it there is nothing to
-- compare, so the lines stay off. The hook reads only plain item info, the saved prices of Pluvas'
-- Auctions and spellbook skills, which are all safe in a tooltip.
local _, ns = ...
local DT = ns:NewModule("DisenchantTooltip")
local DE = ns.Disenchant
local PUI = ns.PluvasUI
local Money = PUI.MoneyIcons
local floor = math.floor

DT.PEER = "PluvasAuctions"

local function muted(text) return PUI.Color(text, "muted") end

-- Whether this character has Enchanting, read again after skill changes. Forever lets any
-- Enchanting skill disenchant any item, so the skill level does not matter.
local enchanter, stale = false, true
local function hasEnchanting()
	if stale then
		enchanter = false
		local profs, any = ns:KnownProfessions()
		for name, p in pairs(profs) do
			if p.line == DE.ENCHANTING_LINE or name == "Enchanting" then enchanter = true end
		end
		-- Early in a login the spellbook lists nothing yet: ask again next time.
		stale = not any
	end
	return enchanter
end
ns:On("SKILL_LINES_CHANGED", function() stale = true end)

local function itemName(id)
	local name = ns.Try(C_Item and C_Item.GetItemInfo, id)
	return name or DE.NAMES[id] or ("item:" .. id)
end

-- " (5d old)" in the warning color when Pluvas' Auctions counts a price last seen at `seen` as
-- old, else "". Older versions of Pluvas' Auctions have no StaleAge: nothing is flagged then.
local function oldNote(auctions, seen, now)
	local age = type(seen) == "number" and auctions.StaleAge and auctions.StaleAge(seen, now)
	if not age then return "" end
	return PUI.Color(" (" .. PUI.Age(age) .. " old)", "warn")
end

-- "75%", "0.5%"
local function percent(chance)
	return string.format("%g%%", floor(chance * 1000 + 0.5) / 10)
end

-- "1-2x " or "3x "; nothing for exactly one.
local function amount(o)
	if o.min == o.max then return o.min == 1 and "" or (o.min .. "x ") end
	return o.min .. "-" .. o.max .. "x "
end

-- What disenchanting an item (link or itemID) may give (see DE.Outcomes), and what a vendor
-- pays for it. nil when it cannot be disenchanted or the client has not loaded it yet. Plain
-- item info only, so safe anywhere.
function DT.ItemOutcomes(item)
	if not (item and C_Item and C_Item.GetItemInfo) then return nil end
	local ok, _, _, quality, level, _, _, _, _, equipLoc, _, sellPrice, classID = pcall(C_Item.GetItemInfo, item)
	if not ok or not DE.Disenchantable(classID, quality, equipLoc) then return nil end
	local outcomes = DE.Outcomes(quality, level, classID == DE.WEAPON)
	if not outcomes then return nil end
	return outcomes, type(sellPrice) == "number" and sellPrice or 0
end

-- The tooltip lines for an item (link or itemID), or nil when it cannot be disenchanted.
-- auctions is the Pluvas' Auctions API; enchanter says whether this character has Enchanting;
-- showMats lists every possible result; now (default time()) dates the prices, so old ones are
-- flagged.
function DT.Lines(item, auctions, enchanter, showMats, now)
	local outcomes, sellPrice = DT.ItemOutcomes(item)
	if not outcomes then return nil end
	now = now or time()

	-- Both sides after the AH cut, so they compare fairly. Mats go up in stacks, so their
	-- deposits are left out; the item itself pays one.
	local gross, missing, matsSeen = DE.Value(outcomes, auctions.Price)
	local value = auctions.Proceeds(gross, 0)
	local sell, where, sellSeen = nil, nil, nil
	if sellPrice > 0 then sell, where = sellPrice, "vendor" end
	local ah, ahSeen = auctions.Price(item)
	if ah then
		local net = auctions.Proceeds(ah, 1)
		if net > (sell or 0) then sell, where, sellSeen = net, "AH", ahSeen end
	end
	local matsOld, sellOld = oldNote(auctions, matsSeen, now), oldNote(auctions, sellSeen, now)

	local verdict = DE.Verdict(value, missing, sell)
	local head
	if verdict == "yes" then
		head = PUI.Color("worth it", "good")
	elseif verdict == "no" then
		head = PUI.Color("not worth it", "bad")
	else
		head = muted("no AH prices for its mats yet")
	end
	-- A verdict built on old prices may no longer hold.
	if verdict ~= "unknown" and (matsOld ~= "" or sellOld ~= "") then
		head = head .. PUI.Color(" (old prices)", "warn")
	end

	local out = { { "Disenchant", head } }
	if gross > 0 then
		local note = missing > 0 and muted(" (" .. missing .. " unpriced)") or ""
		out[#out + 1] = { "   expected mats", Money(value) .. note .. matsOld, color = "soft" }
	end
	if sell then
		out[#out + 1] = { "   selling instead", Money(sell) .. muted(" " .. where) .. sellOld, color = "soft" }
	end
	if showMats then
		for _, o in ipairs(outcomes) do
			local unit, seen = auctions.Price(o.id)
			out[#out + 1] = {
				"   " .. percent(o.chance) .. " " .. amount(o) .. itemName(o.id),
				unit and (Money(floor(unit * DE.Average(o) + 0.5)) .. oldNote(auctions, seen, now)) or muted("no price"),
				color = "soft",
			}
		end
	end
	if not enchanter then out[#out + 1] = { "   needs Enchanting", " ", color = "muted" } end
	return out
end

function DT:OnLogin()
	ns:OnItemTooltip("Disenchant tooltip", function(tooltip, link, id)
		local s = ns.db.settings
		if not s.disenchant then return end
		-- Asked on every hover: Pluvas' Auctions may load after this addon.
		local auctions = ns:Peer(DT.PEER)
		if not auctions then return end
		local lines = DT.Lines(link or id, auctions, hasEnchanting(), s.disenchantMats)
		if lines then PUI.AddTooltipLines(tooltip, lines) end
	end)
end

-- Whether the lines can show at all, for /pprof help and the toggle message.
function DT.Available()
	return ns:Peer(DT.PEER) ~= nil
end
