-- The view model: turns a dex into the plain rows each window tab draws
-- (pure; no WoW API). `other` is an optional second dex; a row is highlighted
-- when `dex` has the entry and `other` does not.
local _, ns = ...

local View = {}
ns.View = View

local GROUP_FIRST = { "Eastern Kingdoms", "Kalimdor" }
local GROUP_LAST = "Dungeons"
local GROUP_FALLBACK = "Other"

local function groupRank(group)
	for i, name in ipairs(GROUP_FIRST) do
		if group == name then
			return i
		end
	end
	if group == GROUP_LAST then
		return 1000
	end
	return 100
end

local function groupBefore(a, b)
	local ra, rb = groupRank(a), groupRank(b)
	if ra ~= rb then
		return ra < rb
	end
	return a < b
end

function View.places(dex)
	local db = dex.db
	local counts = {}
	for _, mob in pairs(db.mobs) do
		for zone in pairs(mob.places or {}) do
			counts[zone] = (counts[zone] or 0) + 1
		end
	end

	local groups, names = {}, {}
	for zone, count in pairs(counts) do
		local info = db.places[zone]
		local group = info and info.group or GROUP_FALLBACK
		if not groups[group] then
			groups[group] = {}
			names[#names + 1] = group
		end
		groups[group][#groups[group] + 1] = { place = zone, count = count }
	end
	table.sort(names, groupBefore)

	local rows = {}
	for _, group in ipairs(names) do
		rows[#rows + 1] = { header = group }
		table.sort(groups[group], function(a, b)
			return a.place < b.place
		end)
		for _, row in ipairs(groups[group]) do
			rows[#rows + 1] = row
		end
	end
	return rows
end

function View.mobsAt(dex, place, other)
	local rows = {}
	for name, mob in pairs(dex.db.mobs) do
		local record = mob.places and mob.places[place]
		if record then
			rows[#rows + 1] = {
				name = name,
				count = record.count,
				classification = mob.classification,
				highlight = other ~= nil and other.db.mobs[name] == nil,
			}
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

function View.classes(dex)
	local counts = {}
	for _, player in pairs(dex.db.players) do
		local class = player.class or "UNKNOWN"
		counts[class] = (counts[class] or 0) + 1
	end
	local rows = {}
	for class, count in pairs(counts) do
		rows[#rows + 1] = { class = class, count = count }
	end
	table.sort(rows, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.class < b.class
	end)
	return rows
end

function View.playersOf(dex, class, other)
	local rows = {}
	for key, player in pairs(dex.db.players) do
		if (player.class or "UNKNOWN") == class then
			rows[#rows + 1] = {
				key = key,
				name = player.name,
				count = player.count,
				highlight = other ~= nil and other.db.players[key] == nil,
			}
		end
	end
	table.sort(rows, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.key < b.key
	end)
	return rows
end

function View.raids(dex)
	local rows = {}
	for _, raid in ipairs(ns.Raids.list()) do
		local caught, total = dex:raidProgress(raid.instanceID)
		rows[#rows + 1] = {
			instanceID = raid.instanceID,
			name = raid.name,
			caught = caught,
			total = total,
			done = total > 0 and caught == total,
		}
	end
	return rows
end

function View.raidMobs(dex, instanceID, other)
	local raid = ns.Raids.byInstance(instanceID)
	if not raid then
		return {}
	end
	local db = dex.db
	local function isNew(npcID)
		return other ~= nil and other.db.raids[npcID] == nil
	end

	local rows, listed = {}, {}
	for _, mob in ipairs(raid.mobs) do
		listed[mob.id] = true
		local entry = db.raids[mob.id]
		if entry and entry.instanceID ~= instanceID then
			entry = nil
		end
		rows[#rows + 1] = {
			npcID = mob.id,
			name = entry and mob.name or nil,
			boss = mob.boss == true,
			count = entry and entry.count or nil,
			caught = entry ~= nil,
			known = true,
			highlight = entry ~= nil and isNew(mob.id),
		}
	end

	local extra = {}
	for npcID, entry in pairs(db.raids) do
		if entry.instanceID == instanceID and not listed[npcID] then
			extra[#extra + 1] = {
				npcID = npcID,
				name = entry.name,
				boss = false,
				count = entry.count,
				caught = true,
				known = false,
				highlight = isNew(npcID),
			}
		end
	end
	table.sort(extra, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.npcID < b.npcID
	end)
	for _, row in ipairs(extra) do
		rows[#rows + 1] = row
	end
	return rows
end

local function levelText(min, max)
	if not min then
		return nil
	end
	if not max or max == min then
		return "Lv " .. min
	end
	return "Lv " .. min .. "\226\128\147" .. max
end

local function typeText(creatureType, family)
	local parts = {}
	if creatureType and creatureType ~= "" then
		parts[#parts + 1] = creatureType
	end
	if family and family ~= "" then
		parts[#parts + 1] = family
	end
	return table.concat(parts, " \194\183 ")
end

-- The place with the earliest first-caught time (name breaks ties).
local function firstPlace(mob)
	local best, bestFirst
	for zone, record in pairs(mob.places or {}) do
		local first = record.first or math.huge
		if not best or first < bestFirst or (first == bestFirst and zone < best) then
			best, bestFirst = zone, first
		end
	end
	return best
end

function View.mobDetail(dex, name, place)
	local mob = dex.db.mobs[name]
	if not mob then
		return nil
	end
	local firstZone = firstPlace(mob)
	place = place or firstZone
	local record = mob.places and mob.places[place]
	if not record then
		return nil
	end
	return {
		name = mob.name or name,
		classification = mob.classification,
		levelText = levelText(mob.minLevel, mob.maxLevel),
		typeText = typeText(mob.creatureType, mob.family),
		flavour = ns.Flavour.line(mob.name or name, mob.creatureType, mob.family, firstZone),
		place = place,
		count = record.count,
		first = record.first,
		last = record.last,
		myLevel = record.myLevel,
		x = record.x,
		y = record.y,
		points = mob.points,
	}
end

local function titleCase(text)
	return (text:sub(1, 1):upper() .. text:sub(2):lower())
end

function View.playerDetail(dex, key)
	local player = dex.db.players[key]
	if not player then
		return nil
	end
	local parts = {}
	if player.lastLevel then
		parts[#parts + 1] = "Lv " .. player.lastLevel
	end
	if player.race and player.race ~= "" then
		parts[#parts + 1] = player.race
	end
	if player.class and player.class ~= "" then
		parts[#parts + 1] = titleCase(player.class)
	end

	local places = {}
	for zone, record in pairs(player.places or {}) do
		places[#places + 1] = { zone = zone, x = record.x, y = record.y, count = record.count }
	end
	table.sort(places, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.zone < b.zone
	end)

	return {
		name = player.name,
		class = player.class,
		levelRaceClass = table.concat(parts, " "),
		guild = player.guild,
		count = player.count,
		first = player.first,
		firstLevel = player.firstLevel,
		last = player.last,
		lastLevel = player.lastLevel,
		points = player.points,
		places = places,
	}
end

function View.raidDetail(dex, npcID)
	local entry = dex.db.raids[npcID]
	if not entry then
		return nil
	end
	local raid = ns.Raids.byInstance(entry.instanceID)
	local zone = raid and raid.name or nil
	return {
		name = entry.name,
		classification = entry.classification,
		levelText = nil,
		typeText = "",
		flavour = ns.Flavour.line(entry.name, nil, nil, zone),
		place = zone,
		count = entry.count,
		first = entry.first,
		last = entry.last,
		myLevel = entry.myLevel,
		x = nil,
		y = nil,
		points = entry.points,
	}
end

local function thousands(n)
	local text = tostring(math.floor(n))
	local formatted
	repeat
		formatted, n = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = formatted
	until n == 0
	return text
end

function View.header(dex, tab)
	local left = "Soul-Dex \194\183 " .. tab
	local pts = thousands(dex:score()) .. " pts"
	local sep = " \194\183 "
	local right
	if tab == "Mobs" then
		right = thousands(dex:uniqueMobs()) .. sep .. pts
	elseif tab == "Players" then
		right = thousands(dex:uniquePlayers()) .. sep .. pts
	elseif tab == "Raids" then
		local caught, total = 0, 0
		for _, raid in ipairs(ns.Raids.list()) do
			local c, t = dex:raidProgress(raid.instanceID)
			caught, total = caught + c, total + t
		end
		right = caught .. "/" .. total .. sep .. pts
	elseif tab == "Milestones" then
		local earned, total = 0, 0
		for _, item in ipairs(ns.Milestones.list(dex)) do
			total = total + 1
			if item.earned then
				earned = earned + 1
			end
		end
		right = earned .. "/" .. total .. sep .. pts
	else
		right = pts
	end
	return left, right
end
