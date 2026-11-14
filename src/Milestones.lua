-- Milestones: thresholds on the dex, earned once and remembered in
-- db.milestones (pure; no WoW API).
local _, ns = ...

local Milestones = {}
ns.Milestones = Milestones

local MOB_STEPS = { 10, 50, 100, 250, 500, 1000 }
local PLAYER_STEPS = { 1, 10, 25, 50, 100 }
local MOB_ANNOUNCE_FROM = 100
local PLAYER_ANNOUNCE_FROM = 25

-- Every definition for the current dex: id, text, announce, progress, goal.
local function definitions(dex)
	local defs = {}
	local function add(id, text, announce, progress, goal)
		defs[#defs + 1] = { id = id, text = text, announce = announce, progress = progress, goal = goal }
	end

	local mobs = dex:uniqueMobs()
	for _, n in ipairs(MOB_STEPS) do
		add("mobs_" .. n, n .. " unique mobs", n >= MOB_ANNOUNCE_FROM, mobs, n)
	end

	local players = dex:uniquePlayers()
	for _, n in ipairs(PLAYER_STEPS) do
		local text = n == 1 and "First player soul" or (n .. " player souls")
		add("players_" .. n, text, n >= PLAYER_ANNOUNCE_FROM, players, n)
	end

	local raids = ns.Raids.list()
	for _, raid in ipairs(raids) do
		local caught, total = dex:raidProgress(raid.instanceID)
		add("raid_" .. raid.key, "Completed " .. raid.name, true, caught, total)
	end
	add("raids_all", "Every raid soul", true, dex:raidsCompleted(), #raids)
	return defs
end

-- A goal of 0 (a raid with no known mobs, or no raids at all) is never reached.
local function reached(def)
	return def.goal > 0 and def.progress >= def.goal
end

function Milestones.list(dex)
	local items = {}
	for i, def in ipairs(definitions(dex)) do
		items[i] = {
			id = def.id,
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
			newly[#newly + 1] = { id = def.id, text = def.text, announce = def.announce }
		end
	end
	return newly
end
