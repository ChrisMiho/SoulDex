local _, ns = ...

-- Pure module: remembers each Soul Shard by its item GUID, so a soul follows its shard
-- through moves, bag sorting and relogs.
-- Map: { [itemGUID] = { soul = <soul table> | false, seen = <epoch seconds> } }, where
-- false means "a shard we have seen, but it has no soul". A shard whose soul's name is
-- still being fetched is { soul = false, pending = { token, ctx }, seen }.

local Shards = {}
ns.Shards = Shards

Shards.ITEM_ID = 6265 -- the Soul Shard item
Shards.FORGET_AFTER = 30 * 86400 -- a baseline drops shards not seen for 30 days

local function valid(entry)
	if type(entry) ~= "table" or not (entry.soul == false or type(entry.soul) == "table") then
		return false
	end
	local pending = entry.pending
	return pending == nil or (type(pending) == "table" and type(pending.token) == "string")
end

-- Absent shards (spent, banked, mailed) are kept so a banked shard still has its soul
-- when it comes back, but a spent one never returns: the login scan drops absent
-- soulless shards after a day, and keeps at most MAX_ABSENT absent ones in all.
Shards.FORGET_SOULLESS_AFTER = 86400
Shards.MAX_ABSENT = 400

-- The login clean-up: drops damaged entries, shards not seen for FORGET_AFTER, absent
-- soulless ones not seen for FORGET_SOULLESS_AFTER, and the oldest absent ones past
-- MAX_ABSENT. A shard still waiting for its name is always kept.
local function tidy(map, isPresent, now)
	local absent = {}
	for guid, entry in pairs(map) do
		local age = valid(entry) and now - (entry.seen or 0)
		if not age or age > Shards.FORGET_AFTER then
			map[guid] = nil
		elseif not isPresent[guid] and not entry.pending then
			if entry.soul == false and age > Shards.FORGET_SOULLESS_AFTER then
				map[guid] = nil
			else
				absent[#absent + 1] = { guid = guid, seen = entry.seen or 0 }
			end
		end
	end
	if #absent > Shards.MAX_ABSENT then
		table.sort(absent, function(a, b)
			if a.seen ~= b.seen then
				return a.seen > b.seen
			end
			return tostring(a.guid) < tostring(b.guid)
		end)
		for i = Shards.MAX_ABSENT + 1, #absent do
			map[absent[i].guid] = nil
		end
	end
end

-- map: the saved map, changed in place (it holds every shard ever seen, so a bag scan
-- must not copy it); present: readable shard GUIDs now in the bags; baseline (quiet):
-- every new GUID is stored as soulless instead of gained (login, bank open, item on the
-- cursor, unreadable shard slots); now: epoch seconds; prune: run the login clean-up
-- (tidy, above). Shards not present are otherwise kept (bank, mailbox, cursor).
-- Returns the map, the sorted list of new GUIDs, which are not yet in the map (the
-- caller fills each with Shards.assign, a soul or false), and how many new GUIDs a
-- baseline stored as soulless.
function Shards.update(map, present, baseline, now, prune)
	local gained, seenNow, quietNew = {}, {}, 0
	for _, guid in ipairs(present) do
		seenNow[guid] = true
	end
	if prune then
		tidy(map, seenNow, now)
	end
	for guid in pairs(seenNow) do
		local entry = map[guid]
		if valid(entry) then
			entry.seen = now
		elseif baseline then
			map[guid] = { soul = false, seen = now }
			quietNew = quietNew + 1
		else
			map[guid] = nil -- a damaged entry: the shard counts as new
			gained[#gained + 1] = guid
		end
	end
	table.sort(gained)
	return map, gained, quietNew
end

-- Sets guid to soulOrFalse, seen now, in map itself; returns map.
function Shards.assign(map, guid, soulOrFalse, now)
	map[guid] = { soul = soulOrFalse, seen = now }
	return map
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

-- Marks guid, in map itself, as waiting for a soul's name: pending = { token, ctx }.
-- Returns map.
function Shards.assignPending(map, guid, token, ctx, now)
	map[guid] = { soul = false, pending = { token = token, ctx = ctx }, seen = now }
	return map
end

-- The pending { token, ctx } of a shard, or nil.
function Shards.pendingOf(map, guid)
	if type(map) ~= "table" or guid == nil then
		return nil
	end
	local entry = map[guid]
	if type(entry) == "table" and type(entry.pending) == "table" then
		return entry.pending
	end
	return nil
end

-- The guid of the shard waiting on token, or nil.
function Shards.findPending(map, token)
	if type(map) ~= "table" or token == nil then
		return nil
	end
	for guid, entry in pairs(map) do
		if type(entry) == "table" and type(entry.pending) == "table" and entry.pending.token == token then
			return guid
		end
	end
	return nil
end

-- Every pending shard as { guid, pending }, sorted by guid.
function Shards.allPending(map)
	local out = {}
	for guid, entry in pairs(map) do
		if type(entry) == "table" and type(entry.pending) == "table" then
			out[#out + 1] = { guid = guid, pending = entry.pending }
		end
	end
	table.sort(out, function(a, b)
		return a.guid < b.guid
	end)
	return out
end
