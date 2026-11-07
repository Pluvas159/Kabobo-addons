-- Pluvas' Auctions: the full scan button under the auction house window. Left-click scans,
-- right-click opens the ledger. Shows the scan state and counts down the server cooldown.
local _, ns = ...
local SB = ns:NewModule("ScanButton")
local PUI = ns.PluvasUI

local button, ticker

-- Text and whether the button can be clicked, for the scanner's state.
function SB.Label(state, progress, cooldown)
	if state == "waiting" then return "Waiting for AH...", false end
	if state == "processing" then return string.format("Scanning %d%%", progress * 100), false end
	if cooldown > 0 then return "Full scan in " .. PUI.Clock(cooldown), false end
	return "Full scan", true
end

local function update()
	if not button then return end
	local scanner = ns.Scanner
	local text, enabled = SB.Label(scanner.state, scanner.progress, scanner:CooldownRemaining())
	button:SetText(text)
	if enabled then button:Enable() else button:Disable() end
end

local function create()
	if button or not AuctionHouseFrame then return end
	button = PUI.Button(AuctionHouseFrame, {
		name = "PluvasAuctionsScanButton",
		width = 150,
		height = 24,
		rightClick = true,
		onClick = function(_, mouseButton)
			if mouseButton == "RightButton" then ns.LedgerWindow:Toggle() else ns.Scanner:FullScan() end
		end,
		tooltip = {
			title = ns.title,
			lines = {
				"Scan every auction and update the price data.",
				{ text = "The server allows one full scan every 15 minutes.", color = "muted" },
				{ text = "Right-click to open the ledger.", color = "muted" },
			},
		},
	})
	button:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, -2)
end

ns:On("AUCTION_HOUSE_SHOW", function()
	create()
	if not button then
		-- The Blizzard AH UI may still be loading; try again next frame.
		C_Timer.After(0, function() create(); update() end)
	end
	update()
	if ticker then ticker:Cancel() end
	-- Once a second only while the AH is open, for the cooldown countdown.
	ticker = C_Timer.NewTicker(1, update)
end)

ns:On("AUCTION_HOUSE_CLOSED", function()
	if ticker then ticker:Cancel(); ticker = nil end
end)

ns:On("ScanStateChanged", update)
