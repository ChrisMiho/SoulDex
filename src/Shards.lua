local _, ns = ...

-- Pure module: keeps the bag slot -> soul map in step with the bags.

local Shards = {}
ns.Shards = Shards

local function parse(key)
	local bag, slot = key:match("^(%d+):(%d+)$")
	return tonumber(bag) or 0, tonumber(slot) or 0
end

local function keyLess(a, b)
	local ba, sa = parse(a)
	local bb, sb = parse(b)
	if ba ~= bb then
		return ba < bb
	end
	return sa < sb
end

-- map: { ["bag:slot"] = soul }; slots: list of "bag:slot" holding a shard;
-- pending: a death candidate is waiting for a shard.
-- Returns a new map and the list of slot keys holding new shards (not in the new map).
function Shards.update(map, slots, pending)
	local present, added, removed, newMap = {}, {}, {}, {}
	for _, key in ipairs(slots) do
		present[key] = true
		if map[key] then
			newMap[key] = map[key]
		else
			added[#added + 1] = key
		end
	end
	for key in pairs(map) do
		if not present[key] then
			removed[#removed + 1] = key
		end
	end
	table.sort(added, keyLess)
	table.sort(removed, keyLess)

	local newCount = math.max(#added - #removed, 0)
	if pending and #added > 0 and newCount == 0 then
		newCount = 1
	end

	local gained = {}
	local r = 1
	for i, key in ipairs(added) do
		if i <= newCount then
			gained[#gained + 1] = key
		else
			if removed[r] then
				newMap[key] = map[removed[r]]
			end
			r = r + 1
		end
	end
	return newMap, gained
end
