-- KaboboUI: a movable window that can dock to another frame, with the Kabobo signature and a
-- footer line.
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
local ADDON, ns = ...
local UI = ns.KaboboUI
local S = UI.Sizes

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

-- Closes the window when the frame it is docked to hides. One hook per host, however often the
-- window docks to it.
local function hookHost(window, target)
	window.hooked = window.hooked or {}
	if window.hooked[target] then return end
	window.hooked[target] = true
	target:HookScript("OnHide", UI.Guard("dock host hide", function()
		if window.dockTarget == target and window:IsShown() then window:Close("host") end
	end))
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
	hookHost(self, target)
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

-- A window that opens comes to the front, so it never shows through another window.
local function windowShow(self)
	if self.Raise then self:Raise() end
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
		error("KaboboUI: window name " .. opts.name .. " must start with " .. ADDON, 2)
	end
	local w = UI.Mixin(CreateFrame("Frame", opts.name, UIParent, UI.Templates.window), Window)
	w.opts = opts
	w.defaultHeight = opts.height or 400
	w.position = opts.position
	w:SetSize(opts.width or 400, w.defaultHeight)
	w:SetFrameStrata("MEDIUM")
	-- Windows in the same strata and level draw through each other; a toplevel window comes
	-- to the front when clicked.
	w:SetToplevel(true)
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
