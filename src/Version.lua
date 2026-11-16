-- Version strings: parsing and comparing "v1.4.0" and "1.4.0-beta.1" (pure; no WoW API).
-- Used for the "a newer SoulDex is out" notice (src/Net.lua).
local _, ns = ...

local Version = {}
ns.Version = Version

local MAX_PART = 9999 -- anything larger is junk (or a prank), not a version

-- { major, minor, patch, pre, preNum } or nil. pre is the prerelease word in lower case
-- ("beta", "alpha", ...) with preNum its number (0 when missing); a release has neither.
-- Strict: "dev", an empty string, extra text or huge numbers give nil.
function Version.parse(text)
	if type(text) ~= "string" or #text > 32 then
		return nil
	end
	local major, minor, patch, rest = text:match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
	if not major then
		return nil
	end
	local v = { major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch) }
	if v.major > MAX_PART or v.minor > MAX_PART or v.patch > MAX_PART then
		return nil
	end
	if rest ~= "" then
		local pre, num = rest:match("^%-(%a+)%.?(%d*)$")
		if not pre or #num > 4 then
			return nil
		end
		v.pre = pre:lower()
		v.preNum = tonumber(num) or 0
	end
	return v
end

-- -1, 0 or 1 for a before, equal to or after b (both parsed). A prerelease comes before
-- its release; two prereleases go by word ("alpha" < "beta"), then by number.
function Version.compare(a, b)
	for _, key in ipairs({ "major", "minor", "patch" }) do
		if a[key] ~= b[key] then
			return a[key] < b[key] and -1 or 1
		end
	end
	if a.pre == b.pre then
		local x, y = a.preNum or 0, b.preNum or 0
		return x == y and 0 or (x < y and -1 or 1)
	end
	if not a.pre then
		return 1
	end
	if not b.pre then
		return -1
	end
	return a.pre < b.pre and -1 or 1
end

-- Whether `theirs` is a newer version than `mine` and worth telling the player about.
-- An unreadable version on either side is never newer. A prerelease is only worth
-- telling someone who runs a prerelease themself: release players hear of releases.
function Version.isNewer(theirs, mine)
	local a, b = Version.parse(theirs), Version.parse(mine)
	if not a or not b then
		return false
	end
	if a.pre and not b.pre then
		return false
	end
	return Version.compare(a, b) > 0
end

-- "v1.4.0" for display, whatever form came in; nil for an unreadable version.
function Version.display(text)
	if not Version.parse(text) then
		return nil
	end
	return text:find("^v") and text or ("v" .. text)
end
