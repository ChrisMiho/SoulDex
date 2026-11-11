-- Raid lookups over ns.RaidData (pure; no WoW API).
local _, ns = ...

local Raids = {}
ns.Raids = Raids

function Raids.list()
	return ns.RaidData
end

function Raids.byInstance(instanceID)
	for _, raid in ipairs(ns.RaidData) do
		if raid.instanceID == instanceID then
			return raid
		end
	end
	return nil
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
