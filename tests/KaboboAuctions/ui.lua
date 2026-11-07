-- Kabobo's Auctions: ledger window smoke tests (KaboboUI, with the frame stand-ins from mocks.lua).
-- Runs after tests.lua, so the addon is already loaded and logged in.
local ns = _NS

test("ledger window opens with the shared look and remembers its place", function()
	SlashCmdList.KABOBOAUCTIONS("")
	local w = KaboboAuctionsFrame
	truthy(w and w:IsShown(), "ledger shown")
	eq(w.title:GetText(), "Kabobo's Auctions")
	truthy(w.signature, "Kabobo signature")
	truthy(ns.db.settings.ledgerWindow, "position table")
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -60)
	w.scripts.OnDragStop(w)
	eq(ns.db.settings.ledgerWindow.x, 50)
end)

test("ledger list switches between recent and top items", function()
	local w = KaboboAuctionsFrame
	w.topButton.scripts.OnClick(w.topButton, "LeftButton")
	eq(w.topButton.selected, true)
	eq(w.recentButton.selected, false)
	w.recentButton.scripts.OnClick(w.recentButton, "LeftButton")
	eq(w.recentButton.selected, true)
end)

test("crafts window lists the open profession's recipes by profit", function()
	local me = ns.Crafting:CharTable()
	me[197] = { name = "Tailoring", r = { [2996] = "1:1|2589*2", [4238] = "1:1|2589*1" } }
	me[164] = { name = "Blacksmithing", r = { [2862] = "1:1|2835*1" } }
	local items = ns.db.realms[ns.realmKey].items
	items["2589"] = { m = 100, t = time() }
	items["2996"] = { m = 1000, q = 12, t = time() }
	items["4238"] = { m = 5000, t = time() }

	SlashCmdList.KABOBOAUCTIONS("crafts")
	local w = KaboboAuctionsCraftsFrame
	truthy(w and w:IsShown(), "crafts window shown")
	eq(w.tabs.selected, 164, "first tab by name")
	local tailoring
	for _, b in ipairs(w.tabs.buttons) do
		if b.key == 197 then tailoring = b end
	end
	tailoring.scripts.OnClick(tailoring, "LeftButton")
	eq(w.tabs.selected, 197)
	local first, last, total = w.list:Range()
	eq(total, 2)
	eq(w.list.items[1].id, 4238, "most profitable first")
	eq(w.list.items[2].listed, 12)

	SlashCmdList.KABOBOAUCTIONS("crafts")
	eq(w:IsShown(), false)
	me[197], me[164] = nil, nil
	items["2589"], items["2996"], items["4238"] = nil, nil, nil
end)

test("clicking a recipe opens its shopping list", function()
	local me = ns.Crafting:CharTable()
	me[197] = { name = "Tailoring", r = { [2996] = "1:1|2589*2" } }
	ns.ShopWindow:Open(2996, 3)
	local w = KaboboAuctionsShopFrame
	truthy(w and w:IsShown(), "shopping window shown")
	eq(ns.Shopping.list.crafts, 3)
	eq(ns.Shopping.list.mats[1].need, 6)
	w.plusButton.scripts.OnClick(w.plusButton, "LeftButton")
	eq(ns.Shopping.list.crafts, 4)
	w:Close("user")
	eq(ns.Shopping.list, nil, "closing it drops the list")
	me[197] = nil
end)

test("ledger lists your auctions", function()
	local w = KaboboAuctionsFrame
	if not w:IsShown() then SlashCmdList.KABOBOAUCTIONS("") end
	w.mineButton.scripts.OnClick(w.mineButton, "LeftButton")
	eq(w.mineButton.selected, true)
	eq(w.recentButton.selected, false)
	w.recentButton.scripts.OnClick(w.recentButton, "LeftButton")
end)

test("ledger toggles closed", function()
	SlashCmdList.KABOBOAUCTIONS("")
	eq(KaboboAuctionsFrame:IsShown(), false)
end)

test("crafts window switches between profit and profit per day", function()
	local me = ns.Crafting:CharTable()
	me[197] = { name = "Tailoring", r = { [2996] = "1:1|2589*2" } }
	ns.CraftsWindow:Open(197)
	local w = KaboboAuctionsCraftsFrame
	truthy(w:IsShown(), "opened on a profession")
	eq(w.tabs.selected, 197)
	ns.db.settings.craftsSort = "profit"
	w.sortButton.scripts.OnClick(w.sortButton, "LeftButton")
	eq(ns.db.settings.craftsSort, "day")
	eq(w.sortButton:GetText(), "Sort: profit per day")
	w.sortButton.scripts.OnClick(w.sortButton, "LeftButton")
	eq(ns.db.settings.craftsSort, "profit")
	w:Close("user")
	me[197] = nil
end)

test("shopping list shows the crafts to do under the mats", function()
	local me = ns.Crafting:CharTable()
	me[197] = { name = "Tailoring", r = { [2996] = "1:1|2589*2", [4238] = "1:1|2996*3" } }
	ns.ShopWindow:Open(4238, 1)
	local w = KaboboAuctionsShopFrame
	local items = w.list.items
	eq(items[1].id, 2589); eq(items[1].need, 6)
	truthy(items[2].header, "craft section")
	eq(items[3].id, 2996); eq(items[3].crafts, 3)
	eq(items[4].id, 4238); eq(items[4].crafts, 1)
	w:Close("user")
	me[197] = nil
end)
