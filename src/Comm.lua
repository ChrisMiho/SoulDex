-- The friend wire format: encode and decode summaries, requests and full dex
-- dumps (pure; no WoW API). Fields are tab-separated, records newline-separated.
local _, ns = ...

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "SoulDex"
Comm.VERSION = 1

local TAB = "\t"

-- Split on tab keeping empty fields.
local function split(str, sep)
	local out, from = {}, 1
	while true do
		local i = str:find(sep, from, true)
		if not i then
			out[#out + 1] = str:sub(from)
			return out
		end
		out[#out + 1] = str:sub(from, i - 1)
		from = i + #sep
	end
end

local function clean(value)
	if value == nil then
		return ""
	end
	return (tostring(value):gsub("[\t\n\r|]", ""))
end

local function int(n)
	return string.format("%d", math.floor(tonumber(n) or 0))
end

-- Strict decimal integer, or nil.
local function parseInt(s)
	if type(s) ~= "string" or not s:match("^%-?%d+$") then
		return nil
	end
	return tonumber(s)
end

local function nilIfEmpty(s)
	if s == "" then
		return nil
	end
	return s
end

-- A decoded text field: cleaned, and nil when empty.
local function text(s)
	return nilIfEmpty(clean(s))
end

local function versionOk(field)
	return parseInt(field) == Comm.VERSION
end

function Comm.encodeSummary(s)
	return table.concat({ "S", int(Comm.VERSION), int(s.score), int(s.mobs), int(s.players), int(s.raids) }, TAB)
end

function Comm.decodeSummary(str)
	if type(str) ~= "string" then
		return nil
	end
	local f = split(str, TAB)
	if #f ~= 6 or f[1] ~= "S" or not versionOk(f[2]) then
		return nil
	end
	local score, mobs, players, raids = parseInt(f[3]), parseInt(f[4]), parseInt(f[5]), parseInt(f[6])
	if not (score and mobs and players and raids) then
		return nil
	end
	return { score = score, mobs = mobs, players = players, raids = raids }
end

-- kind: "Q" (ask for a summary) or "R" (ask for the full dex).
function Comm.encodeRequest(kind)
	if kind ~= "Q" and kind ~= "R" then
		return nil
	end
	return kind .. TAB .. int(Comm.VERSION)
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

function Comm.encodeDex(db)
	local lines = { "D" .. TAB .. int(Comm.VERSION) }
	local places = db.places or {}
	local mobs = db.mobs or {}
	for _, key in ipairs(sortedKeys(mobs)) do
		local m = mobs[key]
		local head = {
			"M", clean(m.name or key), clean(m.classification), clean(m.creatureType), clean(m.family),
			int(m.minLevel), int(m.maxLevel), int(m.points),
		}
		local zones = sortedKeys(m.places or {})
		if #zones == 0 then
			zones = { false }
		end
		for _, zone in ipairs(zones) do
			local line = { unpack(head) }
			if zone then
				line[#line + 1] = clean(zone)
				line[#line + 1] = clean((places[zone] or {}).group)
				line[#line + 1] = int(m.places[zone].count)
			else
				line[#line + 1] = ""
				line[#line + 1] = ""
				line[#line + 1] = "0"
			end
			lines[#lines + 1] = table.concat(line, TAB)
		end
	end
	local players = db.players or {}
	for _, key in ipairs(sortedKeys(players)) do
		local p = players[key]
		lines[#lines + 1] = table.concat({
			"P", clean(key), clean(p.name), clean(p.class), clean(p.race), int(p.count), int(p.points),
		}, TAB)
	end
	local raids = db.raids or {}
	for _, id in ipairs(sortedKeys(raids)) do
		local r = raids[id]
		lines[#lines + 1] = table.concat({
			"X", int(id), int(r.instanceID), clean(r.name), int(r.count), int(r.points), r.known and "1" or "0",
		}, TAB)
	end
	return table.concat(lines, "\n")
end

local function decodeMob(f, db)
	if #f ~= 11 then
		return false
	end
	local minLevel, maxLevel, points, count = parseInt(f[6]), parseInt(f[7]), parseInt(f[8]), parseInt(f[11])
	local name = text(f[2])
	if not name or not (minLevel and maxLevel and points and count) then
		return false
	end
	local entry = db.mobs[name]
	if not entry then
		entry = {
			name = name,
			classification = text(f[3]),
			creatureType = text(f[4]),
			family = text(f[5]),
			minLevel = minLevel ~= 0 and minLevel or nil,
			maxLevel = maxLevel ~= 0 and maxLevel or nil,
			points = points,
			places = {},
		}
		db.mobs[name] = entry
	end
	local zone = text(f[9])
	if zone then
		entry.places[zone] = { count = count }
		if not db.places[zone] then
			db.places[zone] = { group = text(f[10]) }
		end
	end
	return true
end

local function decodePlayer(f, db)
	if #f ~= 7 then
		return false
	end
	local count, points = parseInt(f[6]), parseInt(f[7])
	local key, name = text(f[2]), text(f[3])
	if not key or not name or not (count and points) then
		return false
	end
	db.players[key] = {
		name = name,
		class = text(f[4]),
		race = text(f[5]),
		count = count,
		points = points,
		places = {},
	}
	return true
end

local function decodeRaid(f, db)
	if #f ~= 7 then
		return false
	end
	local npcID, instanceID, count, points = parseInt(f[2]), parseInt(f[3]), parseInt(f[5]), parseInt(f[6])
	local name = text(f[4])
	if not name or not (npcID and instanceID and count and points) or (f[7] ~= "0" and f[7] ~= "1") then
		return false
	end
	db.raids[npcID] = {
		name = name,
		instanceID = instanceID,
		count = count,
		points = points,
		known = f[7] == "1",
	}
	return true
end

local decoders = { M = decodeMob, P = decodePlayer, X = decodeRaid }

function Comm.decodeDex(str)
	if type(str) ~= "string" then
		return nil
	end
	local lines = split(str, "\n")
	local head = split(lines[1], TAB)
	if #head ~= 2 or head[1] ~= "D" or not versionOk(head[2]) then
		return nil
	end
	local db = { mobs = {}, places = {}, players = {}, raids = {} }
	for i = 2, #lines do
		local f = split(lines[i], TAB)
		local decode = decoders[f[1]]
		if not decode or not decode(f, db) then
			return nil
		end
	end
	return db
end

-- Returns the message type and its payload, or nil for anything unrecognised.
-- "S" -> summary table, "Q"/"R" -> true, "D" -> decoded dex.
function Comm.decode(str)
	if type(str) ~= "string" then
		return nil
	end
	local kind = str:sub(1, 1)
	if kind == "S" then
		local s = Comm.decodeSummary(str)
		if s then
			return "S", s
		end
	elseif kind == "Q" or kind == "R" then
		local f = split(str, TAB)
		if #f == 2 and f[1] == kind and versionOk(f[2]) then
			return kind, true
		end
	elseif kind == "D" then
		local db = Comm.decodeDex(str)
		if db then
			return "D", db
		end
	end
	return nil
end
