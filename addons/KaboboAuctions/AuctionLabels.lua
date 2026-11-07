-- Kabobo's Auctions: undercut status beside each of your auctions in the auction house's
-- Auctions tab ("Undercut 10c", "Undercut, same price", "Lowest").
--
-- The list is AuctionHouseFrame.AuctionsFrame.AllAuctionsList (Blizzard_AuctionHouseUI, shared
-- by Forever and Mainline): a ScrollBox with a table builder, columns Name (fills), Bid 120,
-- Buyout 120, Time left 50. The label sits at the right end of the Name column. Hooked with
-- hooksecurefunc and a ScrollBox callback only; the font strings are ours and kept in a table of
-- our own, so nothing of Blizzard's is replaced or written to.
local _, ns = ...
local AL = ns:NewModule("AuctionLabels")
local U = ns.Undercut
local PUI = ns.KaboboUI

AL.RIGHT_OFFSET = -335   -- Bid 120 + Buyout 120 + Time left 50 + padding, from the row's right

local labels = setmetatable({}, { __mode = "k" })   -- row frame -> font string
local list

-- What the label says for one row of your auctions, or nil.
function AL.Text(rowData)
	if not (rowData and rowData.itemKey) then return nil end
	local sold = Enum and Enum.AuctionStatus and rowData.status == Enum.AuctionStatus.Sold
	if sold then return nil end
	local all = U:Mine()
	local e = all and all[U.KeyOf(rowData.itemKey, rowData.itemLink)]
	if not (e and e.s) then return nil end
	if e.s == "matched" or (e.s == "undercut" and e.o == e.u) then return PUI.Color("Undercut, same price", "bad") end
	if e.s == "undercut" then return PUI.Color("Undercut ", "bad") .. PUI.Money(e.o) end
	return PUI.Color("Lowest", "good")
end

local function decorate(row)
	local text = ns.db.settings.auctionLabels and AL.Text(row.rowData) or nil
	local fs = labels[row]
	if not fs then
		if not text then return end
		fs = PUI.Text(row, "body", "RIGHT")
		fs:SetPoint("RIGHT", row, "RIGHT", AL.RIGHT_OFFSET, 0)
		labels[row] = fs
	end
	fs:SetText(text or "")
end

function AL:Refresh()
	local box = list and list.ScrollBox
	if not (box and box.ForEachFrame and list:IsVisible()) then return end
	box:ForEachFrame(decorate)
end

function AL:Hook()
	local frame = AuctionHouseFrame and AuctionHouseFrame.AuctionsFrame
	list = frame and frame.AllAuctionsList
	if not (list and list.ScrollBox) then
		ns:Debug("auctions list not found, no undercut labels")
		list = nil
		return
	end
	local update = ns:Guard("Auction labels", function() AL:Refresh() end)
	if list.RefreshScrollFrame then hooksecurefunc(list, "RefreshScrollFrame", update) end
	local box = list.ScrollBox
	if box.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event then
		box:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, update, AL)
		if ScrollBoxListMixin.Event.OnDataRangeChanged then
			box:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, update, AL)
		end
	end
	list:HookScript("OnShow", update)
end

ns:WhenLoaded("Blizzard_AuctionHouseUI", function() AL:Hook() end)
ns:On("UndercutsChanged", function() AL:Refresh() end)
ns:On("SettingChanged", function(key) if key == "auctionLabels" then AL:Refresh() end end)
