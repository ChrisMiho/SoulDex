-- Colour themes for the window, the popups and the rank emblems (pure; no WoW API).
-- Every theme names the same slots; UIFormat.COLORS is filled from the active one
-- (UIFormat.applyTheme) and the painting helpers repaint by slot name (src/UIList.lua).
-- Rarity and class colours are not here: they mean the same in every theme.
-- Spec: docs/superpowers/specs/2026-11-18-themes-design.md.
local _, ns = ...

local Themes = {}
ns.Themes = Themes

Themes.DEFAULT = "soulshard"

-- The slots every theme defines, as hex "rrggbb".
Themes.SLOTS = {
	"TEXT", "WHITE", "TITLE", "MUTED", "HEADER", "UNKNOWN", "DIM", "FLAVOUR", "GOOD", "ACCENT",
	"BG", "PANE_BG", "SHADE_TOP", "SHADE_BOTTOM", "BORDER", "DIVIDER", "TAB_BG", "BUTTON_EDGE",
	"TRACK", "SELECTED", "HOVER", "ROW_LINE", "TILE_BG", "TILE_EDGE", "QUOTE_BAR", "CHIP_BG", "CHIP_EDGE",
}

-- In the order the options step through them. Soul Shard is the branding look.
Themes.LIST = {
	{
		id = "soulshard",
		name = "Soul Shard",
		colors = {
			TEXT = "e8e0f0", WHITE = "ffffff", TITLE = "c9a8ff", MUTED = "9a8fb0", HEADER = "8a72b8",
			UNKNOWN = "4d4360", DIM = "6e6385", FLAVOUR = "b9a6d9", GOOD = "7dff6a", ACCENT = "9dff3a",
			BG = "14101c", PANE_BG = "0d0a14", SHADE_TOP = "241835", SHADE_BOTTOM = "0b0812",
			BORDER = "6b4fa0", DIVIDER = "3d2d5c", TAB_BG = "251b36", BUTTON_EDGE = "5a4486",
			TRACK = "2d2240", SELECTED = "3a2a55", HOVER = "2a2040", ROW_LINE = "1d1629",
			TILE_BG = "151020", TILE_EDGE = "231a35", QUOTE_BAR = "4a3470", CHIP_BG = "0a1404",
			CHIP_EDGE = "3d6b1f",
		},
	},
	{
		id = "fel",
		name = "Fel",
		colors = {
			TEXT = "e4f0dc", WHITE = "ffffff", TITLE = "b8f07a", MUTED = "94a886", HEADER = "76a050",
			UNKNOWN = "3e4d34", DIM = "66785a", FLAVOUR = "a9c890", GOOD = "7dff6a", ACCENT = "ccff33",
			BG = "0f140b", PANE_BG = "0a0e07", SHADE_TOP = "1a2612", SHADE_BOTTOM = "060904",
			BORDER = "4f8a2a", DIVIDER = "2d4a1c", TAB_BG = "1a2a12", BUTTON_EDGE = "437a24",
			TRACK = "22351a", SELECTED = "2c4a1e", HOVER = "1f3216", ROW_LINE = "141f0e",
			TILE_BG = "111a0c", TILE_EDGE = "1e2e15", QUOTE_BAR = "3a6324", CHIP_BG = "0a1404",
			CHIP_EDGE = "5f8f1f",
		},
	},
	{
		id = "shadow",
		name = "Shadow",
		colors = {
			TEXT = "e0e0f5", WHITE = "ffffff", TITLE = "a9b4ff", MUTED = "8c8cb0", HEADER = "6e74b8",
			UNKNOWN = "3e3e5c", DIM = "5f5f85", FLAVOUR = "a3a8d9", GOOD = "8ad8ff", ACCENT = "c18cff",
			BG = "0c0c18", PANE_BG = "08080f", SHADE_TOP = "181a33", SHADE_BOTTOM = "050509",
			BORDER = "4b4a8f", DIVIDER = "2a2a52", TAB_BG = "17172e", BUTTON_EDGE = "3f3e7a",
			TRACK = "1f1f3d", SELECTED = "2a2a55", HOVER = "1c1c38", ROW_LINE = "121224",
			TILE_BG = "0f0f1f", TILE_EDGE = "1c1c36", QUOTE_BAR = "34336b", CHIP_BG = "120f26",
			CHIP_EDGE = "4a3d8f",
		},
	},
	{
		id = "ember",
		name = "Ember",
		colors = {
			TEXT = "f2e4dc", WHITE = "ffffff", TITLE = "ffb08a", MUTED = "b09a8f", HEADER = "c06a50",
			UNKNOWN = "5c3e36", DIM = "85665c", FLAVOUR = "d9b4a3", GOOD = "ffe9a8", ACCENT = "ff7a1a",
			BG = "160d0b", PANE_BG = "0e0807", SHADE_TOP = "2e1410", SHADE_BOTTOM = "090504",
			BORDER = "9a3022", DIVIDER = "4f1d16", TAB_BG = "2a1410", BUTTON_EDGE = "7f2a1d",
			TRACK = "351a14", SELECTED = "52221a", HOVER = "3a1913", ROW_LINE = "1f100c",
			TILE_BG = "1a0f0c", TILE_EDGE = "301a14", QUOTE_BAR = "6b2a1c", CHIP_BG = "1f0e04",
			CHIP_EDGE = "7a3d12",
		},
	},
}

local BY_ID = {}
for index, theme in ipairs(Themes.LIST) do
	theme.index = index
	BY_ID[theme.id] = theme
end

-- The theme in use (UIFormat.applyTheme sets it); Ranks.emblem reads it.
Themes.current = Themes.DEFAULT

-- A known theme id from anything saved: the value itself, else the default.
function Themes.id(value)
	if type(value) == "string" and BY_ID[value] then
		return value
	end
	return Themes.DEFAULT
end

local function theme(id)
	return BY_ID[Themes.id(id)]
end

-- The slot -> hex table of a theme (the default's for an unknown id). Read only.
function Themes.palette(id)
	return theme(id).colors
end

-- The name the options show.
function Themes.name(id)
	return theme(id).name
end

-- The theme `by` steps (1 or -1) from id, wrapping round the list.
function Themes.next(id, by)
	local count = #Themes.LIST
	local index = (theme(id).index - 1 + (by or 1)) % count + 1
	return Themes.LIST[index].id
end

-- Where a theme's rank emblems sit under art\: Soul Shard's at the top, the others in
-- a folder named after the theme.
function Themes.emblemDir(id)
	id = Themes.id(id)
	if id == Themes.DEFAULT then
		return ""
	end
	return id .. "\\"
end
