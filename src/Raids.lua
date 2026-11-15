-- Raid lookups over ns.RaidData (pure; no WoW API).
local _, ns = ...

local Raids = {}
ns.Raids = Raids

function Raids.list()
	return ns.RaidData
end

function Raids.byInstance(instanceID)
	if instanceID == nil then
		return nil -- a raid whose id is not known yet matches nothing
	end
	for _, raid in ipairs(ns.RaidData) do
		if raid.instanceID == instanceID then
			return raid
		end
	end
	return nil
end

function Raids.byKey(key)
	for _, raid in ipairs(ns.RaidData) do
		if raid.key == key then
			return raid
		end
	end
	return nil
end

local function normalName(name)
	name = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
	return (name:gsub("^the%s+", ""))
end

-- A raid whose instance id is not known yet, by its instance name (case and a leading
-- "The" ignored). Raids that have an id are matched by id only.
function Raids.byName(name)
	if type(name) ~= "string" then
		return nil
	end
	local wanted = normalName(name)
	if wanted == "" then
		return nil
	end
	for _, raid in ipairs(ns.RaidData) do
		if raid.instanceID == nil and normalName(raid.name) == wanted then
			return raid
		end
	end
	return nil
end

-- Gives a raid without an instance id the id seen in game. Returns true when the raid
-- now has that id; false (nothing changed) for an unknown key, a bad id, a raid that
-- already has another id, or an id another raid has.
function Raids.learn(key, instanceID)
	local raid = Raids.byKey(key)
	if not raid or type(instanceID) ~= "number" then
		return false
	end
	if raid.instanceID ~= nil then
		return raid.instanceID == instanceID
	end
	if Raids.byInstance(instanceID) then
		return false
	end
	raid.instanceID = instanceID
	return true
end

-- The raids with a known creature list: the ones totals and milestones count.
function Raids.completable()
	local list = {}
	for _, raid in ipairs(ns.RaidData) do
		if not raid.tbd then
			list[#list + 1] = raid
		end
	end
	return list
end

-- Returns the raid for the instance (nil if it is not a tracked raid) and
-- the mob entry for the npc id (nil if the raid does not list it).
function Raids.find(instanceID, npcID)
	local raid = Raids.byInstance(instanceID)
	if not raid then
		return nil, nil
	end
	for _, mob in ipairs(raid.mobs) do
		if mob.id == npcID then
			return raid, mob
		end
	end
	return raid, nil
end
