-- The view model: turns a dex into the plain rows each window tab draws
-- (pure; no WoW API). `other` is an optional second dex; a row is highlighted
-- when `dex` has the entry and `other` does not.
local _, ns = ...

local View = {}
ns.View = View

View.DASH = "\226\128\148" -- em dash: a field the dex doesn't have
View.TIMES = "\195\151" -- multiplication sign

local GROUP_FIRST = { "Eastern Kingdoms", "Kalimdor" }
local GROUP_LAST = "Dungeons"
local GROUP_RAIDS = "Raids"
local GROUP_FALLBACK = "Other"

local function groupRank(group)
	for i, name in ipairs(GROUP_FIRST) do
		if group == name then
			return i
		end
	end
	if group == GROUP_RAIDS then
		return 999
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
	-- A zone with only unknown souls is still listed; its count (unique mobs) is 0.
	for zone in pairs(db.unknown or {}) do
		counts[zone] = counts[zone] or 0
	end

	local groups, names = {}, {}
	for zone, count in pairs(counts) do
		local info = db.places[zone] or (db.unknown and db.unknown[zone])
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

-- A row's mastery stars, or nil when it has none to show (Dex.stars).
local function starCount(dex, entry)
	local stars = dex:stars(entry)
	return stars and stars > 0 and stars or nil
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
				stars = starCount(dex, mob),
				highlight = other ~= nil and other.db.mobs[name] == nil,
			}
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	-- Hidden-name catches: one row, always last (spec 5.2).
	local unknown = dex.db.unknown and dex.db.unknown[place]
	if unknown then
		rows[#rows + 1] = { name = "Unknown soul", count = unknown.count, unknown = true }
	end
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

-- Souls kept under a raid whose creature list is still TBD (0 until its instance id is known).
local function claimedIn(dex, instanceID)
	local n = 0
	if instanceID ~= nil then
		for _, entry in pairs(dex.db.raids) do
			if entry.instanceID == instanceID then
				n = n + 1
			end
		end
	end
	return n
end

-- A TBD raid is listed but not counted: total 0, never done, caught = souls kept there.
function View.raids(dex)
	local rows = {}
	for _, raid in ipairs(ns.Raids.list()) do
		local caught, total = dex:raidProgress(raid.instanceID)
		local tbd = raid.tbd == true
		if tbd then
			caught, total = claimedIn(dex, raid.instanceID), 0
		end
		rows[#rows + 1] = {
			key = raid.key,
			instanceID = raid.instanceID,
			name = raid.name,
			caught = caught,
			total = total,
			done = total > 0 and caught == total,
			tbd = tbd,
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
			stars = entry and starCount(dex, entry) or nil,
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
				stars = starCount(dex, entry),
				caught = true,
				known = false,
				highlight = isNew(npcID),
			}
		end
	end
	table.sort(extra, function(a, b)
		local an, bn = a.name or "", b.name or ""
		if an ~= bn then
			return an < bn
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

-- { stars, count, from, to } for the detail pane's Mastery line, or nil (Dex.stars).
local function mastery(dex, entry)
	local stars, count, from, to = dex:stars(entry)
	if not stars then
		return nil
	end
	return { stars = stars, count = count, from = from, to = to }
end

function View.mobDetail(dex, name, place)
	local mob = dex.db.mobs[name]
	if not mob then
		return nil
	end
	-- The flavour line uses the first place on purpose, so it stays the same whichever
	-- place is selected (spec 6.5).
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
		creatureType = mob.creatureType,
		flavour = ns.Flavour.line(mob.name or name, mob.creatureType, mob.family, firstZone),
		place = place,
		count = record.count,
		first = record.first,
		last = record.last,
		myLevel = record.myLevel,
		x = record.x,
		y = record.y,
		points = dex:worth(mob),
		mastery = mastery(dex, mob),
	}
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
		levelRace = table.concat(parts, " "), -- the UI adds the class name in the client's language
		guild = player.guild,
		count = player.count,
		first = player.first,
		firstLevel = player.firstLevel,
		last = player.last,
		lastLevel = player.lastLevel,
		points = dex:worth(player, true),
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
		levelText = levelText(entry.minLevel, entry.maxLevel),
		typeText = typeText(entry.creatureType, entry.family),
		creatureType = entry.creatureType,
		flavour = ns.Flavour.line(entry.name, entry.creatureType, entry.family, zone),
		place = zone,
		count = entry.count,
		first = entry.first,
		last = entry.last,
		myLevel = entry.myLevel,
		x = nil,
		y = nil,
		points = dex:worth(entry),
		mastery = mastery(dex, entry),
	}
end

-- 1264 -> "1,264".
local function thousands(n)
	local text = tostring(math.floor(n))
	local formatted
	repeat
		formatted, n = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = formatted
	until n == 0
	return text
end

View.thousands = thousands

local DASH, TIMES = View.DASH, View.TIMES

-- The key with the highest count; ties go to the alphabetically first key.
local function topOf(counts)
	local best, bestCount
	for key, count in pairs(counts) do
		if not best or count > bestCount or (count == bestCount and key < best) then
			best, bestCount = key, count
		end
	end
	return best, bestCount
end

local function countedText(name, count)
	if not name then
		return DASH
	end
	return name .. " " .. TIMES .. count
end

-- Lines of the Me tab: an ordered list of { label, value, color? } (color is a
-- UIFormat.COLORS key). me = { name, summary } and friendsStore feed the rank line;
-- either may be nil (Net not loaded), which gives "—". friendsStore == false (browsing
-- a friend's dex) leaves the rank line out.
-- Zones visited and the top zone count mob, player and unknown catches; raid catches
-- have no zone, so they only add to Souls taken.
function View.me(dex, friendsStore, me, now)
	local db = dex.db
	local souls, unknown = 0, 0
	local mobCounts, zoneCounts = {}, {}
	local function bump(zone, n)
		zoneCounts[zone] = (zoneCounts[zone] or 0) + n
	end
	for name, mob in pairs(db.mobs) do
		local total = 0
		for zone, record in pairs(mob.places or {}) do
			total = total + record.count
			bump(zone, record.count)
		end
		if total > 0 then
			mobCounts[name] = total
		end
		souls = souls + total
	end
	for _, player in pairs(db.players) do
		souls = souls + (player.count or 0)
		for zone, record in pairs(player.places or {}) do
			bump(zone, record.count)
		end
	end
	for _, raid in pairs(db.raids) do
		souls = souls + (raid.count or 0)
	end
	for zone, entry in pairs(db.unknown or {}) do
		unknown = unknown + entry.count
		bump(zone, entry.count)
	end
	souls = souls + unknown

	local zones = 0
	for _, n in pairs(zoneCounts) do
		if n > 0 then
			zones = zones + 1
		end
	end
	local mobName, mobCount = topOf(mobCounts)
	local zoneName, zoneCount = topOf(zoneCounts)

	local rank = DASH
	if friendsStore and me and ns.Friends then
		-- Only people we have numbers for take part in the rank.
		local heard = {}
		for name, entry in pairs(friendsStore) do
			if entry.summary then
				heard[name] = entry
			end
		end
		local rows = ns.Friends.leaderboard(heard, me, now)
		if #rows > 1 then
			for i, r in ipairs(rows) do
				if r.isMe then
					rank = "#" .. i .. " of " .. #rows
				end
			end
		end
	end

	local lines = {
		{ label = "Unique mobs", value = tostring(dex:uniqueMobs()) },
		{ label = "Players", value = tostring(dex:uniquePlayers()) },
		{ label = "Raids completed", value = tostring(dex:raidsCompleted()) },
		{ label = "Mastery stars", value = thousands(dex:masteryStars()), color = "FEL" },
		{ label = "Souls taken", value = thousands(souls) },
		{ label = "Zones visited", value = tostring(zones) },
		{ label = "Most claimed", value = countedText(mobName, mobCount) },
		{ label = "Top zone", value = countedText(zoneName, zoneCount) },
	}
	if unknown > 0 then
		lines[#lines + 1] = { label = "Unknown souls", value = tostring(unknown) }
	end
	if friendsStore ~= false then
		lines[#lines + 1] = { label = "Friends rank", value = rank }
	end
	return lines
end

-- The Me tab's tiles and records (spec 5.8), on top of View.me's numbers.
--   tiles:   { label, value, color? } x6
--   records: { label, name?, count?, time?, souls?, class?, classification?, text? }
-- Browsing a friend (friendsStore == false) swaps the friends tile for zones.
local RARITY_ORDER = { elite = 1, rare = 2, rareelite = 2, worldboss = 3 }

function View.meCard(dex, friendsStore, me, now)
	local db = dex.db
	local value = {}
	for _, line in ipairs(View.me(dex, friendsStore, me, now)) do
		value[line.label] = line.value
	end
	local tiles = {
		{ label = "Unique mobs", value = value["Unique mobs"] },
		{ label = "Players", value = value["Players"] },
		{ label = "Raids", value = value["Raids completed"] .. " / " .. #ns.Raids.completable() },
		{ label = "Mastery", value = value["Mastery stars"], color = "FEL", star = true },
		{ label = "Souls taken", value = value["Souls taken"] },
	}
	if friendsStore == false then
		tiles[6] = { label = "Zones", value = value["Zones visited"] }
	else
		tiles[6] = { label = "Among friends", value = value["Friends rank"] }
	end

	-- Most claimed and hunting ground come ready-made ("Wolf ×14"); the rest are found here.
	local nemesis, rarest, latest
	local function newer(name, entry, extra)
		if entry.last and (not latest or entry.last > latest.time) then
			latest = { name = name, time = entry.last, class = extra and extra.class,
				classification = entry.classification }
		end
	end
	local function rarer(name, entry)
		local order = ns.Points.rule(entry, db.flat) == "boss" and 3 or RARITY_ORDER[entry.classification] or 0
		local first = entry.first or math.huge
		if not rarest or order > rarest.order or (order == rarest.order and first < rarest.first) then
			rarest = { name = name, order = order, first = first, classification = entry.classification }
			if order == 3 then
				rarest.classification = "worldboss"
			end
		end
	end
	for name, mob in pairs(db.mobs) do
		newer(mob.name or name, mob)
		rarer(mob.name or name, mob)
	end
	for _, entry in pairs(db.raids) do
		if entry.name then
			newer(entry.name, entry)
			rarer(entry.name, entry)
		end
	end
	for key, player in pairs(db.players) do
		local name = player.name or key
		newer(name, player, player)
		local count = player.count or 0
		if not nemesis or count > nemesis.count or (count == nemesis.count and name < nemesis.name) then
			nemesis = { name = name, count = count, class = player.class }
		end
	end

	local records = {
		{ label = "Most claimed", text = value["Most claimed"] },
		{ label = "Nemesis", name = nemesis and nemesis.name, count = nemesis and nemesis.count,
			class = nemesis and nemesis.class },
		{ label = "Hunting ground", text = value["Top zone"] },
		{ label = "Rarest trophy", name = rarest and rarest.name, classification = rarest and rarest.classification },
		{ label = "Latest", name = latest and latest.name, time = latest and latest.time,
			class = latest and latest.class, classification = latest and latest.classification },
	}
	local best = db.best
	if type(best) == "table" and (best.count or 0) > 0 then
		records[#records + 1] = { label = "Best day", souls = best.count, time = best.time }
	else
		records[#records + 1] = { label = "Best day" }
	end
	if friendsStore ~= false then
		records[#records + 1] = { label = "Zones hunted", text = value["Zones visited"] }
	end
	if value["Unknown souls"] then
		records[#records + 1] = { label = "Unknown souls", text = value["Unknown souls"] }
	end
	return { tiles = tiles, records = records }
end

function View.header(dex, tab)
	local left = "SoulDex \194\183 " .. tab
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
