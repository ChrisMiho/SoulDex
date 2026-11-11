-- Settings defaults and slash-command parsing (pure; no WoW API).
local _, ns = ...

local Settings = {}
ns.Settings = Settings

Settings.DEFAULTS = { popup = true, sound = true, announce = true }

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
