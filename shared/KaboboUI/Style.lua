-- KaboboUI: the shared look of every Kabobo addon (style tokens).
--
-- Edit this library only in shared/KaboboUI, then run `npm run sync`: every addon embeds its own
-- copy under Libs/KaboboUI, and `npm test` fails when a copy drifts. Each copy attaches to its
-- addon's namespace (ns.KaboboUI) and creates no globals, so addons never share or clash.
--
-- Addon code takes colors, fonts, sizes and templates from here instead of hard-coding them, so
-- a restyle is a change to this file.
local ADDON, ns = ...
local UI = {}
ns.KaboboUI = UI
UI.addon = ADDON

-- Colors as hex RRGGBB. Use UI.Color(text, key) for text and UI.RGB(key) for r, g, b.
UI.Colors = {
	accent = "22b8cf", -- Kabobo blue: chat prefix, labels of values
	gold = "ffd200",   -- headings and group headers (Blizzard's normal font color)
	text = "ffffff",
	soft = "d9d9d9",   -- secondary lines
	muted = "808080",  -- hints, disabled, "no data"
	good = "40d040",   -- available, profit
	bad = "ff5050",    -- missing requirement, loss
	warn = "ffa030",   -- data that may be out of date (old AH prices)
}

-- Font objects by role.
UI.Fonts = {
	title = "GameFontHighlight",
	heading = "GameFontNormal",
	label = "GameFontNormalSmall",
	body = "GameFontHighlightSmall",
	muted = "GameFontDisableSmall",
	bar = "TextStatusBarText", -- text drawn on Blizzard's status bars (experience, reputation)
}

-- Spacing and sizes in pixels.
UI.Sizes = {
	pad = 14,        -- inner padding of a window
	contentTop = 30, -- first content line below a window's title bar
	gap = 4,         -- between buttons and tabs
	row = 18,        -- list row height
	icon = 16,       -- icon in a list row
	button = 22,     -- button height
	tab = 20,        -- tab height
}

-- Blizzard templates used for the frame look.
UI.Templates = {
	window = "BasicFrameTemplateWithInset",
	button = "UIPanelButtonTemplate",
}

-- The Kabobo signature on every window: a thin accent line under the title bar and a faded
-- wordmark in the bottom-right corner. Kept slight on purpose; set line/text to false to drop.
UI.Signature = {
	text = "Kabobo",
	color = "accent",
	alpha = 0.45,      -- wordmark
	line = true,
	lineAlpha = 0.55,
	lineHeight = 1,
}

-- Money (gold, silver, copper): Blizzard's coin colors and icons. Used by UI.Money/MoneyIcons.
UI.Coins = {
	colors = { "ffd700", "c7c7cf", "eda55f" },
	letters = { "g", "s", "c" },
	icons = {
		"Interface\\MoneyFrame\\UI-GoldIcon",
		"Interface\\MoneyFrame\\UI-SilverIcon",
		"Interface\\MoneyFrame\\UI-CopperIcon",
	},
}

UI.Textures = {
	rowHighlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
	unknownIcon = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local function hex(color)
	return UI.Colors[color] or color
end

-- "|cffRRGGBBtext|r". color is a key of UI.Colors or a hex RRGGBB string.
function UI.Color(text, color)
	return "|cff" .. hex(color) .. tostring(text) .. "|r"
end

-- r, g, b (0..1) for a key of UI.Colors or a hex RRGGBB string.
function UI.RGB(color)
	local h = hex(color)
	return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end

-- Chat prefix "Addon Title:" in the accent color, for ns:Print.
function UI.Prefix(title)
	return UI.Color(title, "accent") .. ":"
end
