-- Generates src/RaidData.lua from Questie's Classic Era NPC database.
--
-- Usage:  luajit scripts/gen_raids.lua <path-to-classicNpcDB.lua>
--
-- Source: Questie tag v11.38.0, Database/Classic/classicNpcDB.lua (GPL-3).
-- Only NPC ids, names, raid membership and a boss flag are taken from it.
--
-- The source file is untrusted code. It is never executed: it is read as
-- text, each NPC record line is loaded on its own with an empty environment.
--
-- Record field order (confirmed against the file's npcKeys table):
--   1 name, 4 minLevel, 5 maxLevel, 6 rank (3 = boss),
--   7 spawns {[areaID] = {{x, y}, ...}} (raid spawns appear as {{-1,-1}}),
--   9 zoneID, 13 friendlyToFaction ("A" / "H" / "AH" / nil).
--
-- Kept: NPCs with a spawn in a raid area ID that are hostile to both
-- factions (field 13 is nil) and are not on the exclusion list below.
-- boss = (rank == 3) or the NPC is on the hand-kept boss list below.

local DATE = "2026-11-10"
local SOURCE = "Questie v11.38.0, Database/Classic/classicNpcDB.lua"

-- Display order. areaID is the raid's area ID in the NPC database.
local RAIDS = {
	{ key = "ZG", name = "Zul'Gurub", instanceID = 309, areaID = 1977 },
	{ key = "MC", name = "Molten Core", instanceID = 409, areaID = 2717 },
	{ key = "Onyxia", name = "Onyxia's Lair", instanceID = 249, areaID = 2159 },
	{ key = "BWL", name = "Blackwing Lair", instanceID = 469, areaID = 2677 },
	{ key = "AQ20", name = "Ruins of Ahn'Qiraj", instanceID = 509, areaID = 3429 },
	{ key = "AQ40", name = "Temple of Ahn'Qiraj", instanceID = 531, areaID = 3428 },
	{ key = "Naxx", name = "Naxxramas", instanceID = 533, areaID = 3456 },
}

-- Bosses the spawn filter misses: summoned or scripted-spawn bosses have no
-- spawns and zoneID 0 in the database, and Vaelastrasz is flagged friendly.
-- They are added to the given raid and flagged as bosses.
-- Arlokk (14515) was dropped by the spawn filter for the same reason as
-- Ragnaros: her record has spawns = nil and zoneID 0 (she is scripted).
local HAND_BOSSES = {
	{ id = 11502, raid = "MC" }, -- Ragnaros (summoned)
	{ id = 12018, raid = "MC" }, -- Majordomo Executus (no spawn record)
	{ id = 11583, raid = "BWL" }, -- Nefarian (summoned)
	{ id = 13020, raid = "BWL" }, -- Vaelastrasz the Corrupt (friendly flag)
	{ id = 15517, raid = "AQ40" }, -- Ouro (summoned)
	{ id = 15989, raid = "Naxx" }, -- Sapphiron (no spawn record)
	{ id = 15114, raid = "ZG" }, -- Gahz'ranka (summoned)
	{ id = 14515, raid = "ZG" }, -- High Priestess Arlokk (database record has no spawns and zoneID 0)
	{ id = 15082, raid = "ZG" }, -- Gri'lek (Edge of Madness)
	{ id = 15083, raid = "ZG" }, -- Hazza'rah (Edge of Madness)
	{ id = 15084, raid = "ZG" }, -- Renataki (Edge of Madness)
	{ id = 15085, raid = "ZG" }, -- Wushoolay (Edge of Madness)
}

-- Spawn-filter hits that are not creatures worth recording, with reasons.
-- (Friendly-to-both-factions NPCs such as Lord Victor Nefarius, triggers,
-- critters flagged "AH", Zanza and the AQ40 dragon NPCs are already dropped
-- by the hostile-to-both rule.)
local EXCLUDED = {
	[15957] = "Ouro Spawner: invisible spawn helper",
	[15896] = "C'Thun Portal: scenery object-creature",
	[16218] = "Tesla Coil: Thaddius encounter device",
	[17293] = "Plague Wave: encounter effect",
	[14826] = "Sacrificed Troll: scripted corpse",
	[15514] = "Buru Egg: encounter object",
	[16449] = "Spirit of Naxxramas: ambient spirit",
}

local function readAll(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- Parse the `npcData = [[return { ... }]]` long string line by line.
-- (LuaJIT refuses to load the whole table: too many constants in one chunk.)
local function loadNpcs(path)
	local src = readAll(path)
	local body = src:match("QuestieDB%.npcData = %[%[return {\n(.-)\n}%]%]")
	assert(body, "could not find npcData in " .. path)
	local npcs = {}
	for line in body:gmatch("[^\n]+") do
		local id, rest = line:match("^%[(%d+)%] = (.*),$")
		assert(id, "unexpected line: " .. line:sub(1, 80))
		local chunk = assert(loadstring("return " .. rest))
		setfenv(chunk, {})
		npcs[tonumber(id)] = chunk()
	end
	return npcs
end

local function q(s)
	return string.format("%q", s)
end

local path = arg[1]
assert(path, "usage: luajit scripts/gen_raids.lua <path-to-classicNpcDB.lua>")
local npcs = loadNpcs(path)

-- Field order check: Lucifron is a level 63 rank-3 NPC with a raid spawn.
local sample = npcs[12118]
assert(sample and sample[1] == "Lucifron" and sample[6] == 3 and sample[4] == 63, "unexpected field order")
print(("sample 12118: name=%s level=%d-%d rank=%d zoneID=%d friendly=%s"):format(
	sample[1], sample[4], sample[5], sample[6], sample[9], tostring(sample[13])))

local byKey = {}
for _, raid in ipairs(RAIDS) do
	raid.mobs = {}
	raid.seen = {}
	byKey[raid.key] = raid
end

local function add(raid, id, name, boss)
	if raid.seen[id] then
		return
	end
	raid.seen[id] = true
	raid.mobs[#raid.mobs + 1] = { id = id, name = name, boss = boss }
end

local hand = {}
for _, h in ipairs(HAND_BOSSES) do
	assert(npcs[h.id], "hand-kept boss missing from database: " .. h.id)
	assert(byKey[h.raid], "unknown raid " .. h.raid)
	hand[h.id] = h.raid
end

for id, rec in pairs(npcs) do
	if rec[7] and rec[13] == nil and not EXCLUDED[id] then
		for _, raid in ipairs(RAIDS) do
			if rec[7][raid.areaID] then
				add(raid, id, rec[1], rec[6] == 3 or hand[id] == raid.key)
			end
		end
	end
end
for _, h in ipairs(HAND_BOSSES) do
	local raid = byKey[h.raid]
	if raid.seen[h.id] then
		for _, m in ipairs(raid.mobs) do
			if m.id == h.id then
				m.boss = true
			end
		end
	else
		add(raid, h.id, npcs[h.id][1], true)
	end
end

local out = {}
local function w(s)
	out[#out + 1] = s
end

w("-- Raid creature lists: ids, names, raid membership and a boss flag only.")
w("-- Source: " .. SOURCE .. " (GPL-3). Date: " .. DATE .. ".")
w("-- Generated by scripts/gen_raids.lua \226\128\148 do not edit by hand.")
w("local _, ns = ...")
w("")
w("ns.RaidData = {")
for _, raid in ipairs(RAIDS) do
	table.sort(raid.mobs, function(a, b)
		return a.id < b.id
	end)
	w("\t{")
	w(("\t\tkey = %s,"):format(q(raid.key)))
	w(("\t\tname = %s,"):format(q(raid.name)))
	w(("\t\tinstanceID = %d,"):format(raid.instanceID))
	w("\t\tmobs = {")
	for _, m in ipairs(raid.mobs) do
		w(("\t\t\t{ id = %d, name = %s%s },"):format(m.id, q(m.name), m.boss and ", boss = true" or ""))
	end
	w("\t\t},")
	w("\t},")
end
w("}")
w("")

local f = assert(io.open("src/RaidData.lua", "wb"))
f:write(table.concat(out, "\n"))
f:close()

for _, raid in ipairs(RAIDS) do
	local bosses = 0
	for _, m in ipairs(raid.mobs) do
		if m.boss then
			bosses = bosses + 1
		end
	end
	print(("%-7s mobs=%d bosses=%d"):format(raid.key, #raid.mobs, bosses))
end
