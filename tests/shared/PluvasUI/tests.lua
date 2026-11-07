-- PluvasUI: tests. Loaded on its own as addon "PluvasUITest" (see tests/run.js).
local UI = _NS.PluvasUI

-- Style

test("color wraps text in a color code", function()
	eq(UI.Color("Hi", "accent"), "|cff22b8cfHi|r")
	eq(UI.Color(5, "ff0000"), "|cffff00005|r")
end)

test("rgb from a token", function()
	local r, g, b = UI.RGB("bad")
	near(r, 1); near(g, 0x50 / 255); near(b, 0x50 / 255)
end)

test("chat prefix uses the accent color", function()
	eq(UI.Prefix("Pluvas' Thing"), "|cff22b8cfPluvas' Thing|r:")
end)

-- Format

test("money with colored letters", function()
	eq(UI.Money(0), "0|cffeda55fc|r")
	eq(UI.Money(123456), "12|cffffd700g|r 34|cffc7c7cfs|r 56|cffeda55fc|r")
	eq(UI.Money(5000), "50|cffc7c7cfs|r")
	eq(UI.Money(-10000), "-1|cffffd700g|r")
	eq(UI.Money(12345670000), "1,234,567|cffffd700g|r")
	eq(UI.Money(nil), "|cff808080-|r")
end)

test("money with coin icons", function()
	local G = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
	local S = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
	local C = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
	eq(UI.MoneyIcons(0), "0" .. C)
	eq(UI.MoneyIcons(123456), "12" .. G .. " 34" .. S .. " 56" .. C)
	eq(UI.MoneyIcons(-10000), "-1" .. G)
end)

test("signed money marks gains and losses", function()
	eq(UI.SignedMoney(100), "|cff40d040+|r" .. UI.Money(100))
	eq(UI.SignedMoney(-100), "|cffff5050-|r" .. UI.Money(100))
	eq(UI.SignedMoney(0), UI.Money(0))
	eq(UI.SignedMoney(100, true), "|cff40d040+|r" .. UI.MoneyIcons(100))
end)

test("age and clock", function()
	eq(UI.Age(45), "45s"); eq(UI.Age(720), "12m"); eq(UI.Age(3 * 3600), "3h"); eq(UI.Age(5 * 86400), "5d")
	eq(UI.Age(nil), "?")
	eq(UI.Clock(65), "1:05"); eq(UI.Clock(-3), "0:00")
end)

-- Label/value lines

test("tooltip lines: accent labels by default, any color on request", function()
	local got = {}
	local tooltip = { AddDoubleLine = function(_, l, r, lr, lg, lb) got[#got + 1] = { l, r, lr, lg, lb } end }
	UI.AddTooltipLines(tooltip, { { "Price", "5s" }, { "  detail", nil, color = "soft" } })
	eq(got[1][1], "Price"); eq(got[1][2], "5s")
	near(got[1][3], 0x22 / 255)
	eq(got[2][2], " ", "an empty value still makes a double line")
	near(got[2][3], 0xd9 / 255)
end)

test("a line panel shows its lines, sizes to them, and hides leftovers", function()
	local panel = UI.LinePanel(UIParent, { lineHeight = 10 })
	eq(panel:IsShown(), false, "starts hidden")
	panel:SetLines({ { "A", "1" }, { "B", "2", color = "muted" }, { "C", "3" } })
	eq(panel:GetHeight(), 30)
	eq(panel.labels[1]:GetText(), "|cff22b8cfA|r")
	eq(panel.labels[2]:GetText(), "|cff808080B|r")
	eq(panel.values[3]:GetText(), "3")
	panel:SetLines({ { "Only", "x" } })
	eq(panel:GetHeight(), 10)
	eq(panel.labels[2]:IsShown(), false)
	eq(panel.labels[1]:IsShown(), true)
end)

-- Grid

test("a grid has a cell per row and column", function()
	local grid = UI.Grid(UIParent, { columns = { "Today", "Week" }, rows = { "Sales", "Cut", "Profit" } })
	eq(#grid.cells, 3)
	eq(#grid.cells[1], 2)
	grid:Set(3, 2, "42")
	eq(grid.cells[3][2]:GetText(), "42")
	grid:Set(3, 2, nil)
	eq(grid.cells[3][2]:GetText(), "")
end)

-- Window

local events = {}
local function newWindow(extra)
	local opts = {
		name = "PluvasUITestWindow" .. (#events + 1),
		title = "Test", width = 300, height = 400,
		onShow = function(w) events[#events + 1] = "show" end,
		onHide = function(w, reason) events[#events + 1] = "hide:" .. reason end,
	}
	for k, v in pairs(extra or {}) do opts[k] = v end
	return UI.Window(opts)
end

local function onEscapeList(name)
	for _, n in ipairs(UISpecialFrames) do
		if n == name then return true end
	end
	return false
end

test("window names must start with the addon name", function()
	local ok = pcall(UI.Window, { name = "SomeoneElsesFrame" })
	eq(ok, false)
end)

test("a new window starts hidden, floating in the center, closable with Escape", function()
	local w = newWindow()
	eq(w:IsShown(), false)
	eq(w:IsDocked(), false)
	eq((w:GetPoint(1)), "CENTER")
	truthy(onEscapeList(w:GetName()), "on the Escape list")
	eq(w.title:GetText(), "Test")
end)

test("the window carries the Pluvas signature", function()
	local w = newWindow()
	truthy(w.signature, "wordmark")
	truthy(w.signature:GetText():find("Pluvas", 1, true), "wordmark text")
	truthy(w.signatureLine, "accent line")
end)

test("the footer stops short of the signature", function()
	local w = newWindow()
	local footer = w:Footer()
	eq(w:Footer(), footer, "one footer per window")
	local _, relativeTo = footer:GetPoint(2)
	eq(relativeTo, w.signature)
end)

test("a floating window remembers where it was dragged", function()
	local pos = {}
	local w = newWindow({ position = pos })
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -80)
	w.scripts.OnDragStop(w)
	eq(pos.point, "TOPLEFT"); eq(pos.x, 120); eq(pos.y, -80)
	local again = newWindow({ position = pos })
	local point, _, _, x, y = again:GetPoint(1)
	eq(point, "TOPLEFT"); eq(x, 120); eq(y, -80)
end)

test("docking anchors to the right of the host and leaves Escape to it", function()
	local host = CreateFrame("Frame", "PluvasUITestHost")
	host:SetHeight(600)
	local w = newWindow()
	eq(w:DockTo(host, { x = 54 }), true)
	local point, relativeTo, relativePoint, x = w:GetPoint(1)
	eq(point, "TOPLEFT"); eq(relativeTo, host); eq(relativePoint, "TOPRIGHT"); eq(x, 54)
	eq(w:GetHeight(), 600, "matches the host height")
	eq(onEscapeList(w:GetName()), false)
	w:Float()
	eq(onEscapeList(w:GetName()), true)
	eq(w:GetHeight(), 400)
end)

test("docking to a hidden host fails", function()
	local host = CreateFrame("Frame")
	host:Hide()
	eq(newWindow():DockTo(host), false)
end)

test("a docked window closes with its host and says why", function()
	local host = CreateFrame("Frame")
	local w = newWindow()
	w:DockTo(host)
	events = {}
	w:Show()
	host:Hide()
	eq(w:IsShown(), false)
	eq(table.concat(events, ","), "show,hide:host")
end)

test("closing reasons: user by default, or the one given", function()
	local w = newWindow()
	events = {}
	w:Show(); w:Hide()
	w:Show(); w:Close("logout")
	w:Toggle(); w:Toggle()
	eq(table.concat(events, ","), "show,hide:user,show,hide:logout,show,hide:user")
end)

test("the host hook is added once, however often the window docks", function()
	local host = CreateFrame("Frame")
	local w = newWindow()
	w:DockTo(host); w:DockTo(host); w:DockTo(host)
	events = {}
	w:Show()
	host:Hide()
	eq(table.concat(events, ","), "show,hide:host")
end)

-- List

local function items(n)
	local out = {}
	for i = 1, n do out[i] = { text = "Item " .. i, right = tostring(i) } end
	return out
end

test("a list shows as many rows as fit its height", function()
	local list = UI.List(UIParent, {})
	list:SetHeight(18 * 5)
	eq(list.visible, 5)
	eq(list.rows[5]:IsShown(), true)
end)

test("rows are created only when they first need to show, then reused", function()
	local list = UI.List(UIParent, {})
	eq(#list.rows, 1, "nothing beyond one row before the list has a size")
	list:SetHeight(18 * 5)
	eq(#list.rows, 5)
	local fifth = list.rows[5]
	list:SetHeight(18 * 3)
	eq(#list.rows, 5, "shrinking keeps rows for later")
	eq(fifth:IsShown(), false)
	list:SetHeight(18 * 6)
	eq(list.rows[5], fifth, "growing reuses them")
	eq(#list.rows, 6)
end)

test("a list never creates more than maxRows rows", function()
	local list = UI.List(UIParent, { maxRows = 4 })
	list:SetHeight(18 * 50)
	eq(#list.rows, 4)
end)

test("widgets share one set of methods", function()
	local a, b = UI.List(UIParent, {}), UI.List(UIParent, {})
	eq(a.Refresh, b.Refresh)
	eq(a.rows[1].scripts.OnEnter, b.rows[1].scripts.OnEnter)
	local w1 = UI.Window({ name = "PluvasUITestShareA" })
	local w2 = UI.Window({ name = "PluvasUITestShareB" })
	eq(w1.DockTo, w2.DockTo)
	eq(w1.scripts.OnShow, w2.scripts.OnShow)
end)

test("icon rows fill from items, and empty rows clear", function()
	local list = UI.List(UIParent, {})
	list:SetHeight(18 * 3)
	list:SetItems(items(2))
	eq(list.rows[1].text:GetText(), "Item 1")
	eq(list.rows[2].right:GetText(), "2")
	eq(list.rows[3].text:GetText(), "")
	eq(list.rows[3].item, nil)
end)

test("a header row is gold and has no icon", function()
	local list = UI.List(UIParent, {})
	list:SetHeight(18 * 2)
	list:SetItems({ { header = true, text = "Trainer", right = "3" } })
	eq(list.rows[1].text:GetText(), "|cffffd200Trainer|r")
end)

test("scrolling stays within the items", function()
	local list = UI.List(UIParent, {})
	list:SetHeight(18 * 4)
	list:SetItems(items(10))
	list:Scroll(3)
	eq(list.rows[1].text:GetText(), "Item 4")
	list:Scroll(100)
	eq(list.offset, 6, "last page")
	eq(list.rows[4].text:GetText(), "Item 10")
	list:Scroll(-100)
	eq(list.offset, 0)
	local first, last, total = list:Range()
	eq(first, 1); eq(last, 4); eq(total, 10)
end)

test("the mouse wheel scrolls and reports it", function()
	local scrolled = 0
	local list = UI.List(UIParent, { onScroll = function() scrolled = scrolled + 1 end })
	list:SetHeight(18 * 4)
	list:SetItems(items(10))
	list.scripts.OnMouseWheel(list, -1)
	eq(list.offset, 3)
	eq(scrolled, 1)
	list.scripts.OnMouseWheel(list, 1)
	list.scripts.OnMouseWheel(list, 1)   -- already at the top: no report
	eq(scrolled, 2)
end)

test("new items start at the top unless asked to keep the offset", function()
	local list = UI.List(UIParent, {})
	list:SetHeight(18 * 4)
	list:SetItems(items(10))
	list:Scroll(4)
	list:SetItems(items(10), true)
	eq(list.offset, 4)
	list:SetItems(items(10))
	eq(list.offset, 0)
end)

test("an empty list has an empty range and can show a message", function()
	local list = UI.List(UIParent, {})
	list:SetHeight(18 * 4)
	list:SetItems({})
	local first, last, total = list:Range()
	eq(first, 0); eq(last, 0); eq(total, 0)
	list:SetEmptyText("Nothing here")
	eq(list.empty:GetText(), "Nothing here")
end)

test("a column list can reserve a header line above its rows", function()
	local list = UI.List(UIParent, { kind = "columns", headers = true, columns = { { width = 50 }, { width = 80 } } })
	list:SetHeight(18 * 4)
	eq(list.visible, 3, "the header takes one row's height")
	list:SetHeaders("When", "Item")
	eq(list.headers[2]:GetText(), "Item")
	local _, _, _, _, y = list.rows[1]:GetPoint(1)
	eq(y, -18, "rows start below the header")
end)

test("scroll to top", function()
	local list = UI.List(UIParent, {})
	list:SetHeight(18 * 4)
	list:SetItems(items(10))
	list:Scroll(5)
	list:ScrollToTop()
	eq(list.offset, 0)
	eq(list.rows[1].text:GetText(), "Item 1")
end)

test("column rows take one value per column", function()
	local list = UI.List(UIParent, { kind = "columns", columns = {
		{ width = 90 }, { width = 200 }, { width = 100, justify = "RIGHT" },
	} })
	list:SetHeight(18 * 2)
	list:SetItems({ { "a", "b", "c" } })
	eq(list.rows[1].cells[1]:GetText(), "a")
	eq(list.rows[1].cells[3]:GetText(), "c")
	eq(list.rows[2].cells[2]:GetText(), "")
end)

test("row callbacks get the row's item", function()
	local entered, clicked
	local list = UI.List(UIParent, {
		onEnter = function(_, item) entered = item end,
		onClick = function(_, item, button) clicked = button .. ":" .. item.text end,
	})
	list:SetHeight(18 * 3)
	list:SetItems(items(1))
	list.rows[1].scripts.OnEnter(list.rows[1])
	list.rows[1].scripts.OnClick(list.rows[1], "LeftButton")
	list.rows[2].scripts.OnClick(list.rows[2], "LeftButton")   -- empty row: nothing
	eq(entered.text, "Item 1")
	eq(clicked, "LeftButton:Item 1")
end)

-- Buttons and tabs

test("button wires text, size and click", function()
	local got
	local b = UI.Button(UIParent, { text = "Go", width = 80, onClick = function() got = true end })
	eq(b:GetText(), "Go")
	eq(b:GetWidth(), 80)
	b.scripts.OnClick(b, "LeftButton")
	eq(got, true)
end)

test("tab bar lays out tabs, selects one, and reports clicks", function()
	local picked
	local bar = UI.TabBar(UIParent, { width = 300, onSelect = function(key) picked = key end })
	bar:SetTabs({ "Tailoring", { key = "cook", text = "Cooking" } }, "Tailoring")
	eq(bar.buttons[1]:GetText(), "Tailoring")
	eq(bar.buttons[2]:GetText(), "Cooking")
	eq(bar.buttons[1].selected, true)
	eq(bar.buttons[2].selected, false)
	eq(bar.buttons[1]:GetWidth(), 100, "capped at maxTabWidth")
	bar.buttons[2].scripts.OnClick(bar.buttons[2])
	eq(picked, "cook")
	eq(bar.selected, "cook")
	eq(bar.buttons[2].selected, true)
	bar:SetTabs({ "Mining" }, "Mining")
	eq(bar.buttons[2]:IsShown(), false, "unused tab hidden")
end)
