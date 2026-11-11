-- Capture glue: watches your Drain Soul / Shadowburn casts and the bags, records catches,
-- shows the popup and announces milestones. The decision helpers are pure and tested;
-- the event wiring below them is game code.
--
-- WoW: Forever blocks the combat log for addons and may hand back "secret" values: every
-- value read from the game goes through the readable/plainString/plainNumber checks
-- before it is compared, indexed, joined or saved.
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
local DEFAULT_LAST_BAG = 4
local SENT_TTL = 30 -- seconds a UNIT_SPELLCAST_SENT reading stays usable
local SENT_CHECK = 1 -- seconds a SENT target name cross-checks a channel with another cast id
local BASELINE_DELAY = 1
local CONTINENT_MAP_TYPE = 2
local CONTINENT_NAMES = { [1414] = "Kalimdor", [1415] = "Eastern Kingdoms" }
local UNKNOWN_SOUL = "Unknown soul"

-- Every rank, so a rank whose name can't be read still counts.
local DRAIN_SOUL_IDS = { [1120] = true, [8288] = true, [8289] = true, [11675] = true }
local SHADOWBURN_IDS = {
	[17877] = true, [18867] = true, [18868] = true, [18869] = true, [18870] = true, [18871] = true,
}

Capture.SHARD_ITEM_ID = SHARD_ITEM_ID
Capture.UNKNOWN_SOUL = UNKNOWN_SOUL

-- Secret-value guards -----------------------------------------------------------------

-- False for a secret value. Clients without issecretvalue have no secrets.
function Capture.readable(v)
	return not (issecretvalue and issecretvalue(v))
end
local readable = Capture.readable

function Capture.plainString(v)
	return readable(v) and type(v) == "string" and v ~= ""
end
local plainString = Capture.plainString

function Capture.plainNumber(v)
	return readable(v) and type(v) == "number"
end
local plainNumber = Capture.plainNumber

function Capture.readableTable(v)
	return readable(v) and type(v) == "table" and (not canaccesstable or canaccesstable(v))
end
local readableTable = Capture.readableTable

local function unpackOk(ok, ...)
	if ok then
		return ...
	end
end

-- fn(...) in protected mode; nothing when fn is missing or errors.
function Capture.call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	return unpackOk(pcall(fn, ...))
end
local call = Capture.call

local function str(v)
	return plainString(v) and v or nil
end

local function num(v)
	return plainNumber(v) and v or nil
end

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

-- "drainsoul", "shadowburn" or nil for a spell ID. names: { drainsoul = <name>,
-- shadowburn = <name> } (either may be nil); nameOf(id) gives a spell's name or nil.
function Capture.spellKind(spellID, nameOf, names)
	if DRAIN_SOUL_IDS[spellID] then
		return "drainsoul"
	end
	if SHADOWBURN_IDS[spellID] then
		return "shadowburn"
	end
	local name = nameOf and nameOf(spellID)
	if name == nil then
		return nil
	end
	if names.drainsoul and name == names.drainsoul then
		return "drainsoul"
	end
	if names.shadowburn and name == names.shadowburn then
		return "shadowburn"
	end
	return nil
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

-- Records a captured target { guid, info } into the dex. Returns result, kind (or nil if
-- it can't be recorded). ctx must already hold time, myLevel, zone, group, x, y.
function Capture.recordCatch(dex, cand, ctx, instanceType, instanceID)
	local info = cand.info
	if not info or not info.name or info.unknown or not ctx.zone then
		return nil
	end
	if info.isPlayer or Capture.isPlayerGuid(cand.guid) then
		return dex:recordPlayer(info, ctx), "player"
	end
	if instanceType == "raid" then
		local npcID = Capture.npcIdFromGuid(cand.guid)
		if instanceID and npcID and ns.Raids.byInstance(instanceID) then
			return dex:recordRaid(info, ctx, instanceID, npcID), "raid"
		end
		-- A raid we do not list: a plain mob, under its own "Raids" group.
		local raidCtx = {}
		for k, v in pairs(ctx) do
			raidCtx[k] = v
		end
		raidCtx.group = "Raids"
		return dex:recordMob(info, raidCtx), "mob"
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

-- Game reads (each value checked) ----------------------------------------------------------

local function errorHandler()
	local handler = call(geterrorhandler)
	if type(handler) == "function" then
		return handler
	end
	return function() end
end

local function isUnknownName(name)
	return not plainString(name) or (UNKNOWN ~= nil and name == UNKNOWN)
		or (UNKNOWNOBJECT ~= nil and name == UNKNOWNOBJECT)
end

-- The unit's details. A hidden or unknown name gives { unknown = true, isPlayer, guid }.
-- sentName: the target name UNIT_SPELLCAST_SENT reported, when readable: if it differs
-- from the unit's name the spell went elsewhere (a mouseover macro), so the name is
-- not trusted.
function Capture.readUnit(unit, sentName)
	local guid = str(call(UnitGUID, unit))
	local isPlayer = call(UnitIsPlayer, unit)
	if readable(isPlayer) and isPlayer ~= nil then
		isPlayer = isPlayer and true or false
	else
		isPlayer = nil
	end
	if isPlayer == nil and guid then
		isPlayer = Capture.isPlayerGuid(guid)
	end
	local name, realm = call(UnitName, unit)
	if isUnknownName(name) then
		return { unknown = true, isPlayer = isPlayer, guid = guid }
	end
	if plainString(sentName) then
		local full = plainString(realm) and (name .. "-" .. realm) or name
		if sentName ~= name and sentName ~= full then
			return { unknown = true, isPlayer = isPlayer, guid = guid }
		end
	end
	local info = {
		name = name,
		guid = guid,
		isPlayer = isPlayer,
		level = num(call(UnitLevel, unit)),
		classification = str(call(UnitClassification, unit)),
		creatureType = str(call(UnitCreatureType, unit)),
		family = str(call(UnitCreatureFamily, unit)),
	}
	if info.level and info.level < 1 then
		info.level = nil -- "??" skull level
	end
	if isPlayer then
		local bare, fromName = Capture.splitName(name, str(realm))
		info.name = bare
		info.realm = fromName or str(call(GetRealmName))
		info.guild = str(call(GetGuildInfo, unit))
		local _, classToken = call(UnitClass, unit)
		info.class = str(classToken)
		info.race = str(call(UnitRace, unit))
	end
	return info
end

local function mapInfo(id)
	local info = C_Map and call(C_Map.GetMapInfo, id)
	if not readableTable(info) then
		return nil
	end
	return { mapType = num(info.mapType), parentMapID = num(info.parentMapID), name = str(info.name) }
end

-- Where and when: { time, myLevel, zone, group, x, y }, instance type and ID.
function Capture.buildContext()
	local _, instanceType, _, _, _, _, _, instanceID = call(GetInstanceInfo)
	instanceType, instanceID = str(instanceType), num(instanceID)
	local mapID = C_Map and num(call(C_Map.GetBestMapForUnit, "player"))
	local continent = mapID and Capture.continentOf(mapID, mapInfo)
	local zone = str(call(GetRealZoneText)) or str(call(GetZoneText)) or "Unknown"
	local ctx = {
		time = time(),
		myLevel = num(call(UnitLevel, "player")),
		zone = zone,
		group = Capture.groupFor(instanceType, continent),
	}
	if instanceType == "raid" then
		ctx.group = "Raids"
	end
	if instanceType == "none" and mapID then
		local pos = call(C_Map.GetPlayerMapPosition, mapID, "player")
		if readableTable(pos) then
			local x, y = call(pos.GetXY, pos)
			if plainNumber(x) and plainNumber(y) and (x ~= 0 or y ~= 0) then
				ctx.x, ctx.y = x * 100, y * 100
			end
		end
	end
	return ctx, instanceType, instanceID
end

-- The readable GUID of the item in a bag slot, or nil.
function Capture.itemGuid(bag, slot)
	if not (C_Item and ItemLocation) then
		return nil
	end
	local location = call(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
	if not location then
		return nil
	end
	return str(call(C_Item.GetItemGUID, location))
end

local function lastBag()
	return num(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or num(NUM_BAG_SLOTS) or DEFAULT_LAST_BAG
end

-- Readable GUIDs of every Soul Shard in the bags, and how many slots could not be read
-- (a secret item ID, or a shard whose GUID is secret or missing).
function Capture.shardGuids()
	local guids, unreadable = {}, 0
	for bag = 0, lastBag() do
		local slots = num(call(C_Container.GetContainerNumSlots, bag)) or 0
		for slot = 1, slots do
			local itemID = call(C_Container.GetContainerItemID, bag, slot)
			if not readable(itemID) then
				unreadable = unreadable + 1
			elseif plainNumber(itemID) and itemID == SHARD_ITEM_ID then
				local guid = Capture.itemGuid(bag, slot)
				if guid then
					guids[#guids + 1] = guid
				else
					unreadable = unreadable + 1
				end
			end
		end
	end
	return guids, unreadable
end

-- Something on the cursor (or an unreadable answer): new shards are not trusted.
local function cursorBusy()
	if type(GetCursorInfo) ~= "function" then
		return false
	end
	local ok, what = pcall(GetCursorInfo)
	if not ok then
		return false
	end
	return not readable(what) or what ~= nil
end

-- Recording ---------------------------------------------------------------------------

-- Guild chat through C_ChatInfo when the client has it; never raises (chat lockdown,
-- deprecated global).
local function announce(text)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	call(send, text, "GUILD")
end

local function milestones(db, dex)
	local settings = db.settings
	for _, m in ipairs(ns.Milestones.check(dex, time())) do
		Capture.protect(errorHandler(), function()
			ns.Print("Milestone earned: " .. m.text)
			local inGuild = call(IsInGuild)
			if m.announce and settings.announce and readable(inGuild) and inGuild then
				announce("Soul-Dex: " .. m.text .. "!")
			end
		end)
	end
end

local function popup(db, result, entry)
	local settings = db.settings
	if settings.popup and ns.Toast then
		ns.Toast.show(result, entry.info, entry.ctx)
	end
	if settings.sound then
		local kit = SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST or FALLBACK_SOUND
		pcall(PlaySound, kit)
	end
end

-- Each step is protected: nothing here can skip the catch hooks.
local function afterCatch(db, dex, result, entry)
	if result.isNew then
		Capture.protect(errorHandler(), popup, db, result, entry)
	end
	Capture.protect(errorHandler(), milestones, db, dex)
	Capture.runHooks(ns.onCatch, errorHandler(), result, entry)
end

-- Records the capture and returns the soul to remember for its shard (or nil), plus the
-- work for afterCatch (run by the caller once the map is saved).
function Capture.record(dex, capture)
	local info = capture.info
	local ctx, instanceType, instanceID = Capture.buildContext()
	if info.unknown then
		local result = dex:recordUnknown(ctx)
		local soul = { name = UNKNOWN_SOUL, unknown = true, zone = ctx.zone, time = ctx.time }
		return soul, { result = result, entry = { info = info, ctx = ctx, kind = "unknown" } }
	end
	local result, kind = Capture.recordCatch(dex, { guid = info.guid, info = info }, ctx, instanceType, instanceID)
	if not result then
		return nil
	end
	local soul = {
		name = info.name,
		color = Capture.colorFor(info, RAID_CLASS_COLORS),
		zone = ctx.zone,
		time = ctx.time,
	}
	return soul, { result = result, entry = { info = info, ctx = ctx, kind = kind } }
end

-- Event wiring ------------------------------------------------------------------------------

local UNIT_EVENTS = {
	"UNIT_SPELLCAST_SENT",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_SUCCEEDED",
}
local EVENTS = {
	"PLAYER_ENTERING_WORLD",
	"BAG_UPDATE_DELAYED",
	"PLAYER_REGEN_ENABLED",
	"BANKFRAME_OPENED",
	"BANKFRAME_CLOSED",
}

-- Registers each event on its own, so one the client refuses can't stop the rest.
-- Returns the names that failed.
function Capture.register(frame, events, unitEvents)
	local failed = {}
	for _, event in ipairs(events) do
		if not pcall(frame.RegisterEvent, frame, event) then
			failed[#failed + 1] = event
		end
	end
	for _, event in ipairs(unitEvents) do
		local ok
		if frame.RegisterUnitEvent then
			ok = pcall(frame.RegisterUnitEvent, frame, event, "player")
		else
			ok = pcall(frame.RegisterEvent, frame, event)
		end
		if not ok then
			failed[#failed + 1] = event
		end
	end
	return failed
end

-- dex: the Dex on db (ns.dex). Returns the event handler table (for tests).
function Capture.start(db, dex)
	dex = dex or ns.dex or ns.Dex.new(db)
	ns.dex = dex
	local window = ns.Catch.new()
	local scanned, baselineQueued, scanQueued = false, false, false
	local bankOpen = false
	local sent -- { castGUID, kind, info, targetName, time } from the last UNIT_SPELLCAST_SENT
	local lastUnreadable = 0 -- unreadable shard slots in the previous scan
	local names = {
		drainsoul = C_Spell and str(call(C_Spell.GetSpellName, DRAIN_SOUL_ID)),
		shadowburn = C_Spell and str(call(C_Spell.GetSpellName, SHADOWBURN_ID)),
	}
	local function nameOf(id)
		return C_Spell and str(call(C_Spell.GetSpellName, id))
	end

	local function scanBags()
		local firstScan = not scanned
		scanned = true
		local now = time()
		local present, unreadable = Capture.shardGuids()
		-- A shard slot we couldn't read now (or last scan) may hold an old shard that turns
		-- readable later: no shard is named until two scans in a row read every slot.
		local quiet = firstScan or bankOpen or cursorBusy() or unreadable > 0 or lastUnreadable > 0
		lastUnreadable = unreadable
		local map, gained = ns.Shards.update(db.shardSouls, present, quiet, now, firstScan)
		local done = {}
		for _, guid in ipairs(gained) do
			local soul, after
			local capture = window:take(GetTime())
			if capture then
				soul, after = Capture.record(dex, capture)
			end
			map = ns.Shards.assign(map, guid, soul or false, now)
			if after then
				done[#done + 1] = after
			end
		end
		db.shardSouls = map
		-- Saved first: nothing below can lose a catch.
		for _, d in ipairs(done) do
			Capture.protect(errorHandler(), afterCatch, db, dex, d.result, d.entry)
		end
	end

	local function queueScan()
		if not scanned or scanQueued then
			return
		end
		scanQueued = true
		C_Timer.After(0, function()
			scanQueued = false
			Capture.protect(errorHandler(), scanBags)
		end)
	end

	-- The baseline waits a second after login so every bag has reported its slots.
	local function onEnterWorld()
		if scanned or baselineQueued then
			return
		end
		baselineQueued = true
		C_Timer.After(BASELINE_DELAY, function()
			Capture.protect(errorHandler(), scanBags)
		end)
	end

	-- The target's details for a channel start / Shadowburn success: the SENT reading
	-- when the cast ids match; otherwise the target read now, cross-checked against the
	-- name a SENT of the same spell under SENT_CHECK s ago reported (a mouseover macro
	-- whose channel event carries another, nil or secret cast id).
	local function targetInfo(castGUID, kind, now)
		if sent and sent.kind == kind and castGUID and sent.castGUID == castGUID and now - sent.time <= SENT_TTL then
			return sent.info
		end
		local check
		if sent and sent.kind == kind and now - sent.time <= SENT_CHECK then
			check = sent.targetName
		end
		return Capture.readUnit("target", check)
	end

	-- unit, castGUID, spellID as the event gave them; returns kind, castGUID or nil when
	-- the event is unreadable (after telling the window).
	local function spellOf(isChannelStart, unit, castGUID, spellID)
		if not readable(unit) or not readable(spellID) then
			window:restricted(isChannelStart, GetTime())
			return nil
		end
		if unit ~= "player" or not plainNumber(spellID) then
			return nil
		end
		return Capture.spellKind(spellID, nameOf, names), str(castGUID)
	end

	local handlers = {}

	handlers.UNIT_SPELLCAST_SENT = function(unit, targetName, castGUID, spellID)
		local kind, cast = spellOf(false, unit, castGUID, spellID)
		if kind then
			sent = {
				castGUID = cast,
				kind = kind,
				info = Capture.readUnit("target", targetName),
				targetName = str(targetName),
				time = GetTime(),
			}
		end
	end

	handlers.UNIT_SPELLCAST_CHANNEL_START = function(unit, castGUID, spellID)
		local kind, cast = spellOf(true, unit, castGUID, spellID)
		if kind == "drainsoul" then
			local now = GetTime()
			local info = targetInfo(cast, kind, now)
			window:startCapture("drainsoul", info, cast, now)
		end
		queueScan()
	end

	handlers.UNIT_SPELLCAST_CHANNEL_STOP = function(unit, castGUID, spellID)
		local kind, cast = spellOf(false, unit, castGUID, spellID)
		if kind == "drainsoul" then
			window:channelStopped(cast, GetTime())
		end
		queueScan()
	end

	handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID, spellID)
		local kind, cast = spellOf(false, unit, castGUID, spellID)
		if kind == "shadowburn" then
			local now = GetTime()
			local info = targetInfo(cast, kind, now)
			window:startCapture("shadowburn", info, cast, now)
		end
		queueScan()
	end

	handlers.PLAYER_ENTERING_WORLD = onEnterWorld
	handlers.BAG_UPDATE_DELAYED = queueScan
	handlers.PLAYER_REGEN_ENABLED = queueScan
	handlers.BANKFRAME_OPENED = function()
		bankOpen = true
	end
	handlers.BANKFRAME_CLOSED = function()
		bankOpen = false
		queueScan()
	end

	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		local fn = handlers[event]
		if fn then
			Capture.protect(errorHandler(), fn, ...)
		end
	end)
	local failed = Capture.register(frame, EVENTS, UNIT_EVENTS)
	if #failed > 0 and ns.Print then
		ns.Print("The game refused some events (" .. table.concat(failed, ", ") .. "); catching may miss souls.")
	end
	return handlers
end

function ns.OnLoaded(db)
	db.settings = ns.Settings.normalise(db.settings)
	db.shardSlots = nil -- slot map from an unreleased build; souls are keyed by item GUID now
	if type(db.shardSouls) ~= "table" then
		db.shardSouls = {}
	end
	ns.db = db
	ns.dex = ns.Dex.new(db)
	Capture.protect(function(err)
		if ns.Print then
			ns.Print("Catching could not start: " .. tostring(err))
		end
		errorHandler()(err)
	end, Capture.start, db, ns.dex)
	Capture.runHooks(ns.onLoaded, errorHandler(), db)
end
