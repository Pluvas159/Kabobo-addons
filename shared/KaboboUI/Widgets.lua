-- KaboboUI: small widgets built on the style tokens in Style.lua.
--
--   UI.Text(parent, font, justify, opts)       font string
--   UI.ShowTooltip / UI.SetTooltip             tooltips from a title and lines
--   UI.AddTooltipLines(tooltip, lines)         label/value lines in an existing tooltip
--   UI.Button(parent, opts)                    standard button
--   UI.SetSelected(button, on)                 mark the selected button of a group
--   UI.TabBar(parent, opts)                    row of buttons, one selected
--   UI.Grid(parent, opts)                      table of values with row and column labels
--   UI.LinePanel(parent, opts)                 stack of label/value lines inside another frame
--
-- List.lua has UI.List, Window.lua has UI.Window.
--
-- Lightweight by design: widgets share one set of methods and scripts (no closures per
-- instance) and nothing runs per frame. See shared/KaboboUI/README.md for the rules.
local _, ns = ...
local UI = ns.KaboboUI
local S = UI.Sizes

-- Copies shared methods onto a frame.
function UI.Mixin(target, methods)
	for k, v in pairs(methods) do target[k] = v end
	return target
end

-- Callbacks run inside Blizzard script chains, so contain their errors when the addon has
-- KaboboCore's ns:Guard.
function UI.Guard(name, fn)
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
	local t = self.kaboboTooltip
	local title, lines = t.title, t.lines
	if type(title) == "function" then title = title(self) end
	if type(lines) == "function" then lines = lines(self) end
	UI.ShowTooltip(self, title, lines)
end

-- title and lines can be functions(frame), for tooltips that change.
function UI.SetTooltip(frame, title, lines)
	frame.kaboboTooltip = { title = title, lines = lines }
	frame:SetScript("OnEnter", tooltipEnter)
	frame:SetScript("OnLeave", UI.HideTooltip)
end

-- Label/value lines -----------------------------------------------------------------
--
-- Item tooltips and info panels share one line format, so both look the same:
--   { "Label", "value" }                     label in the accent color, value white
--   { "   detail", "value", color = "soft" } any UI.Colors key for the label
-- Values carry their own color codes (UI.Color, UI.MoneyIcons).

function UI.AddTooltipLines(tooltip, lines)
	for _, line in ipairs(lines) do
		local r, g, b = UI.RGB(line.color or "accent")
		tooltip:AddDoubleLine(line[1], line[2] or " ", r, g, b, 1, 1, 1)
	end
end

local LinePanel = {}

-- Font strings are made on demand, since the number of lines varies.
function LinePanel:Line(i)
	if not self.labels[i] then
		local y = -(i - 1) * self.lineHeight
		local l = UI.Text(self, "body", "LEFT")
		l:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
		local v = UI.Text(self, "body", "RIGHT")
		v:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, y)
		self.labels[i], self.values[i] = l, v
	end
	return self.labels[i], self.values[i]
end

-- Shows the lines and sizes the panel to them.
function LinePanel:SetLines(lines)
	for i, line in ipairs(lines) do
		local l, v = self:Line(i)
		l:SetText(UI.Color(line[1], line.color or "accent"))
		v:SetText(line[2] or "")
		l:Show()
		v:Show()
	end
	for i = #lines + 1, #self.labels do
		self.labels[i]:Hide()
		self.values[i]:Hide()
	end
	self:SetHeight(math.max(1, #lines) * self.lineHeight)
end

-- opts: width (default 250), lineHeight (default 14). Starts hidden.
function UI.LinePanel(parent, opts)
	opts = opts or {}
	local panel = UI.Mixin(CreateFrame("Frame", nil, parent), LinePanel)
	panel.lineHeight = opts.lineHeight or 14
	panel.labels, panel.values = {}, {}
	panel:SetSize(opts.width or 250, panel.lineHeight)
	panel:Hide()
	return panel
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
	if opts.onClick then b:SetScript("OnClick", UI.Guard((opts.name or "button") .. " click", opts.onClick)) end
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
	local bar = UI.Mixin(CreateFrame("Frame", nil, parent), TabBar)
	bar.opts = opts or {}
	bar:SetSize(bar.opts.width or 300, bar.opts.height or S.tab)
	bar.buttons = {}
	bar.click = UI.Guard("tab click", tabClick)
	return bar
end

-- Grid ----------------------------------------------------------------------------
--
-- A table of right-aligned values: column headings on top (gold), row labels on the left.
-- opts: columns = { "Today", ... }, rows = { "Sales", ... }, labelWidth (default 100),
-- cellWidth (default 115), gap between cells (default 5).
-- grid:Set(row, column, text). The grid sizes itself; anchor it by its TOPLEFT.

local Grid = {}

function Grid:Set(row, column, text)
	self.cells[row][column]:SetText(text or "")
end

function UI.Grid(parent, opts)
	local grid = UI.Mixin(CreateFrame("Frame", nil, parent), Grid)
	local labelWidth, cellWidth, gap = opts.labelWidth or 100, opts.cellWidth or 115, opts.gap or 5
	local headingGap = 6
	local function x(c) return labelWidth + (c - 1) * (cellWidth + gap) end
	for c, text in ipairs(opts.columns) do
		local h = UI.Text(grid, "heading", "RIGHT")
		h:SetWidth(cellWidth)
		h:SetPoint("TOPLEFT", grid, "TOPLEFT", x(c), 0)
		h:SetText(text)
	end
	grid.cells = {}
	for r, text in ipairs(opts.rows) do
		local y = -headingGap - r * S.row
		local l = UI.Text(grid, "label")
		l:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, y)
		l:SetText(text)
		grid.cells[r] = {}
		for c = 1, #opts.columns do
			local cell = UI.Text(grid, "body", "RIGHT")
			cell:SetWidth(cellWidth)
			cell:SetPoint("TOPLEFT", grid, "TOPLEFT", x(c), y)
			grid.cells[r][c] = cell
		end
	end
	grid:SetSize(x(#opts.columns + 1) - gap, headingGap + (#opts.rows + 1) * S.row)
	return grid
end
