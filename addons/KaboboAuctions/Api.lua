-- Kabobo's Auctions: what other Kabobo addons may read, through ns:Peer("KaboboAuctions").
--
-- Saved data only, so every function is safe in tooltips. This is a contract with other addons
-- (Kabobo's Professions prices disenchanting with it): add functions, never change these.
local _, ns = ...
local P = ns.Pricing

ns:Expose({
	-- AH price of one unit of an item (itemID or item link): the market value, or the lowest
	-- buyout when there is no market value yet. Also returns time() it was last seen. nil
	-- without price data.
	Price = function(item)
		local key = P.ItemKeyFromLink(item) or P.ItemKey(tonumber(item))
		local entry = P:Get(key)
		if not entry then return nil end
		return entry.m or entry.n, entry.t
	end,

	-- What selling for `gross` copper in `auctions` auctions leaves after the AH cut and the
	-- deposits. auctions defaults to 1; pass 0 to take off only the cut.
	Proceeds = function(gross, auctions)
		local _, _, net = P.NetProceeds(gross, 1, P.DEPOSIT * (auctions or 1))
		return net
	end,

	-- How old a price last seen at `seen` (Price's second result) is, in seconds, once it counts
	-- as old under the player's /ka stale setting; nil while it is fresh. now defaults to time().
	StaleAge = function(seen, now)
		return P.StaleAge(seen, now or time())
	end,

	-- One craft of a recipe, also one this character has not learned. recipe is a recipe string
	-- ("minYield:maxYield|itemID*qty,itemID*qty", as Kabobo's Professions saves them), made the
	-- item outputItemID. Mats are priced as everywhere in Kabobo's Auctions (the cheaper of AH and
	-- vendor; mats you can craft from their own mats when that is cheaper). Returns the profit
	-- (nil without an AH price for the item or for every mat), the mats cost, what the items bring
	-- in after the AH cut and deposit, and how many mats had no price.
	CraftProfit = function(outputItemID, recipe)
		local C = ns.Crafting
		local s = C.CraftSummary(recipe, C.MatPrice, C.RecipeOf, (C.AHPrice(outputItemID)))
		return s.profit, s.cost, s.net, s.missing or 0
	end,

	-- About how many of an item sell per day on the AH, from the player's full scans (an
	-- estimate), and whether enough scans back it; nil before two scans were compared.
	SoldPerDay = function(itemID)
		return ns.Sales:RateOf(itemID)
	end,
})
