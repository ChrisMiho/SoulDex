local _, ns = ...

-- Pure module: keeps the bag slot -> soul map in step with the bags.
-- Map values are a soul table, or false for "a shard we have seen but it has no soul".

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

-- map: { ["bag:slot"] = soul | false }; slots: list of "bag:slot" holding a shard;
-- baseline: first scan after login - every slot is known, nothing is gained.
-- Returns a new map and the list of genuinely new slot keys (absent from the new map;
-- the caller fills each with Shards.assign, a soul or false).
function Shards.update(map, slots, baseline)
	local present, added, removed, newMap = {}, {}, {}, {}
	for _, key in ipairs(slots) do
		present[key] = true
		if map[key] ~= nil then
			newMap[key] = map[key]
		elseif baseline then
			newMap[key] = false
		else
			added[#added + 1] = key
		end
	end
	if baseline then
		return newMap, {}
	end
	for key in pairs(map) do
		if not present[key] then
			removed[#removed + 1] = key
		end
	end
	table.sort(added, keyLess)
	table.sort(removed, keyLess)

	local newCount = math.max(#added - #removed, 0)
	local gained = {}
	local r = 1
	for i, key in ipairs(added) do
		if i <= newCount then
			gained[#gained + 1] = key
		else
			newMap[key] = map[removed[r]]
			r = r + 1
		end
	end
	return newMap, gained
end

-- Returns a copy of map with slot set to soulOrFalse.
function Shards.assign(map, slot, soulOrFalse)
	local out = {}
	for k, v in pairs(map) do
		out[k] = v
	end
	out[slot] = soulOrFalse
	return out
end
