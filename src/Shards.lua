local _, ns = ...

-- Pure module: remembers each Soul Shard by its item GUID, so a soul follows its shard
-- through moves, bag sorting and relogs.
-- Map: { [itemGUID] = { soul = <soul table> | false, seen = <epoch seconds> } }, where
-- false means "a shard we have seen, but it has no soul".

local Shards = {}
ns.Shards = Shards

Shards.ITEM_ID = 6265 -- the Soul Shard item
Shards.FORGET_AFTER = 30 * 86400 -- a baseline drops shards not seen for 30 days

local function valid(entry)
	return type(entry) == "table" and (entry.soul == false or type(entry.soul) == "table")
end

-- map: the saved map; present: readable shard GUIDs now in the bags; baseline (quiet):
-- every new GUID is stored as soulless instead of gained (login, bank open, item on the
-- cursor, unreadable shard slots); now: epoch seconds; prune: drop shards not seen for
-- FORGET_AFTER (the login scan only). Shards not present are otherwise kept (bank,
-- mailbox, cursor).
-- Returns a new map, the sorted list of new GUIDs, which are left out of the new map
-- (the caller fills each with Shards.assign, a soul or false), and how many new GUIDs a
-- baseline stored as soulless.
function Shards.update(map, present, baseline, now, prune)
	local newMap, gained, seenNow, quietNew = {}, {}, {}, 0
	for guid, entry in pairs(map) do
		if valid(entry) and not (prune and now - (entry.seen or 0) > Shards.FORGET_AFTER) then
			newMap[guid] = entry
		end
	end
	for _, guid in ipairs(present) do
		if not seenNow[guid] then
			seenNow[guid] = true
			local entry = newMap[guid]
			if entry then
				newMap[guid] = { soul = entry.soul, seen = now }
			elseif baseline then
				newMap[guid] = { soul = false, seen = now }
				quietNew = quietNew + 1
			else
				gained[#gained + 1] = guid
			end
		end
	end
	table.sort(gained)
	return newMap, gained, quietNew
end

-- Returns a copy of map with guid set to soulOrFalse, seen now.
function Shards.assign(map, guid, soulOrFalse, now)
	local out = {}
	for k, v in pairs(map) do
		out[k] = v
	end
	out[guid] = { soul = soulOrFalse, seen = now }
	return out
end

-- The soul table remembered for a shard, or nil (unknown or soulless).
function Shards.soulOf(map, guid)
	if type(map) ~= "table" or guid == nil then
		return nil
	end
	local entry = map[guid]
	if type(entry) == "table" and type(entry.soul) == "table" then
		return entry.soul
	end
	return nil
end
