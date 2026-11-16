-- Settings defaults and slash-command parsing (pure; no WoW API).
local _, ns = ...

local Settings = {}
ns.Settings = Settings

-- chatter: a chat line in the warlock's voice for every claim; off unless asked for.
-- greeting: the "loaded" chat line after each login and /reload.
-- lateAsk: experimental, off unless asked for: a boss drained during its encounter keeps
-- its shard held, and its name is asked for when the fight ends (spec 4.2).
Settings.DEFAULTS = {
	popup = true, sound = true, announce = true, chatter = false, greeting = true, lateAsk = false,
}

-- The window's scale: its limits, the step of the options' - and + buttons, the default.
Settings.SCALE_MIN, Settings.SCALE_MAX, Settings.SCALE_STEP, Settings.SCALE_DEFAULT = 0.6, 1.6, 0.1, 1

-- A usable window scale from anything: a number or numeric text, in percent ("120") or
-- as a factor ("1.2"), rounded to the nearest 5% and kept within the limits. nil when it
-- is no number at all.
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

-- Returns a new table with every default key present; non-booleans fall back to the default.
function Settings.normalise(t)
	local result = {}
	for key, default in pairs(Settings.DEFAULTS) do
		local value = nil
		if type(t) == "table" then
			value = t[key]
		end
		if type(value) == "boolean" then
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
