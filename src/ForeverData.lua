-- WoW: Forever's own raids. Hand-kept (src/RaidData.lua is generated; this file is not).
-- Source: Blizzard, "World of Warcraft: Forever Raid Overview" (news 24303009), read 2026-11-15:
-- names and boss counts only. Boss names, creature lists and instance ids are not published.
--
-- tbd = true: the creature list is not known yet. The raid is listed but not counted, and
-- keeps every soul claimed inside it. Its instance id is learned in game (Raids.learn).
-- When the data is known, an entry gets its instanceID and mobs and loses tbd.
local _, ns = ...

ns.RaidData = ns.RaidData or {}

local RAIDS = {
	{ key = "BD", name = "The Barrow Deeps", bossCount = 8, tbd = true, mobs = {} },
	{ key = "Hyjal", name = "Hyjal Summit", bossCount = 13, tbd = true, mobs = {} },
}

-- Listed first: these are the raids that exist in the game today.
for i, raid in ipairs(RAIDS) do
	table.insert(ns.RaidData, i, raid)
end
