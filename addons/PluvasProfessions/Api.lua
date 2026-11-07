-- Pluvas' Professions: what other Pluvas addons may read, through ns:Peer("PluvasProfessions").
--
-- Plain item info only, so every function is safe in tooltips and panels. This is a contract
-- with other addons (Pluvas' Auctions shows disenchant value in the profession window): add
-- functions, never change these.
local _, ns = ...
local DE, DT = ns.Disenchant, ns.DisenchantTooltip

ns:Expose({
	-- Expected value of disenchanting one item (itemID or link): the sum over its possible
	-- results of chance x average amount x price(itemID), where price gives copper per unit or
	-- nil (and optionally when that price was last seen). Returns copper (before any AH cut),
	-- how many results had no price and when the oldest price used was last seen, or nil when
	-- the item cannot be disenchanted or the client has not loaded it yet.
	DisenchantValue = function(item, price)
		local outcomes = DT.ItemOutcomes(item)
		if not outcomes then return nil end
		return DE.Value(outcomes, price)
	end,
})
