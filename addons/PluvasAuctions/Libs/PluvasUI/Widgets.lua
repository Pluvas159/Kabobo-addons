-- PluvasUI: reusable widgets built on the style tokens in Style.lua.
--
--   UI.Text(parent, font, justify, opts)       font string
--   UI.ShowTooltip / UI.SetTooltip             tooltips from a title and lines
--   UI.Button(parent, opts)                    standard button
--   UI.SetSelected(button, on)                 mark the selected button of a group
--   UI.TabBar(parent, opts)                    row of buttons, one selected
--   UI.List(parent, opts)                      scrolling list of rows (icon rows or columns)
--   UI.Window(opts)                            movable window that can dock to another frame,
--                                              with the Pluvas signature and a footer line
--
-- Lightweight by design: widgets share one set of methods and scripts (no closures per
-- instance), list rows are created only when they first need to show, scrolling redraws only
-- the visible rows, and nothing runs per frame. See shared/PluvasUI/README.md for the rules.
local ADDON, ns = ...
local UI = ns.PluvasUI
local S = UI.Sizes

-- Copies shared methods onto a frame.
local function mix(target, methods)
	for k, v in pairs(methods) do target[k] = v end
	return target
end

-- Callbacks run inside Blizzard script chains (hooks), so contain their errors.
local function guard(name, fn)
	if not fn then return nil end
	if ns.Guard then return ns:Guard(name, fn) end
	return fn
end

-- Text ----------------------------------------------------------------------------

-- font: a key of UI.Fonts or a font object name. opts.wrap = true allows several lines.
function UI.Text(parent, font, justify, opts)
	local fs = parent:CreateFontString(nil, "OVERLAY", UI.Fonts[font] or font or UI.Fonts.body)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap((opts and opts.wrap) and true or false)
	return fs
end

-- Tooltips ------------------------------------------------------------------------

-- lines: strings (white, wrapped) or { text = "...", color = key, wrap = false }.
function UI.ShowTooltip(owner, title, lines, anchor)
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetText(title or "", UI.RGB("gold"))
	for _, line in ipairs(lines or {}) do
		if type(line) == "string" then
			GameTooltip:AddLine(line, 1, 1, 1, true)
		elseif line.text then
			local r, g, b = UI.RGB(line.color or "text")
			GameTooltip:AddLine(line.text, r, g, b, line.wrap ~= false)
		end
	end
	GameTooltip:Show()
end

function UI.HideTooltip()
	GameTooltip:Hide()
end

local function tooltipEnter(self)
	local t = self.pluvasTooltip
	local title, lines = t.title, t.lines
	if type(title) == "function" then title = title(self) end
	if type(lines) == "function" then lines = lines(self) end
	UI.ShowTooltip(self, title, lines)
end

-- title and lines can be functions(frame), for tooltips that change.
function UI.SetTooltip(frame, title, lines)
	frame.pluvasTooltip = { title = title, lines = lines }
	frame:SetScript("OnEnter", tooltipEnter)
	frame:SetScript("OnLeave", UI.HideTooltip)
end

-- Buttons -------------------------------------------------------------------------

-- opts: text, width, height, name (global, must start with the addon name), onClick(self,
-- mouseButton), rightClick = true to also take right clicks, tooltip = { title, lines }.
function UI.Button(parent, opts)
	opts = opts or {}
	local b = CreateFrame("Button", opts.name, parent, UI.Templates.button)
	b:SetSize(opts.width or 110, opts.height or S.button)
	if opts.text then b:SetText(opts.text) end
	if opts.rightClick then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
	if opts.onClick then b:SetScript("OnClick", guard((opts.name or "button") .. " click", opts.onClick)) end
	if opts.tooltip then UI.SetTooltip(b, opts.tooltip.title, opts.tooltip.lines) end
	return b
end

-- A gray (disabled) button reads as "unavailable", so a selected button keeps its highlight lit
-- instead of being disabled.
function UI.SetSelected(button, on)
	if on then button:LockHighlight() else button:UnlockHighlight() end
	button.selected = on and true or false
end

-- Tab bar -------------------------------------------------------------------------
--
-- opts: width (of the bar), maxTabWidth (default 100), height, onSelect(key).
-- bar:SetTabs(tabs, selectedKey): tabs = { { key = ..., text = ... }, ... } or plain strings.
-- bar:Select(key) only marks the tab; onSelect runs on clicks.

local TabBar = {}

local function tabClick(self)
	local bar = self.bar
	bar:Select(self.key)
	if bar.opts.onSelect then bar.opts.onSelect(self.key) end
end

function TabBar:SetTabs(tabs, selected)
	local opts = self.opts
	local n = #tabs
	local width = 0
	if n > 0 then
		width = math.floor(((opts.width or 300) - (n - 1) * S.gap) / n)
		width = math.min(opts.maxTabWidth or 100, width)
	end
	for i = 1, math.max(n, #self.buttons) do
		local b = self.buttons[i]
		local tab = tabs[i]
		if tab then
			if not b then
				b = UI.Button(self, { height = opts.height or S.tab })
				b.bar = self
				b:SetScript("OnClick", self.click)
				self.buttons[i] = b
			end
			if type(tab) ~= "table" then tab = { key = tab, text = tab } end
			b.key = tab.key
			b:SetText(tab.text or tostring(tab.key))
			b:SetWidth(width)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (width + S.gap), 0)
			b:Show()
		elseif b then
			b:Hide()
			b.key = nil
		end
	end
	self:Select(selected)
end

function TabBar:Select(key)
	self.selected = key
	for _, b in ipairs(self.buttons) do
		if b.key ~= nil then UI.SetSelected(b, b.key == key) end
	end
end

function UI.TabBar(parent, opts)
	local bar = mix(CreateFrame("Frame", nil, parent), TabBar)
	bar.opts = opts or {}
	bar:SetSize(bar.opts.width or 300, bar.opts.height or S.tab)
	bar.buttons = {}
	bar.click = guard("tab click", tabClick)
	return bar
end

-- List ----------------------------------------------------------------------------
--
-- A list of rows that fills its own height and scrolls with the mouse wheel. Rows are created
-- the first time they need to show and then reused; update(row, item) fills them.
--
-- opts:
--   kind        "icon" (icon, text, right text; the default) or "columns"
--   columns     for "columns": { { width = 90, justify = "LEFT", font = "body" }, ... }
--   rightWidth  for "icon": width of the right text (default 120)
--   rowHeight   default UI.Sizes.row
--   maxRows     most rows that can show at once (default 40)
--   update      function(row, item) to fill a row. Defaults: UI.SetIconRow(row, item) or
--               UI.SetColumns(row, unpack(item)).
--   onEnter     function(row, item) for a tooltip
--   onClick     function(row, item, mouseButton)
--   interactive function(item) -> whether the row takes the mouse (default: when onEnter or
--               onClick is set)
--   scrollStep  rows per wheel notch (default 3)
--   onScroll    function(list) after scrolling, e.g. to update a "1-20 of 45" footer
--
-- list:SetItems(items, keepOffset), list:Refresh(), list:Scroll(rows), list:Range() -> first,
-- last, total, list:SetEmptyText(text). The empty text shows below the last visible row.

local function setText(fs, text)
	fs:SetText(text or "")
end

-- values: { icon, text, right, header = bool, desaturate = bool }. A header has no icon.
function UI.SetIconRow(row, v)
	v = v or {}
	local icon = (not v.header and v.text) and (v.icon or UI.Textures.unknownIcon) or nil
	setText(row.text, v.header and v.text and UI.Color(v.text, "gold") or v.text)
	setText(row.right, v.right)
	row.icon:SetShown(icon ~= nil)
	if icon then
		row.icon:SetTexture(icon)
		row.icon:SetDesaturated(v.desaturate and true or false)
	end
	-- The text takes the whole row when there is nothing on the right.
	row.text:ClearAllPoints()
	if icon then
		row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	else
		row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
	end
	if v.right and v.right ~= "" then
		row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
	else
		row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	end
end

-- One value per column.
function UI.SetColumns(row, ...)
	for i, cell in ipairs(row.cells) do
		setText(cell, (select(i, ...)))
	end
end

local function defaultIconUpdate(row, item) UI.SetIconRow(row, item) end
local function defaultColumnsUpdate(row, item) UI.SetColumns(row, unpack(item)) end
local function clearIconRow(row) UI.SetIconRow(row, nil) end
local function clearColumnsRow(row) UI.SetColumns(row) end

-- Shared row scripts: each row knows its list.
local function rowEnter(self)
	local f = self.list.opts.onEnter
	if self.item and f then f(self, self.item) end
end
local function rowClick(self, button)
	local f = self.list.opts.onClick
	if self.item and f then f(self, self.item, button) end
end

local function makeRow(list, i)
	local opts = list.opts
	local height = list.rowHeight
	local row = CreateFrame("Button", nil, list)
	row.list = list
	row:SetHeight(height)
	row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * height)
	row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
	row:SetHighlightTexture(UI.Textures.rowHighlight, "ADD")
	if opts.kind == "columns" then
		row.cells = {}
		local x = 0
		for c, col in ipairs(opts.columns or {}) do
			local cell = UI.Text(row, col.font or "body", col.justify)
			cell:SetWidth(col.width)
			cell:SetPoint("LEFT", row, "LEFT", x, 0)
			row.cells[c] = cell
			x = x + col.width + (opts.columnGap or 6)
		end
	else
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(S.icon, S.icon)
		row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
		row.right = UI.Text(row, "body", "RIGHT")
		row.right:SetWidth(opts.rightWidth or 120)
		row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.text = UI.Text(row, "body", "LEFT")
	end
	row:SetScript("OnEnter", rowEnter)
	row:SetScript("OnLeave", UI.HideTooltip)
	row:SetScript("OnClick", rowClick)
	return row
end

local List = {}

function List:Layout()
	local fit = math.floor((self:GetHeight() or 0) / self.rowHeight)
	self.visible = math.max(1, math.min(self.maxRows, fit))
	for i = #self.rows + 1, self.visible do self.rows[i] = makeRow(self, i) end
	for i, row in ipairs(self.rows) do row:SetShown(i <= self.visible) end
end

function List:Refresh()
	local n = #self.items
	self.offset = math.max(0, math.min(self.offset, n - self.visible))
	for i = 1, self.visible do
		local row = self.rows[i]
		local item = self.items[self.offset + i]
		row.item = item
		if item then self.update(row, item) else self.clear(row) end
		row:EnableMouse(item ~= nil and self.interactive(item) and true or false)
	end
	local shown = math.min(n, self.visible)
	self.empty:ClearAllPoints()
	self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(shown + 1) * self.rowHeight)
	self.empty:SetPoint("RIGHT", self, "RIGHT", 0, 0)
end

function List:SetItems(items, keepOffset)
	self.items = items or {}
	if not keepOffset then self.offset = 0 end
	self:Refresh()
end

function List:Scroll(rows)
	local before = self.offset
	self.offset = math.max(0, self.offset + rows)
	self:Refresh()
	if self.offset ~= before and self.opts.onScroll then self.opts.onScroll(self) end
end

-- first, last, total of the visible part (0, 0, 0 when empty).
function List:Range()
	local n = #self.items
	if n == 0 then return 0, 0, 0 end
	return self.offset + 1, math.min(self.offset + self.visible, n), n
end

function List:SetEmptyText(text)
	self.empty:SetText(text or "")
end

local function listWheel(self, delta)
	self:Scroll(-delta * (self.opts.scrollStep or 3))
end

-- Docking and resizing change the height; refit the rows whenever it does.
local function listSizeChanged(self)
	self:Layout()
	self:Refresh()
end

local function always() return true end
local function never() return false end

function UI.List(parent, opts)
	opts = opts or {}
	local list = mix(CreateFrame("Frame", nil, parent), List)
	list.opts = opts
	list.rowHeight = opts.rowHeight or S.row
	list.maxRows = opts.maxRows or 40
	local columns = opts.kind == "columns"
	list.update = opts.update or (columns and defaultColumnsUpdate or defaultIconUpdate)
	list.clear = columns and clearColumnsRow or clearIconRow
	list.interactive = opts.interactive or ((opts.onEnter or opts.onClick) and always or never)
	list.items, list.offset, list.rows, list.visible = {}, 0, {}, 1
	list.empty = UI.Text(list, "muted", "CENTER", { wrap = true })
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", listWheel)
	list:SetScript("OnSizeChanged", listSizeChanged)
	list:Layout()
	return list
end

-- Window --------------------------------------------------------------------------
--
-- opts:
--   name      global frame name (needed for Escape); must start with the addon name
--   title     title bar text
--   width, height
--   position  optional saved table; the window remembers where it was dragged
--   onShow    function(window)
--   onHide    function(window, reason): reason "host" when it closed because the frame it was
--             docked to closed, a reason passed to window:Close(reason), else "user"
--
-- Floating, the window can be dragged and closes with Escape. Docked (window:DockTo(frame)),
-- it sits to the right of that frame, follows it, closes with it, and Escape is left to that
-- frame, so Escape closes both together instead of just the window.

local function setEscapeCloses(name, on)
	if not name then return end
	local list = UISpecialFrames
	for i = #list, 1, -1 do
		if list[i] == name then table.remove(list, i) end
	end
	if on then tinsert(list, name) end
end

local Window = {}

function Window:SetTitleText(text)
	self.title:SetText(text or "")
end

function Window:IsDocked()
	return self.dockTarget ~= nil
end

-- Floats the window at its remembered position (or the screen center).
function Window:Float()
	self:ClearAllPoints()
	local p = self.position
	if p and p.point then
		self:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x or 0, p.y or 0)
	else
		self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	self:SetHeight(self.defaultHeight)
	self.dockTarget = nil
	setEscapeCloses(self.opts.name, true)
end

-- Docks to the right of target. o: x, y offsets (default 2, 0), matchHeight (default true),
-- minHeight. Returns false when target is missing or hidden.
function Window:DockTo(target, o)
	o = o or {}
	if not (target and target:IsShown()) then return false end
	self:ClearAllPoints()
	self:SetPoint("TOPLEFT", target, "TOPRIGHT", o.x or 2, o.y or 0)
	if o.matchHeight ~= false then
		self:SetHeight(math.max(o.minHeight or 200, target:GetHeight() or self.defaultHeight))
	end
	self.dockTarget = target
	setEscapeCloses(self.opts.name, false)
	self.hooked = self.hooked or {}
	if not self.hooked[target] then
		self.hooked[target] = true
		local window = self
		target:HookScript("OnHide", guard("dock host hide", function()
			if window.dockTarget == target and window:IsShown() then window:Close("host") end
		end))
	end
	return true
end

function Window:Close(reason)
	self.hideReason = reason
	self:Hide()
	self.hideReason = nil
end

function Window:Toggle()
	if self:IsShown() then self:Close("user") else self:Show() end
end

-- Footer line along the bottom, stopping short of the signature. Created on first use.
function Window:Footer()
	if self.footer then return self.footer end
	local fs = UI.Text(self, "muted", "LEFT")
	fs:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", S.pad, 12)
	if self.signature then
		fs:SetPoint("RIGHT", self.signature, "LEFT", -10, 0)
	else
		fs:SetPoint("RIGHT", self, "RIGHT", -S.pad, 0)
	end
	self.footer = fs
	return fs
end

local function windowDragStart(self)
	if not self.dockTarget then self:StartMoving() end
end

local function windowDragStop(self)
	self:StopMovingOrSizing()
	if self.position and not self.dockTarget then
		local point, _, relativePoint, x, y = self:GetPoint(1)
		self.position.point, self.position.relativePoint = point, relativePoint
		self.position.x, self.position.y = x, y
	end
end

local function windowShow(self)
	if self.opts.onShow then self.opts.onShow(self) end
end

local function windowHide(self)
	if self.opts.onHide then self.opts.onHide(self, self.hideReason or "user") end
end

-- Signature: accent line along the top of the content area (the template's inset when it has
-- one, so it follows the template's geometry) and the wordmark bottom right.
local function addSignature(w)
	local sig = UI.Signature or {}
	if sig.line then
		local line = w:CreateTexture(nil, "ARTWORK")
		local r, g, b = UI.RGB(sig.color or "accent")
		line:SetColorTexture(r, g, b, sig.lineAlpha or 0.55)
		line:SetHeight(sig.lineHeight or 1)
		if w.Inset then
			line:SetPoint("TOPLEFT", w.Inset, "TOPLEFT", 2, -1)
			line:SetPoint("TOPRIGHT", w.Inset, "TOPRIGHT", -2, -1)
		else
			line:SetPoint("TOPLEFT", w, "TOPLEFT", 6, -24)
			line:SetPoint("TOPRIGHT", w, "TOPRIGHT", -6, -24)
		end
		w.signatureLine = line
	end
	if sig.text then
		local mark = UI.Text(w, "muted", "RIGHT")
		mark:SetText(UI.Color(sig.text, sig.color or "accent"))
		mark:SetAlpha(sig.alpha or 0.45)
		mark:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -S.pad, 12)
		w.signature = mark
	end
end

-- Build windows when they first open, not at load, so an unused window costs nothing.
function UI.Window(opts)
	opts = opts or {}
	if opts.name and opts.name:sub(1, #ADDON) ~= ADDON then
		error("PluvasUI: window name " .. opts.name .. " must start with " .. ADDON, 2)
	end
	local w = mix(CreateFrame("Frame", opts.name, UIParent, UI.Templates.window), Window)
	w.opts = opts
	w.defaultHeight = opts.height or 400
	w.position = opts.position
	w:SetSize(opts.width or 400, w.defaultHeight)
	w:SetFrameStrata("MEDIUM")
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:Hide()

	w.title = w.TitleText or UI.Text(w, "title", "CENTER")
	if not w.TitleText then w.title:SetPoint("TOP", w, "TOP", 0, -5) end
	w.title:SetText(opts.title or "")
	addSignature(w)

	w:SetScript("OnDragStart", windowDragStart)
	w:SetScript("OnDragStop", windowDragStop)
	w:SetScript("OnShow", windowShow)
	w:SetScript("OnHide", windowHide)
	w:Float()
	return w
end
