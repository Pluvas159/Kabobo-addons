-- Pluvas' Auctions: ledger window smoke tests (PluvasUI, with the frame stand-ins from mocks.lua).
-- Runs after tests.lua, so the addon is already loaded and logged in.
local ns = _NS

test("ledger window opens with the shared look and remembers its place", function()
	SlashCmdList.PLUVASAUCTIONS("")
	local w = PluvasAuctionsFrame
	truthy(w and w:IsShown(), "ledger shown")
	eq(w.title:GetText(), "Pluvas' Auctions")
	truthy(w.signature, "Pluvas signature")
	truthy(ns.db.settings.ledgerWindow, "position table")
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -60)
	w.scripts.OnDragStop(w)
	eq(ns.db.settings.ledgerWindow.x, 50)
end)

test("ledger list switches between recent and top items", function()
	local w = PluvasAuctionsFrame
	w.topButton.scripts.OnClick(w.topButton, "LeftButton")
	eq(w.topButton.selected, true)
	eq(w.recentButton.selected, false)
	w.recentButton.scripts.OnClick(w.recentButton, "LeftButton")
	eq(w.recentButton.selected, true)
end)

test("ledger toggles closed", function()
	SlashCmdList.PLUVASAUCTIONS("")
	eq(PluvasAuctionsFrame:IsShown(), false)
end)
