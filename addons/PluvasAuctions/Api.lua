-- Pluvas' Auctions: what other Pluvas addons may read, through ns:Peer("PluvasAuctions").
--
-- Saved data only, so every function is safe in tooltips. This is a contract with other addons
-- (Pluvas' Professions prices disenchanting with it): add functions, never change these.
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
	-- as old under the player's /pa stale setting; nil while it is fresh. now defaults to time().
	StaleAge = function(seen, now)
		return P.StaleAge(seen, now or time())
	end,
})
