-- Capture glue: watches unit info, the combat log and the bags, records catches,
-- shows the popup and announces milestones. The decision helpers are pure and tested;
-- the event wiring below them is game code.
--
-- Hooks (plain lists of functions, so later modules can add their own work):
--   ns.onLoaded  functions called with (db) at the end of ns.OnLoaded
--   ns.onCatch   functions called with (result, entry) after every recorded catch, where
--                result is the Dex.record* result ({ isNew, points, placeCount, kind })
--                and entry is { info = <mob/player info>, ctx = <catch context>, kind = <result.kind> }
local _, ns = ...

local Capture = {}
ns.Capture = Capture

ns.onLoaded = ns.onLoaded or {}
ns.onCatch = ns.onCatch or {}

local SHARD_ITEM_ID = 6265
local DRAIN_SOUL_ID = 1120
local SHADOWBURN_ID = 17877
local FALLBACK_SOUND = 8959
local MAX_BAG = 4
local CONTINENT_MAP_TYPE = 2
local CONTINENT_NAMES = { [1414] = "Kalimdor", [1415] = "Eastern Kingdoms" }

Capture.SHARD_ITEM_ID = SHARD_ITEM_ID

-- Pure helpers ---------------------------------------------------------------

-- NPC ID is field 6 of "Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID".
function Capture.npcIdFromGuid(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local parts = {}
	for part in guid:gmatch("[^-]+") do
		parts[#parts + 1] = part
	end
	if parts[1] ~= "Creature" and parts[1] ~= "Vehicle" then
		return nil
	end
	return tonumber(parts[6])
end

function Capture.isPlayerGuid(guid)
	return type(guid) == "string" and guid:sub(1, 7) == "Player-"
end

-- Walks up the map tree to the continent. getInfo(id) -> { mapType, parentMapID, name } or nil.
function Capture.continentOf(mapID, getInfo)
	local id, steps = mapID, 0
	while id and id ~= 0 and steps < 20 do
		local info = getInfo(id)
		if not info then
			return nil
		end
		if info.mapType == CONTINENT_MAP_TYPE then
			return CONTINENT_NAMES[id] or info.name
		end
		id = info.parentMapID
		steps = steps + 1
	end
	return nil
end

function Capture.groupFor(instanceType, continent)
	if instanceType == "party" then
		return "Dungeons"
	end
	return continent or "Other"
end

-- "Name-Realm" -> name, realm. A bare name keeps the fallback realm.
function Capture.splitName(full, fallbackRealm)
	if not full then
		return nil, fallbackRealm
	end
	local name, realm = full:match("^([^-]+)-(.+)$")
	if name then
		return name, realm
	end
	return full, fallbackRealm
end

local function hex(r, g, b)
	local function byte(v)
		return math.floor(v * 255 + 0.5)
	end
	return string.format("%02x%02x%02x", byte(r), byte(g), byte(b))
end

local RARITY_COLORS = {
	elite = "ffcc33",
	rare = "9fb8d0",
	rareelite = "9fb8d0",
	worldboss = "ff5050",
}
local NORMAL_COLOR = "ffffff"

-- Hex colour (no "|cff") for a caught thing: class colour for players, rarity for mobs.
-- classColors is RAID_CLASS_COLORS (or nil).
function Capture.colorFor(info, classColors)
	if info.class then
		local c = classColors and classColors[info.class]
		if c then
			return hex(c.r, c.g, c.b)
		end
		return NORMAL_COLOR
	end
	return RARITY_COLORS[info.classification] or NORMAL_COLOR
end

-- Records a matched candidate { guid, info } into the dex. Returns result, kind (or nil if
-- the candidate can't be recorded). ctx must already hold time, myLevel, zone, group, x, y.
function Capture.recordCatch(dex, cand, ctx, instanceType, instanceID)
	local info = cand.info
	if not info or not info.name or not ctx.zone then
		return nil
	end
	if Capture.isPlayerGuid(cand.guid) then
		return dex:recordPlayer(info, ctx), "player"
	end
	if instanceType == "raid" and instanceID then
		local npcID = Capture.npcIdFromGuid(cand.guid)
		if npcID then
			return dex:recordRaid(info, ctx, instanceID, npcID), "raid"
		end
	end
	return dex:recordMob(info, ctx), "mob"
end

-- Calls fn(...) in protected mode; an error goes to handler(err) instead of propagating.
function Capture.protect(handler, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and handler then
		handler(err)
	end
	return ok
end

-- Calls every hook with (...), each protected, so one bad hook can't stop the others.
function Capture.runHooks(hooks, handler, ...)
	for _, fn in ipairs(hooks) do
		Capture.protect(handler, fn, ...)
	end
end

-- Game wiring ------------------------------------------------------------------

local function unitInfo(unit)
	local info = {
		name = UnitName(unit),
		level = UnitLevel(unit),
		classification = UnitClassification(unit),
		creatureType = UnitCreatureType(unit),
		family = UnitCreatureFamily(unit),
	}
	if info.level and info.level < 1 then
		info.level = nil -- "??" skull level
	end
	if UnitIsPlayer(unit) then
		local _, realm = UnitName(unit)
		info.realm = (realm and realm ~= "") and realm or GetRealmName()
		info.guild = GetGuildInfo(unit)
		local _, classToken = UnitClass(unit)
		info.class = classToken
		info.race = UnitRace(unit)
	end
	return info
end

local function noteUnit(matcher, unit)
	if not UnitExists(unit) then
		return
	end
	local guid = UnitGUID(unit)
	if guid and guid ~= UnitGUID("player") then
		matcher:noteUnit(guid, unitInfo(unit), GetTime())
	end
end

local function buildContext()
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	local mapID = C_Map.GetBestMapForUnit("player")
	local continent = mapID and Capture.continentOf(mapID, C_Map.GetMapInfo)
	local zone = GetRealZoneText()
	if not zone or zone == "" then
		zone = GetZoneText()
	end
	if not zone or zone == "" then
		zone = "Unknown"
	end
	local ctx = {
		time = time(),
		myLevel = UnitLevel("player"),
		zone = zone,
		group = Capture.groupFor(instanceType, continent),
	}
	if instanceType == "none" and mapID then
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		if pos then
			local x, y = pos:GetXY()
			if x and y and (x ~= 0 or y ~= 0) then
				ctx.x, ctx.y = x * 100, y * 100
			end
		end
	end
	return ctx, instanceType, instanceID
end

local function afterCatch(db, dex, result, entry)
	local settings = db.settings
	if result.isNew then
		if settings.popup and ns.Toast then
			ns.Toast.show(result, entry.info, entry.ctx)
		end
		if settings.sound then
			local kit = SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST or FALLBACK_SOUND
			pcall(PlaySound, kit)
		end
	end
	for _, m in ipairs(ns.Milestones.check(dex, time())) do
		ns.Print("Milestone earned: " .. m.text)
		if m.announce and settings.announce and IsInGuild() then
			SendChatMessage("Soul-Dex: " .. m.text .. "!", "GUILD")
		end
	end
	Capture.runHooks(ns.onCatch, geterrorhandler(), result, entry)
end

local function fillPlayerInfo(cand)
	if Capture.isPlayerGuid(cand.guid) then
		local _, classToken, race = GetPlayerInfoByGUID(cand.guid)
		local info = cand.info
		info.class = info.class or classToken
		info.race = info.race or race
		local name, realm = Capture.splitName(info.name, info.realm)
		info.name = name
		info.realm = (realm and realm ~= "") and realm or GetRealmName()
	end
end

-- Records the candidate and returns the soul to remember for its shard, or nil,
-- plus the entry for afterCatch (run by the caller once the map is saved).
local function record(dex, cand)
	fillPlayerInfo(cand)
	local ctx, instanceType, instanceID = buildContext()
	local result, kind = Capture.recordCatch(dex, cand, ctx, instanceType, instanceID)
	if not result then
		return nil
	end
	local soul = {
		name = cand.info.name,
		color = Capture.colorFor(cand.info, RAID_CLASS_COLORS),
		zone = ctx.zone,
		time = ctx.time,
	}
	return soul, { result = result, entry = { info = cand.info, ctx = ctx, kind = kind } }
end

local function shardSlots()
	local slots = {}
	for bag = 0, MAX_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			if C_Container.GetContainerItemID(bag, slot) == SHARD_ITEM_ID then
				slots[#slots + 1] = bag .. ":" .. slot
			end
		end
	end
	return slots
end

function Capture.start(db)
	local dex = ns.Dex.new(db)
	ns.dex = dex
	local matcher = ns.Catch.new()
	local scanned = false -- the baseline scan has run
	local scheduled = false
	local drainSoul, shadowburn = GetSpellInfo(DRAIN_SOUL_ID), GetSpellInfo(SHADOWBURN_ID)

	local function scanBags()
		local firstScan = not scanned
		scanned = true
		local newMap, gained = ns.Shards.update(db.shardSlots, shardSlots(), firstScan)
		local done = {}
		for _, slot in ipairs(gained) do
			local cand = matcher:takeCandidate(GetTime())
			local soul, after
			if cand then
				soul, after = record(dex, cand)
			end
			newMap = ns.Shards.assign(newMap, slot, soul or false)
			if after then
				done[#done + 1] = after
			end
		end
		db.shardSlots = newMap
		-- Saved first: nothing below can lose a catch.
		for _, d in ipairs(done) do
			Capture.protect(geterrorhandler(), afterCatch, db, dex, d.result, d.entry)
		end
	end

	-- The baseline waits a second after login so every bag has reported its slots.
	local function onEnterWorld()
		if scanned or scheduled then
			return
		end
		scheduled = true
		C_Timer.After(1, scanBags)
	end

	local function onBagUpdate()
		if scanned then
			scanBags()
		end
	end

	local function combatLog()
		local _, sub, _, sourceGUID, _, _, _, destGUID, destName, _, _, _, spellName = CombatLogGetCurrentEventInfo()
		local now = GetTime()
		if sub == "UNIT_DIED" or sub == "PARTY_KILL" then
			matcher:noteDeath(destGUID, destName, now)
			return
		end
		if sourceGUID ~= UnitGUID("player") then
			return
		end
		local kind
		if spellName == drainSoul then
			kind = "drainsoul"
		elseif spellName == shadowburn then
			kind = "shadowburn"
		else
			return
		end
		if sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" then
			matcher:noteAura(destGUID, kind, now)
		elseif sub == "SPELL_AURA_REMOVED" then
			matcher:noteAuraGone(destGUID, kind, now)
		end
	end

	local handlers = {
		PLAYER_TARGET_CHANGED = function() noteUnit(matcher, "target") end,
		UPDATE_MOUSEOVER_UNIT = function() noteUnit(matcher, "mouseover") end,
		NAME_PLATE_UNIT_ADDED = function(unit) noteUnit(matcher, unit) end,
		COMBAT_LOG_EVENT_UNFILTERED = combatLog,
		BAG_UPDATE_DELAYED = onBagUpdate,
		PLAYER_ENTERING_WORLD = onEnterWorld,
	}
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		handlers[event](...)
	end)
end

function ns.OnLoaded(db)
	db.settings = ns.Settings.normalise(db.settings)
	db.shardSlots = db.shardSlots or {}
	ns.db = db
	Capture.start(db)
	for _, fn in ipairs(ns.onLoaded) do
		fn(db)
	end
end
