-- Rarity colours and labels, and class colours as hex (pure; no WoW API). One table for
-- the window, the popup and the shard tooltip, so a soul looks the same everywhere.
-- Colours are hex "rrggbb", as settled in the mockups (spec section 5).
local _, ns = ...

local Rarity = {}
ns.Rarity = Rarity

Rarity.ELITE = "ffd25a"
Rarity.RARE = "c0c0c0"
Rarity.BOSS = "ff9a5a"

local STYLES = {
	elite = { color = Rarity.ELITE, label = "Elite" },
	rareelite = { color = Rarity.RARE, label = "Rare Elite" },
	rare = { color = Rarity.RARE, label = "Rare" },
	worldboss = { color = Rarity.BOSS, label = "Boss" },
}

-- Hex colour for a classification, or nil for ordinary mobs.
function Rarity.color(classification)
	local style = STYLES[classification]
	return style and style.color
end

-- "Elite" / "Rare" / "Rare Elite" / "Boss", or nil for ordinary mobs.
function Rarity.label(classification)
	local style = STYLES[classification]
	return style and style.label
end

-- Hex class colour from RAID_CLASS_COLORS (or nil).
function Rarity.classHex(class, classColors)
	local c = class and classColors and classColors[class]
	if not c then
		return nil
	end
	local function byte(v)
		return math.floor(v * 255 + 0.5)
	end
	return string.format("%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
end
