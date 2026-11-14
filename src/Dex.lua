-- The dex model: what has been caught, where, and how many soul points it is
-- worth (pure; no WoW API). Works on the SoulDexDB table it is given.
local _, ns = ...

local Dex = {}
ns.Dex = Dex

local methods = {}
local meta = { __index = methods }

function Dex.new(db)
	for _, key in ipairs({ "mobs", "places", "players", "raids", "milestones", "unknown" }) do
		if type(db[key]) ~= "table" then
			db[key] = {} -- missing, or damaged saved data
		end
	end
	return setmetatable({ db = db }, meta)
end

local function notePlace(db, ctx)
	if ctx.zone and not db.places[ctx.zone] then
		db.places[ctx.zone] = { group = ctx.group }
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
	local entry = db.mobs[info.name]
	local isNew = entry == nil
	local points = 0
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
	entry.last = ctx.time
	noteLevel(entry, info.level)
	local place = entry.places[ctx.zone]
	if not place then
		place = { count = 0, first = ctx.time, myLevel = ctx.myLevel, x = ctx.x, y = ctx.y }
		entry.places[ctx.zone] = place
	end
	place.count = place.count + 1
	place.last = ctx.time
	return { isNew = isNew, points = points, total = self:uniqueSouls(), kind = "mob" }
end

function methods:recordPlayer(info, ctx)
	local db = self.db
	notePlace(db, ctx)
	local key = info.name .. "-" .. (info.realm or "")
	local entry = db.players[key]
	local isNew = entry == nil
	local points = 0
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
	return { isNew = isNew, points = points, total = self:uniqueSouls(), kind = "player" }
end

function methods:recordRaid(info, ctx, instanceID, npcID)
	local db = self.db
	local _, known = ns.Raids.find(instanceID, npcID)
	local entry = db.raids[npcID]
	local isNew = entry == nil
	local points = 0
	local before
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
	-- A new raid slot whose name the dex already has (spec 4.5) adds no soul: no total, so
	-- the popup shows no repeated "Soul #N".
	local total = self:uniqueSouls()
	if total == before then
		total = nil
	end
	return { isNew = isNew, points = points, total = total, kind = "raid" }
end

-- A soul whose name the game hid (spec 4.4): counted per zone only. No points, not a
-- unique mob, not new, so no popup and no milestone progress.
function methods:recordUnknown(ctx)
	local db = self.db
	notePlace(db, ctx)
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

function methods:score()
	local total = 0
	for _, collection in ipairs({ self.db.mobs, self.db.players, self.db.raids }) do
		for _, entry in pairs(collection) do
			total = total + (entry.points or 0)
		end
	end
	return total
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
