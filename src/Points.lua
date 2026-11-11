-- Soul point values per kill (pure; no WoW API).
local _, ns = ...

local Points = {}
ns.Points = Points

Points.PLAYER = 10

local BY_CLASSIFICATION = {
	normal = 1,
	minus = 1,
	elite = 5,
	rare = 10,
	rareelite = 10,
	worldboss = 25,
}

local RAID_BOSS = 25

function Points.forMob(classification, isRaidBoss)
	if isRaidBoss then
		return RAID_BOSS
	end
	return BY_CLASSIFICATION[classification] or 1
end
