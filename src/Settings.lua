-- Settings defaults and slash-command parsing (pure; no WoW API).
local _, ns = ...

local Settings = {}
ns.Settings = Settings

-- chatter: a chat line in the warlock's voice for every claim; off unless asked for.
-- popupScale: the size of the new-soul and rank-up popups (a scale, see Settings.scale).
Settings.DEFAULTS = { popup = true, sound = true, announce = true, chatter = false, popupScale = 1 }

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

-- A scale as the options show it: 1.1 -> "110%".
function Settings.percent(scale)
	return math.floor(scale * 100 + 0.5) .. "%"
end

-- Returns a new table with every default key present: switches that are no boolean and
-- scales that are no usable number fall back to the default.
function Settings.normalise(t)
	local result = {}
	for key, default in pairs(Settings.DEFAULTS) do
		local value = nil
		if type(t) == "table" then
			value = t[key]
		end
		if type(default) == "number" then
			result[key] = Settings.scale(value) or default
		elseif type(value) == "boolean" then
			result[key] = value
		else
			result[key] = default
		end
	end
	return result
end

-- "" -> toggle, "options" -> options, "add <name>" / "remove <name>" -> add/remove + name, else help.
function Settings.parseCommand(msg)
	msg = (msg or ""):match("^%s*(.-)%s*$")
	if msg == "" then
		return "toggle"
	end
	local word, rest = msg:match("^(%S+)%s*(.*)$")
	word = word:lower()
	if word == "options" and rest == "" then
		return "options"
	end
	if (word == "add" or word == "remove") and rest ~= "" then
		return word, rest
	end
	return "help"
end
