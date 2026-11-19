-- Sorting, filtering and comparing dex rows for the window (pure; no WoW API).
-- `other` is the viewer's own dex while a friend's dex is on screen: `side` says
-- whether a row is "missing" (the viewer lacks it), "shared", or "mine" (only the viewer has it).
local _, ns = ...

local Browse = {}
ns.Browse = Browse

Browse.ALL = "*"

local SORTS = {
	Mobs = { "name", "count", "recent", "rarity" },
	Players = { "count", "name", "recent" },
}
local COLLECTIONS = { Mobs = true, Players = true, Raids = true }
local OWN_MOB_FILTERS = { "all", "rare", "mastered", "unmastered" }
local BROWSING_FILTERS = { "all", "diff", "missing", "mine", "shared" }
local RARE = { elite = true, rare = true, rareelite = true, worldboss = true }
local RARITY = { worldboss = 3, rare = 2, rareelite = 2, elite = 1 }

local LABELS = {
	name = "A\226\128\147Z",
	count = "Most claimed",
	recent = "Newest",
	rarity = "Rarest",
	all = "All",
	rare = "Rare and elite",
	mastered = "Mastered",
	unmastered = "Not mastered",
	diff = "Differences",
	missing = "Missing",
	mine = "Only mine",
	shared = "Shared",
}

local function copy(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

function Browse.sorts(tab, browsing)
	local list = SORTS[tab]
	if not list then
		return {}
	end
	local out = {}
	for _, id in ipairs(list) do
		if not (browsing and id == "recent") then
			out[#out + 1] = id
		end
	end
	return out
end

function Browse.filters(tab, browsing)
	if browsing and COLLECTIONS[tab] then
		return copy(BROWSING_FILTERS)
	end
	if not browsing and tab == "Mobs" then
		return copy(OWN_MOB_FILTERS)
	end
	return {}
end

function Browse.valid(list, id)
	for _, v in ipairs(list) do
		if v == id then
			return id
		end
	end
	return list[1]
end

function Browse.step(list, id, back)
	local current = Browse.valid(list, id)
	if current == nil then
		return nil
	end
	for i, v in ipairs(list) do
		if v == current then
			local n = i + (back and -1 or 1)
			if n < 1 then
				n = #list
			elseif n > #list then
				n = 1
			end
			return list[n]
		end
	end
end

function Browse.label(id, browsing)
	if id == "all" and browsing then
		return "Their dex"
	end
	return LABELS[id]
end

-- A mob's mastery stars, or nil when it has none to show.
local function starCount(dex, entry)
	local stars = dex:stars(entry)
	return stars and stars > 0 and stars or nil
end

-- A mob's claims and latest claim, over one place or (place == ALL) every place.
local function claims(mob, place)
	local count, last = 0, nil
	for zone, record in pairs(mob.places or {}) do
		if place == Browse.ALL or zone == place then
			count = count + (record.count or 0)
			if record.last and (not last or record.last > last) then
				last = record.last
			end
		end
	end
	return count, last
end

local function hasPlace(mob, place)
	if place == Browse.ALL then
		return true
	end
	return mob.places ~= nil and mob.places[place] ~= nil
end

function Browse.mobs(dex, place, other)
	local rows = {}
	local mobs = dex.db.mobs
	local unknownRow
	if place == Browse.ALL then
		for name, mob in pairs(mobs) do
			local count, last = claims(mob, place)
			rows[#rows + 1] = {
				name = name,
				count = count,
				classification = mob.classification,
				stars = starCount(dex, mob),
				last = last,
			}
		end
	else
		for _, row in ipairs(ns.View.mobsAt(dex, place)) do
			if row.unknown then
				unknownRow = { name = row.name, count = row.count, unknown = true }
			else
				row.highlight = nil
				row.last = mobs[row.name].places[place].last
				rows[#rows + 1] = row
			end
		end
	end
	if other then
		for _, row in ipairs(rows) do
			row.side = other.db.mobs[row.name] and "shared" or "missing"
		end
		for name, mob in pairs(other.db.mobs) do
			if not mobs[name] and hasPlace(mob, place) then
				local count, last = claims(mob, place)
				rows[#rows + 1] = {
					name = name,
					count = count,
					classification = mob.classification,
					last = last,
					side = "mine",
				}
			end
		end
	end
	if unknownRow then
		rows[#rows + 1] = unknownRow
	end
	return rows
end

function Browse.players(dex, class, other)
	local rows = {}
	local players = dex.db.players
	for key, player in pairs(players) do
		if class == Browse.ALL or (player.class or "UNKNOWN") == class then
			rows[#rows + 1] = {
				key = key,
				name = player.name,
				class = player.class,
				count = player.count,
				last = player.last,
				side = other and (other.db.players[key] and "shared" or "missing") or nil,
			}
		end
	end
	if other then
		for key, player in pairs(other.db.players) do
			if not players[key] and (class == Browse.ALL or (player.class or "UNKNOWN") == class) then
				rows[#rows + 1] = {
					key = key,
					name = player.name,
					class = player.class,
					count = player.count,
					last = player.last,
					side = "mine",
				}
			end
		end
	end
	return rows
end

local function keeps(row, filter)
	if row.unknown then
		return filter == "all"
	end
	if filter == "rare" then
		return RARE[row.classification] == true
	elseif filter == "mastered" then
		return (row.stars or 0) >= 1
	elseif filter == "unmastered" then
		return not row.stars
	elseif filter == "missing" or filter == "mine" or filter == "shared" then
		return row.side == filter
	elseif filter == "diff" then
		return row.side == "missing" or row.side == "mine"
	end
	return true
end

local function byName(a, b)
	local an, bn = a.name or "", b.name or ""
	if an ~= bn then
		return an < bn
	end
	return (a.key or "") < (b.key or "")
end

local function rarityOf(row)
	return RARITY[row.classification] or 0
end

-- True when a goes before b under sort; every tie falls through to name, then key.
local function before(sort, a, b)
	if a.unknown ~= b.unknown then
		return b.unknown == true
	end
	if sort == "count" then
		if (a.count or 0) ~= (b.count or 0) then
			return (a.count or 0) > (b.count or 0)
		end
	elseif sort == "recent" then
		if a.last ~= b.last then
			if not a.last then
				return false
			elseif not b.last then
				return true
			end
			return a.last > b.last
		end
	elseif sort == "rarity" then
		if rarityOf(a) ~= rarityOf(b) then
			return rarityOf(a) > rarityOf(b)
		end
	end
	return byName(a, b)
end

function Browse.apply(rows, filter, sort)
	local out = {}
	for _, row in ipairs(rows) do
		if keeps(row, filter) then
			out[#out + 1] = row
		end
	end
	if sort then
		table.sort(out, function(a, b)
			return before(sort, a, b)
		end)
	end
	return out
end

function Browse.counts(dex, other, tab)
	local result = { missing = 0, mine = 0, shared = 0 }
	local field = tab == "Mobs" and "mobs" or tab == "Players" and "players" or tab == "Raids" and "raids"
	if not field then
		return result
	end
	local theirs, mine = dex.db[field], other.db[field]
	for key in pairs(theirs) do
		local side = mine[key] and "shared" or "missing"
		result[side] = result[side] + 1
	end
	for key in pairs(mine) do
		if not theirs[key] then
			result.mine = result.mine + 1
		end
	end
	return result
end
