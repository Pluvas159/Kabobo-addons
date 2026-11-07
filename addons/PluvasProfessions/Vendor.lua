-- Pluvas' Professions: learns which vendors sell recipes.
--
-- Forever's client has no recipe source data (GetRecipeSourceText returns nil and recipe info
-- has no sourceType), so sources are learned from what the player sees. While a vendor window is
-- open, every recipe item it sells ("Pattern: Red Linen Robe") is stored under the recipe it
-- teaches, shared by all characters: db.vendor[lowercase recipe name] = { v = vendor, z = zone,
-- c = copper, it = item name, lim = limited supply }.
--
-- The merchant API is only called between MERCHANT_SHOW and MERCHANT_CLOSED.
local _, ns = ...
local V = ns:NewModule("Vendor")
local D = ns.Data

local RECIPE_CLASS = 9   -- Enum.ItemClass.Recipe
local BOOK_SUBCLASS = 0  -- Enum.ItemRecipeSubclass.Book: profession books, not single recipes

-- "Pattern: Red Linen Robe" -> "Red Linen Robe". Every recipe item prefixes the name it teaches
-- with a type word and a colon (Pattern, Recipe, Plans, Formula, Schematic, Manual, ...).
function V.RecipeName(itemName)
	if type(itemName) ~= "string" then return nil end
	local name = itemName:match("^[^:]+:%s*(.-)%s*$")
	if not name or name == "" then return nil end
	return name
end

-- Store one recipe item a vendor sells. item = { name, price, extended, available, npc, zone }
function V.Record(item)
	local key = D.Key(V.RecipeName(item.name))
	if not key then return false end
	ns.db.vendor[key] = {
		v = item.npc,
		z = item.zone,
		-- Items bought with tokens or other items have no plain gold price.
		c = (not item.extended and item.price and item.price > 0) and item.price or nil,
		it = item.name,
		lim = (item.available and item.available >= 0) and true or nil,
	}
	return true
end

local open = false

local function itemInfo(i)
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(i)
		if type(info) == "table" then
			return info.name, info.price, info.hasExtendedCost, info.numAvailable
		end
	end
	if GetMerchantItemInfo then
		local name, _, price, _, available, _, _, extended = GetMerchantItemInfo(i)
		return name, price, extended, available
	end
end

local function isRecipeItem(link)
	if not (link and C_Item and C_Item.GetItemInfoInstant) then return false end
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
	return classID == RECIPE_CLASS and subclassID ~= BOOK_SUBCLASS
end

function V:Read()
	if not open or not GetMerchantNumItems then return end
	local npc = UnitName("npc")
	local zone = GetZoneText and GetZoneText() or nil
	local count = 0
	for i = 1, GetMerchantNumItems() or 0 do
		local link = GetMerchantItemLink(i)
		if isRecipeItem(link) then
			local name, price, extended, available = itemInfo(i)
			name = name or (link and link:match("%[(.-)%]"))
			if V.Record({ name = name, price = price, extended = extended, available = available,
				npc = npc, zone = zone }) then
				count = count + 1
			end
		end
	end
	if count > 0 then
		ns:Debug("vendor: recorded", count, "recipes from", tostring(npc))
		ns.UI:Refresh()
	end
end

local pending = false
local guardedRead = ns:Guard("Vendor read", function() V:Read() end)
local function readSoon()
	if pending or not open then return end
	pending = true
	-- Item data can arrive a moment after the window opens; read once it settles.
	C_Timer.After(0.3, function()
		pending = false
		guardedRead()
	end)
end

ns:On("MERCHANT_SHOW", function()
	open = true
	readSoon()
end)
ns:On("MERCHANT_UPDATE", readSoon)
ns:On("MERCHANT_CLOSED", function() open = false end)
