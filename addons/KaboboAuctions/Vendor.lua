-- Kabobo's Auctions: what vendors charge for the items they sell, so mats like thread, dyes and
-- vials get a price even though nobody lists them on the AH.
--
-- The client only gives vendor buy prices while a vendor window is open, so they are learned:
-- every item a vendor sells for plain gold and in unlimited supply is stored as copper per unit,
-- shared by all characters since vendor prices do not depend on realm or faction:
-- db.vendor[itemID] = copper. Reputation discounts can make a price differ a little between
-- characters; the last price seen wins.
--
-- The merchant API is only called while the merchant session is open.
local _, ns = ...
local V = ns:NewModule("Vendor")

local merchant = ns:Session("MERCHANT_SHOW", "MERCHANT_CLOSED")

-- Copper per unit for one merchant item (see ns.MerchantItems), or nil when it cannot simply be
-- bought for gold whenever you need it.
function V.UnitPrice(item)
	if not item.id or item.extended then return nil end   -- also costs tokens or items
	if item.available and item.available >= 0 then return nil end   -- limited supply
	if not item.price or item.price <= 0 then return nil end
	local qty = item.quantity or 1
	if qty < 1 then qty = 1 end
	return item.price / qty
end

-- Vendor price per unit of an item, or nil. Read-only, for tooltips and other hot paths.
function V:Get(itemID)
	return itemID and ns.db.vendor[itemID] or nil
end

function V:Read()
	if not merchant.open then return end
	local changed = 0
	for _, item in ipairs(ns.MerchantItems()) do
		local unit = V.UnitPrice(item)
		if unit and ns.db.vendor[item.id] ~= unit then
			ns.db.vendor[item.id] = unit
			changed = changed + 1
		end
	end
	if changed > 0 then
		ns:Debug("vendor: recorded", changed, "prices from", tostring(UnitName and UnitName("npc")))
		ns:Send("VendorPricesChanged")
	end
end

-- Item data can arrive a moment after the window opens; read once it settles.
local readSoon = ns:Debounce("Vendor read", 0.3, function() V:Read() end)
ns:On("MERCHANT_SHOW", readSoon)
ns:On("MERCHANT_UPDATE", function()
	if merchant.open then readSoon() end
end)
