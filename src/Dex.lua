-- The dex model: what has been caught, where, and how many soul points it is
-- worth (pure; no WoW API). Works on the SoulDexDB table it is given.
local _, ns = ...

local Dex = {}
ns.Dex = Dex

local methods = {}
local meta = { __index = methods }

function Dex.new(db)
	for _, key in ipairs({ "mobs", "places", "players", "raids", "milestones", "unknown", "instances" }) do
		if type(db[key]) ~= "table" then
			db[key] = {} -- missing, or damaged saved data
		end
	end
	-- Instance ids learned in game for raids the data lists without one (raidFor).
	-- Raids.learn refuses anything damaged or out of date.
	for key, instanceID in pairs(db.instances) do
		ns.Raids.learn(key, instanceID)
	end
	return setmetatable({ db = db }, meta)
end

local function notePlace(db, ctx)
	if ctx.zone and not db.places[ctx.zone] then
		db.places[ctx.zone] = { group = ctx.group }
	end
end

-- Souls claimed today and on the best day so far (the Me tab's "Best day"): db.today and
-- db.best are { day, count }, a day being Points.day. Counted from the first claim after
-- this was added; earlier days were never saved.
local function noteDay(db, now)
	if type(now) ~= "number" then
		return
	end
	local day = ns.Points.day(now)
	local today = db.today
	if type(today) ~= "table" or today.day ~= day then
		today = { day = day, count = 0, time = now }
		db.today = today
	end
	today.count = today.count + 1
	local best = db.best
	if type(best) ~= "table" or today.count > (best.count or 0) then
		db.best = { day = day, count = today.count, time = today.time }
	end
end

local function noteLevel(entry, level)
	if level then
		if not entry.minLevel or level < entry.minLevel then
			entry.minLevel = level
		end
		if not entry.maxLevel or level > entry.maxLevel then
			entry.maxLevel = level
		end
	end
end

function methods:recordMob(info, ctx)
	local db = self.db
	notePlace(db, ctx)
	noteDay(db, ctx.time)
	local entry = db.mobs[info.name]
	local isNew = entry == nil
	local points, stars = 0, nil
	local before = entry and ns.Points.count(entry) or 0
	local prevLast = entry and entry.last
	if isNew then
		points = ns.Points.forMob(info.classification)
		entry = {
			name = info.name,
			minLevel = info.level,
			maxLevel = info.level,
			classification = info.classification,
			creatureType = info.creatureType,
			family = info.family,
			points = points,
			first = ctx.time,
			places = {},
		}
		db.mobs[info.name] = entry
	end
	if not isNew then
		-- A soul named by whisper may have been recorded before its details were readable:
		-- fill the gaps, never overwrite, never lower points.
		for _, field in ipairs({ "classification", "creatureType", "family" }) do
			if entry[field] == nil and type(info[field]) == "string" then
				entry[field] = info[field]
				if field == "classification" then
					entry.points = math.max(entry.points or 0, ns.Points.forMob(info.classification))
				end
			end
		end
	end
	entry.last = ctx.time
	noteLevel(entry, info.level)
	local place = entry.places[ctx.zone]
	if not place then
		place = { count = 0, first = ctx.time, myLevel = ctx.myLevel, x = ctx.x, y = ctx.y }
		entry.places[ctx.zone] = place
	end
	place.count = place.count + 1
	place.last = ctx.time
	if not isNew then
		points, stars = ns.Points.again(entry, before, prevLast, ctx.time)
	end
	return {
		isNew = isNew, points = points, total = self:uniqueSouls(), kind = "mob",
		stars = stars, count = before + 1,
	}
end

function methods:recordPlayer(info, ctx)
	local db = self.db
	notePlace(db, ctx)
	noteDay(db, ctx.time)
	local key = info.name .. "-" .. (info.realm or "")
	local entry = db.players[key]
	local isNew = entry == nil
	local points = 0
	local prevLast = entry and entry.last
	if isNew then
		points = ns.Points.PLAYER
		entry = {
			name = info.name,
			realm = info.realm,
			firstLevel = info.level,
			count = 0,
			first = ctx.time,
			points = points,
			places = {},
		}
		db.players[key] = entry
	end
	entry.class = info.class or entry.class
	entry.race = info.race or entry.race
	entry.guild = info.guild or entry.guild
	entry.lastLevel = info.level or entry.lastLevel
	entry.count = entry.count + 1
	entry.last = ctx.time
	local place = entry.places[ctx.zone]
	if not place then
		place = { count = 0, x = ctx.x, y = ctx.y }
		entry.places[ctx.zone] = place
	end
	place.count = place.count + 1
	if not isNew then
		points = ns.Points.again(entry, entry.count - 1, prevLast, ctx.time, true)
	end
	return { isNew = isNew, points = points, total = self:uniqueSouls(), kind = "player", count = entry.count }
end

-- The listed raid for an instance. A raid the data lists without an instance id is
-- matched by its instance name the first time; the id is then learned and saved.
function methods:raidFor(instanceID, instanceName)
	local raid = ns.Raids.byInstance(instanceID)
	if raid then
		return raid
	end
	raid = ns.Raids.byName(instanceName)
	if raid and ns.Raids.learn(raid.key, instanceID) then
		self.db.instances[raid.key] = instanceID
		return raid
	end
	return nil
end

function methods:recordRaid(info, ctx, instanceID, npcID)
	local db = self.db
	noteDay(db, ctx.time)
	local _, known = ns.Raids.find(instanceID, npcID)
	local entry = db.raids[npcID]
	local isNew = entry == nil
	local points, stars = 0, nil
	local before
	local prevLast = entry and entry.last
	if isNew then
		before = self:uniqueSouls()
		points = ns.Points.forMob(info.classification, known ~= nil and known.boss == true)
		entry = {
			name = info.name,
			instanceID = instanceID,
			count = 0,
			first = ctx.time,
			myLevel = ctx.myLevel,
			points = points,
			known = known ~= nil,
		}
		db.raids[npcID] = entry
	end
	-- Filled on later catches too, for entries saved before these were kept.
	entry.classification = entry.classification or info.classification
	entry.creatureType = entry.creatureType or info.creatureType
	entry.family = entry.family or info.family
	noteLevel(entry, info.level)
	entry.count = entry.count + 1
	entry.last = ctx.time
	if not isNew then
		points, stars = ns.Points.again(entry, entry.count - 1, prevLast, ctx.time)
	end
	-- A new raid slot whose name the dex already has (spec 4.5) adds no soul: no total, so
	-- the popup shows no repeated "Soul #N".
	local total = self:uniqueSouls()
	if total == before then
		total = nil
	end
	return { isNew = isNew, points = points, total = total, kind = "raid", stars = stars, count = entry.count }
end

-- A soul whose name the game hid (spec 4.4): counted per zone only. No points, not a
-- unique mob, not new, so no popup and no milestone progress.
function methods:recordUnknown(ctx)
	local db = self.db
	notePlace(db, ctx)
	noteDay(db, ctx.time)
	local entry = db.unknown[ctx.zone]
	if not entry then
		entry = { count = 0, first = ctx.time, group = ctx.group }
		db.unknown[ctx.zone] = entry
	end
	entry.count = entry.count + 1
	entry.last = ctx.time
	return { isNew = false, points = 0, kind = "unknown" }
end

-- Raid creatures count as mobs too, once per name (spec 4.5).
function methods:uniqueMobs()
	local seen, n = {}, 0
	for name in pairs(self.db.mobs) do
		seen[name] = true
		n = n + 1
	end
	for _, entry in pairs(self.db.raids) do
		if entry.name and not seen[entry.name] then
			seen[entry.name] = true
			n = n + 1
		end
	end
	return n
end

function methods:uniquePlayers()
	local n = 0
	for _ in pairs(self.db.players) do
		n = n + 1
	end
	return n
end

-- Different souls in the dex: unique mobs (raid creatures included) plus unique players.
-- Record results carry it as `total` after the catch (the popup's "Soul #N").
function methods:uniqueSouls()
	return self:uniqueMobs() + self:uniquePlayers()
end

-- What one saved entry has scored. A dex received from a friend (db.flat) already carries
-- each entry's full worth in `points`.
function methods:worth(entry, isPlayer)
	if self.db.flat then
		return entry.points or 0
	elseif isPlayer then
		return ns.Points.playerWorth(entry)
	end
	return ns.Points.mobWorth(entry)
end

function methods:score()
	local db = self.db
	local total = 0
	for _, entry in pairs(db.mobs) do
		total = total + self:worth(entry)
	end
	for _, entry in pairs(db.raids) do
		total = total + self:worth(entry)
	end
	for _, entry in pairs(db.players) do
		total = total + self:worth(entry, true)
	end
	return total
end

-- A saved mob or raid entry's mastery: stars, claims, and the claim counts its current
-- star began at and the next comes at. nil for souls that earn no stars (bosses, rares),
-- and for a friend's raid creatures (their dex doesn't say which are bosses).
function methods:stars(entry)
	local flat = self.db.flat
	if (flat and entry.instanceID) or ns.Points.rule(entry, flat) ~= "mastery" then
		return nil
	end
	local count = ns.Points.count(entry)
	local from, to = ns.Points.starSpan(count)
	return ns.Points.stars(count), count, from, to
end

-- Mastery stars across the dex (mobs and raid creatures that earn them).
function methods:masteryStars()
	local n = 0
	for _, collection in ipairs({ self.db.mobs, self.db.raids }) do
		for _, entry in pairs(collection) do
			n = n + (self:stars(entry) or 0)
		end
	end
	return n
end

-- Known raid creatures caught, and how many the raid lists.
function methods:raidProgress(instanceID)
	local raid = ns.Raids.byInstance(instanceID)
	if not raid then
		return 0, 0
	end
	local caught = 0
	for _, mob in ipairs(raid.mobs) do
		local entry = self.db.raids[mob.id]
		if entry and entry.instanceID == instanceID then
			caught = caught + 1
		end
	end
	return caught, #raid.mobs
end

function methods:raidsCompleted()
	local n = 0
	for _, raid in ipairs(ns.Raids.list()) do
		local caught, total = self:raidProgress(raid.instanceID)
		if total > 0 and caught == total then
			n = n + 1
		end
	end
	return n
end
