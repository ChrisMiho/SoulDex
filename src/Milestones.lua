-- Milestones: thresholds on the dex, earned once and remembered in
-- db.milestones (pure; no WoW API).
local _, ns = ...

local Milestones = {}
ns.Milestones = Milestones

local MOB_STEPS = { 10, 50, 100, 250, 500, 1000 }
local PLAYER_STEPS = { 1, 10, 25, 50, 100 }
-- The name each milestone is earned under; `text` stays the plain goal beside it.
local MOB_TITLES = {
	[10] = "First Harvest",
	[50] = "Soul Collector",
	[100] = "A Hundred Voices",
	[250] = "Shard Hoarder",
	[500] = "Soul Baron",
	[1000] = "A Thousand Souls",
}
local PLAYER_TITLES = {
	[1] = "First Blood",
	[10] = "Headhunter",
	[25] = "Menace",
	[50] = "Dreaded",
	[100] = "Nemesis",
}
local MOB_ANNOUNCE_FROM = 100
local PLAYER_ANNOUNCE_FROM = 25

-- Every definition for the current dex: id, group, title, text, announce, progress, goal.
Milestones.GROUPS = { "Mobs", "Players", "Raids" }

local function definitions(dex)
	local defs = {}
	local group
	local function add(id, title, text, announce, progress, goal)
		defs[#defs + 1] = {
			id = id, title = title, text = text, announce = announce, progress = progress, goal = goal,
			group = group,
		}
	end
	group = "Mobs"

	local mobs = dex:uniqueMobs()
	for _, n in ipairs(MOB_STEPS) do
		add("mobs_" .. n, MOB_TITLES[n], n .. " unique mobs", n >= MOB_ANNOUNCE_FROM, mobs, n)
	end

	group = "Players"
	local players = dex:uniquePlayers()
	for _, n in ipairs(PLAYER_STEPS) do
		local text = n == 1 and "First player soul" or (n .. " player souls")
		add("players_" .. n, PLAYER_TITLES[n], text, n >= PLAYER_ANNOUNCE_FROM, players, n)
	end

	group = "Raids"
	local raids = ns.Raids.list()
	for _, raid in ipairs(raids) do
		local caught, total = dex:raidProgress(raid.instanceID)
		add("raid_" .. raid.key, raid.name .. " Drained", "every soul", true, caught, total)
	end
	add("raids_all", "Raid Reaper", "every raid drained", true, dex:raidsCompleted(), #raids)
	return defs
end

-- A goal of 0 (a raid with no known mobs, or no raids at all) is never reached.
local function reached(def)
	return def.goal > 0 and def.progress >= def.goal
end

-- One line for chat: "A Hundred Voices (100 unique mobs)", or the text alone without a title.
function Milestones.label(m)
	if m.title and m.title ~= "" then
		return m.title .. " (" .. m.text .. ")"
	end
	return m.text
end

function Milestones.list(dex)
	local items = {}
	for i, def in ipairs(definitions(dex)) do
		items[i] = {
			id = def.id,
			group = def.group,
			title = def.title,
			text = def.text,
			earned = dex.db.milestones[def.id],
			progress = def.progress,
			goal = def.goal,
		}
	end
	return items
end

function Milestones.check(dex, now)
	local earned = dex.db.milestones
	local newly = {}
	for _, def in ipairs(definitions(dex)) do
		if not earned[def.id] and reached(def) then
			earned[def.id] = now
			newly[#newly + 1] = { id = def.id, title = def.title, text = def.text, announce = def.announce }
		end
	end
	return newly
end
