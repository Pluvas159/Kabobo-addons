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
