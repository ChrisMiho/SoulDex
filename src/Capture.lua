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
--                result is the Dex.record* result ({ isNew, points, total, kind })
--                and entry is { info = <mob/player info>, ctx = <catch context>, kind = <result.kind>,
--                color = <soul hex colour, or nil for an unknown soul> }
local _, ns = ...

local Capture = {}
ns.Capture = Capture

ns.onLoaded = ns.onLoaded or {}
ns.onCatch = ns.onCatch or {}

local SHARD_ITEM_ID = ns.Shards.ITEM_ID
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

local NORMAL_COLOR = "ffffff"

-- Hex colour (no "|cff") for a caught thing: class colour for players, rarity for mobs,
-- the same ones the window uses (ns.Rarity). classColors is RAID_CLASS_COLORS (or nil).
function Capture.colorFor(info, classColors)
	if info.class then
		return ns.Rarity.classHex(info.class, classColors) or NORMAL_COLOR
	end
	return ns.Rarity.color(info.classification) or NORMAL_COLOR
end

-- Records a captured target { guid, info } into the dex. Returns result, kind (or nil if
-- it can't be recorded). ctx must already hold time, myLevel, zone, group, x, y (as
-- buildContext gives them: a raid-type instance is already grouped under "Raids").
function Capture.recordCatch(dex, cand, ctx, instanceType, instanceID)
	local info = cand.info
	if not info or not info.name or info.unknown then
		return nil
	end
	if info.isPlayer or Capture.isPlayerGuid(cand.guid) then
		return dex:recordPlayer(info, ctx), "player"
	end
	if instanceType == "raid" then
		local npcID = Capture.npcIdFromGuid(cand.guid)
		if instanceID and npcID and dex:raidFor(instanceID, ctx.instanceName) then
			return dex:recordRaid(info, ctx, instanceID, npcID), "raid"
		end
		-- A raid we do not list: a plain mob (ctx.group is already "Raids").
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
-- sentName: the target name UNIT_SPELLCAST_SENT reported: if it differs from the unit's
-- name the spell went elsewhere (a mouseover macro), so the name is not trusted. A secret
-- sentName can't be compared, so it is not trusted either.
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
	if isUnknownName(name) or (sentName ~= nil and not readable(sentName)) then
		return { unknown = true, isPlayer = isPlayer, guid = guid }
	end
	if plainString(sentName) then
		local dashed = plainString(realm) and (name .. "-" .. realm) or name
		local spaced = plainString(realm) and (name .. " " .. realm) or name
		if sentName ~= name and sentName ~= dashed and sentName ~= spaced then
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
		-- WoW: Forever: UnitName's second value is the second half of the name
		-- ("Forgot", "Shards" for "Forgot Shards"), not a realm.
		info.name = ns.Friends.fullName(name, str(realm)) or name
		info.realm = str(call(GetRealmName))
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

-- Where and when: { time, myLevel, zone, group, instanceName, x, y }, instance type and ID.
function Capture.buildContext()
	local instanceName, instanceType, _, _, _, _, _, instanceID = call(GetInstanceInfo)
	instanceType, instanceID = str(instanceType), num(instanceID)
	local mapID = C_Map and num(call(C_Map.GetBestMapForUnit, "player"))
	local continent = mapID and Capture.continentOf(mapID, mapInfo)
	local zone = str(call(GetRealZoneText)) or str(call(GetZoneText)) or "Unknown"
	local ctx = {
		time = time(),
		myLevel = num(call(UnitLevel, "player")),
		zone = zone,
		group = Capture.groupFor(instanceType, continent),
		instanceName = str(instanceName), -- matches a raid whose instance id is not known yet
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

-- Guild announcements. During a boss encounter (and Mythic+) the game silently drops
-- addon messages to guild: pcall still succeeds, so the message would just vanish. While
-- chat is locked (or the answer is secret) messages wait in db.announceQueue, saved over
-- a reload, and go out when the lockdown ends. A held message expires after an hour.

local QUEUE_MAX = 10
local QUEUE_TTL = 3600

-- True for a readable true from fn(); a secret answer counts as true when secretIs is.
local function yes(fn, secretIs)
	local v = call(fn)
	if not readable(v) then
		return secretIs
	end
	return v == true
end

local function chatLocked()
	return yes(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown, true) or yes(IsEncounterInProgress, true)
end

-- Guild chat through C_ChatInfo when the client has it; never raises (deprecated global).
local function send(text)
	local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	call(fn, text, "GUILD")
end

-- Keeps the held messages still worth sending, oldest first.
local function liveQueue(db, now)
	local kept = {}
	if type(db.announceQueue) == "table" then
		for _, item in ipairs(db.announceQueue) do
			if type(item) == "table" and type(item.text) == "string" and type(item.at) == "number"
				and now - item.at <= QUEUE_TTL then
				kept[#kept + 1] = item
			end
		end
	end
	return kept
end

-- Sends every held message if chat is open and you're in a guild; drops them all when
-- announcements are off.
function Capture.flushAnnouncements(db)
	local queue = liveQueue(db, time())
	if not db.settings.announce then
		queue = {}
	elseif #queue > 0 and not chatLocked() and yes(IsInGuild, false) then
		for _, item in ipairs(queue) do
			send(item.text)
		end
		queue = {}
	end
	db.announceQueue = queue
end

local function announce(db, text)
	local queue = liveQueue(db, time())
	queue[#queue + 1] = { text = text, at = time() }
	while #queue > QUEUE_MAX do
		table.remove(queue, 1)
	end
	db.announceQueue = queue
	Capture.flushAnnouncements(db)
end

local function milestones(db, dex)
	local settings = db.settings
	for _, m in ipairs(ns.Milestones.check(dex, time())) do
		Capture.protect(errorHandler(), function()
			local label = ns.Milestones.label(m)
			ns.Print("Milestone earned: " .. label)
			if m.announce and settings.announce then
				announce(db, "SoulDex: " .. label .. "!")
			end
		end)
	end
end

local function catchSound()
	return SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST or FALLBACK_SOUND
end

local LEVEL_UP_SOUND = 888

-- The sound for a claim: the level-up fanfare for a new rank, a heavier chime for a boss
-- (first claim or not: 25 points or more from a creature), else the usual one.
function Capture.soundFor(result, rank)
	if rank then
		return SOUNDKIT and SOUNDKIT.LEVEL_UP or LEVEL_UP_SOUND
	end
	if result.kind ~= "player" and (result.points or 0) >= ns.Points.BOSS then
		return SOUNDKIT and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or catchSound()
	end
	return catchSound()
end

-- The game reads a sound from disk the first time it plays, which stalls that frame: the
-- first catch of a session lagged. At login (behind the loading screen) the catch sound
-- is started and stopped at once, so it is already loaded by the first catch. Skipped
-- when the sound is off, or when the client can't stop it (it would be heard).
function Capture.preloadSound(db)
	if not db.settings.sound or type(StopSound) ~= "function" then
		return
	end
	local willPlay, handle = call(PlaySound, catchSound())
	if readable(willPlay) and willPlay and plainNumber(handle) then
		call(StopSound, handle)
	end
end

-- Gets ready what a switched-on setting needs at the next catch: the popup frame for
-- "popup", the loaded sound for "sound". Run for both when the world first loads, and
-- for one when it is ticked in the options, so the first catch after either doesn't lag.
function Capture.prepareFor(db, key)
	if key == "popup" and db.settings.popup and ns.Toast then
		ns.Toast.prepare()
	elseif key == "sound" then
		Capture.preloadSound(db)
	end
end

-- The rank this catch earned (ns.Ranks.gained), or nil: only a catch that scored can.
local function rankGained(dex, result)
	if not ns.Ranks or type(result.points) ~= "number" or result.points <= 0 then
		return nil
	end
	local score = dex:score()
	return ns.Ranks.gained(score - result.points, score)
end

-- A chat line for every rank-up; guild chat from Ranks.ANNOUNCE_FROM on (when switched on).
local function rankUp(db, rank)
	local place = " (rank " .. rank.index .. " of " .. rank.count .. ")."
	ns.Print("Rank up: you are now |cff9dff3a" .. rank.name .. "|r" .. place)
	if db.settings.announce and rank.index >= ns.Ranks.ANNOUNCE_FROM then
		announce(db, "SoulDex: reached the rank of " .. rank.name .. "!")
	end
end

local function popup(db, result, entry, rank)
	local settings = db.settings
	if settings.popup and ns.Toast then
		ns.Toast.show(result, entry.info, entry.ctx, entry.color)
		if rank then
			ns.Toast.showRank(rank)
		end
	end
	if settings.sound then
		pcall(PlaySound, Capture.soundFor(result, rank))
	end
end

-- Each step is protected: nothing here can skip the catch hooks.
local function afterCatch(db, dex, result, entry)
	local ok, rank = pcall(rankGained, dex, result)
	if not ok then
		rank = nil
	end
	if result.isNew or result.stars then
		-- A frame later, so the popup and its sound don't land on the bag scan's frame.
		C_Timer.After(0, function()
			Capture.protect(errorHandler(), popup, db, result, entry, rank)
		end)
	end
	if rank then
		Capture.protect(errorHandler(), rankUp, db, rank)
	end
	if db.settings.chatter and ns.Flavour.chatter and result.kind ~= "unknown" then
		Capture.protect(errorHandler(), function()
			local line = ns.Flavour.chatter(entry.info.name, result.count, result.points)
			if line then
				ns.Print(line)
			end
		end)
	end
	if result.stars then
		Capture.protect(errorHandler(), function()
			local stars = result.stars .. (result.stars == 1 and " star" or " stars")
			ns.Print("Mastery: " .. entry.info.name .. " reached |cff9dff3a" .. stars .. "|r (+" .. result.points .. " pts).")
		end)
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
	return soul, { result = result, entry = { info = info, ctx = ctx, kind = kind, color = soul.color } }
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
	"MAIL_SHOW",
	"MAIL_CLOSED",
	"TRADE_SHOW",
	"TRADE_CLOSED",
	"MERCHANT_SHOW",
	"MERCHANT_CLOSED",
}
-- Chat lockdown ending; newer clients only (see Capture.flushAnnouncements).
local OPTIONAL_EVENTS = {
	"ADDON_RESTRICTION_STATE_CHANGED",
	"ENCOUNTER_END",
}

-- Windows a shard can arrive from without a kill (bank, mail, trade, vendor buyback):
-- open event -> its close event.
local SHARD_SOURCES = {
	BANKFRAME_OPENED = "BANKFRAME_CLOSED",
	MAIL_SHOW = "MAIL_CLOSED",
	TRADE_SHOW = "TRADE_CLOSED",
	MERCHANT_SHOW = "MERCHANT_CLOSED",
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
	local sourcesOpen = {} -- open SHARD_SOURCES windows, by open event
	local sent -- { castGUID, kind, info, targetName, targetHidden, time } from the last UNIT_SPELLCAST_SENT
	local lastUnreadable = 0 -- unreadable shard slots in the previous scan
	local names = {
		drainsoul = C_Spell and str(call(C_Spell.GetSpellName, DRAIN_SOUL_ID)),
		shadowburn = C_Spell and str(call(C_Spell.GetSpellName, SHADOWBURN_ID)),
	}
	local function nameOf(id)
		return C_Spell and str(call(C_Spell.GetSpellName, id))
	end

	local function sourceOpen()
		return next(sourcesOpen) ~= nil
	end

	local function scanBags()
		local firstScan = not scanned
		scanned = true
		local now = time()
		local present, unreadable = Capture.shardGuids()
		-- A shard slot we couldn't read now (or last scan) may hold an old shard that turns
		-- readable later: no shard is named until two scans in a row read every slot.
		local quiet = firstScan or sourceOpen() or cursorBusy() or unreadable > 0 or lastUnreadable > 0
		lastUnreadable = unreadable
		local map, gained, quietNew = ns.Shards.update(db.shardSouls, present, quiet, now, firstScan)
		db.shardSouls = map
		-- A new shard we won't name may be the kill's own: the capture is spent on it, so it
		-- can't name a later shard (a trade, a mail) instead. Two new shards at once can't
		-- be told apart: neither is named.
		if quietNew > 0 or #gained > 1 then
			window:take(GetTime())
		end
		local done = {}
		for _, guid in ipairs(gained) do
			local soul, after
			local capture = #gained == 1 and window:take(GetTime())
			if capture then
				local ok, s, a = pcall(Capture.record, dex, capture)
				if ok then
					soul, after = s, a
				else
					pcall(errorHandler(), s)
				end
			end
			-- Saved shard by shard, so an error later can't lose this one.
			map = ns.Shards.assign(map, guid, soul or false, now)
			db.shardSouls = map
			if after then
				done[#done + 1] = after
			end
		end
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
		Capture.protect(errorHandler(), Capture.prepareFor, db, "popup")
		Capture.protect(errorHandler(), Capture.prepareFor, db, "sound")
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
			if sent.targetHidden then
				return { unknown = true } -- a secret SENT name can't vouch for the target
			end
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
				targetName = readable(targetName) and str(targetName) or nil,
				targetHidden = not readable(targetName),
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

	local function flushAnnouncements()
		Capture.protect(errorHandler(), Capture.flushAnnouncements, db)
	end

	handlers.PLAYER_ENTERING_WORLD = function()
		onEnterWorld()
		flushAnnouncements()
	end
	handlers.BAG_UPDATE_DELAYED = queueScan
	handlers.PLAYER_REGEN_ENABLED = function()
		queueScan()
		flushAnnouncements()
	end
	-- Optional: an older client without these just waits for combat to end or a reload.
	handlers.ADDON_RESTRICTION_STATE_CHANGED = flushAnnouncements
	handlers.ENCOUNTER_END = flushAnnouncements
	for openEvent, closeEvent in pairs(SHARD_SOURCES) do
		handlers[openEvent] = function()
			sourcesOpen[openEvent] = true
		end
		handlers[closeEvent] = function()
			sourcesOpen[openEvent] = nil
			queueScan()
		end
	end

	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		local fn = handlers[event]
		if fn then
			Capture.protect(errorHandler(), fn, ...)
		end
	end)
	local failed = Capture.register(frame, EVENTS, UNIT_EVENTS)
	Capture.register(frame, OPTIONAL_EVENTS, {}) -- refusals here are not worth a warning
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
