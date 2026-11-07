-- PluvasUI: a scrolling list of rows (icon rows or columns).
--
-- The list fills its own height with rows and scrolls with the mouse wheel. Rows are created the
-- first time they need to show and then reused; update(row, item) fills only the visible ones.
--
-- opts:
--   kind        "icon" (icon, text, right text; the default) or "columns"
--   columns     for "columns": { { width = 90, justify = "LEFT", font = "body" }, ... }
--   headers     for "columns": true to reserve a header line on top (list:SetHeaders(...))
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
-- list:SetItems(items, keepOffset), list:Refresh(), list:Scroll(rows), list:ScrollToTop(),
-- list:Range() -> first, last, total, list:SetEmptyText(text), list:SetHeaders(...).
-- The empty text shows below the last visible row.
local _, ns = ...
local UI = ns.PluvasUI
local S = UI.Sizes

local COLUMN_GAP = 6

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

-- Font strings laid out along the columns, for column rows and the header line.
local function columnCells(parent, columns, font, anchor)
	local cells, x = {}, 0
	for c, col in ipairs(columns) do
		local cell = UI.Text(parent, font or col.font or "body", col.justify)
		cell:SetWidth(col.width)
		cell:SetPoint(anchor, parent, anchor, x, 0)
		cells[c] = cell
		x = x + col.width + COLUMN_GAP
	end
	return cells
end

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
	row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.top - (i - 1) * height)
	row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
	row:SetHighlightTexture(UI.Textures.rowHighlight, "ADD")
	if opts.kind == "columns" then
		row.cells = columnCells(row, opts.columns or {}, nil, "LEFT")
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
	local fit = math.floor(((self:GetHeight() or 0) - self.top) / self.rowHeight)
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
	self.empty:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -self.top - (shown + 1) * self.rowHeight)
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

function List:ScrollToTop()
	self:Scroll(-self.offset)
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

-- Header text per column, for a "columns" list made with headers = true.
function List:SetHeaders(...)
	for i, cell in ipairs(self.headers) do setText(cell, (select(i, ...))) end
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
	local list = UI.Mixin(CreateFrame("Frame", nil, parent), List)
	list.opts = opts
	list.rowHeight = opts.rowHeight or S.row
	list.maxRows = opts.maxRows or 40
	local columns = opts.kind == "columns"
	list.top = 0
	if columns and opts.headers then
		list.header = CreateFrame("Frame", nil, list)
		list.header:SetHeight(list.rowHeight)
		list.header:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
		list.header:SetPoint("RIGHT", list, "RIGHT", 0, 0)
		list.headers = columnCells(list.header, opts.columns or {}, "label", "LEFT")
		list.top = list.rowHeight
	end
	list.headers = list.headers or {}
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
