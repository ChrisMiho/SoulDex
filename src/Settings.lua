-- Settings defaults and slash-command parsing (pure; no WoW API).
local _, ns = ...

local Settings = {}
ns.Settings = Settings

-- greeting: the "loaded" chat line after each login and /reload.
-- unitTooltip: the "Soul collected" line on a caught creature's or player's tooltip
-- (spec 6.3a).
-- popupScale: the size of the new-soul and rank-up popups (a scale, see Settings.scale).
-- theme: the colour theme of the window and popups (an id from ns.Themes).
Settings.DEFAULTS = {
	popup = true, sound = true, announce = true, greeting = true,
	unitTooltip = true, popupScale = 1, theme = "soulshard",
}

-- The sizes of the window and the popups: the limits, the step of the options' - and +
-- buttons, the default.
Settings.SCALE_MIN, Settings.SCALE_MAX, Settings.SCALE_STEP, Settings.SCALE_DEFAULT = 0.6, 1.6, 0.1, 1

-- A usable scale from anything: a number or numeric text, in percent ("120") or as a
-- factor ("1.2"), rounded to the nearest 5% and kept within the limits. nil when it is
-- no number at all.
function Settings.scale(value)
	local n = tonumber(type(value) == "string" and value:match("^%s*(.-)%s*%%?%s*$") or value)
	if not n or n ~= n or n <= 0 then
		return nil
	end
	if n > 10 then
		n = n / 100
	end
	n = math.floor(n * 20 + 0.5) / 20
	return math.max(Settings.SCALE_MIN, math.min(Settings.SCALE_MAX, n))
end

-- The scale while the window's corner is dragged: it grows by the share the corner
-- moved, right and down averaged (w, h: the window's size on screen when the drag
-- began, at scale `from`; dx right, dy down, in the same units). Rounded and kept
-- within the limits like Settings.scale.
function Settings.dragScale(from, w, h, dx, dy)
	if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
		return from
	end
	-- Dragged past the top-left corner: the smallest size (a factor of 0 or less is no scale).
	return Settings.scale(math.max(0.01, from * (1 + (dx / w + dy / h) / 2))) or from
end

-- A scale as the options show it: 1.1 -> "110%".
function Settings.percent(scale)
	return math.floor(scale * 100 + 0.5) .. "%"
end

-- Returns a new table with every default key present: switches that are no boolean,
-- scales that are no usable number and a theme no one knows fall back to the default.
function Settings.normalise(t)
	local result = {}
	for key, default in pairs(Settings.DEFAULTS) do
		local value = nil
		if type(t) == "table" then
			value = t[key]
		end
		if type(default) == "number" then
			result[key] = Settings.scale(value) or default
		elseif type(default) == "string" then
			-- The theme: kept only when ns.Themes knows it.
			result[key] = ns.Themes and ns.Themes.id(value) or default
		elseif type(value) == "boolean" then
			result[key] = value
		else
			result[key] = default
		end
	end
	return result
end

-- Words that are a whole command, and words that need something after them.
local BARE = { options = true, help = true, version = true, reset = true, test = true }
local WITH_ARG = { add = true, remove = true, find = true, scale = true }

-- "" -> toggle; "options", "version", "reset", "test" -> themselves; "add <name>",
-- "remove <name>", "find <text>", "scale <number>" -> the word plus what follows; anything
-- else (a word missing its argument too) -> help.
function Settings.parseCommand(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$")
	if msg == "" then
		return "toggle"
	end
	local word, rest = msg:match("^(%S+)%s*(.*)$")
	word = word:lower()
	if BARE[word] and rest == "" then
		return word
	end
	if WITH_ARG[word] and rest ~= "" then
		return word, rest
	end
	return "help"
end
