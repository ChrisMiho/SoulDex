local _, ns = ...

-- Pure module: the self-whisper that names a soul when the client hides the target's
-- name. The addon whispers the player "SDX1:<token>:%t"; the client expands %t to the
-- target's name, and the whisper that comes back carries it. No WoW API.

local Whisper = {}
ns.Whisper = Whisper

Whisper.MARKER = "SDX1"
Whisper.TIMEOUT = 60 -- seconds of unrestricted time to wait for the reply
Whisper.CEILING = 600 -- seconds after sending, whatever the state
Whisper.MAX_NAME = 64

local PREFIX = Whisper.MARKER .. ":"

-- The text to whisper; the client replaces %t with the target's name.
function Whisper.message(token)
	return PREFIX .. token .. ":%t"
end

function Whisper.isMarker(text)
	return type(text) == "string" and text:sub(1, #PREFIX) == PREFIX
end

local function validName(name)
	return name ~= ""
		and #name <= Whisper.MAX_NAME
		and name ~= "%t"
		and not name:find("[:|%c{}]")
end

-- A marked target comes back with its raid marker as text: "{rt8}Mana Phantom", or a
-- word such as "{skull}" on some clients. No creature name has braces, so every {...}
-- goes, with the spaces around the name.
function Whisper.stripMarkers(name)
	return (name:gsub("{[^{}]*}", ""):match("^%s*(.-)%s*$"))
end

-- Returns token, name. token is set for any well-formed "SDX1:<token>:<rest>"; name is
-- set only when <rest> looks like a real name (not empty, not the unexpanded "%t").
function Whisper.parse(text)
	if not Whisper.isMarker(text) then
		return nil, nil
	end
	local token, rest = text:match("^" .. PREFIX .. "([^:]+):(.*)$")
	if not token then
		return nil, nil
	end
	rest = Whisper.stripMarkers(rest)
	if validName(rest) then
		return token, rest
	end
	return token, nil
end

-- Folds a mob entry saved under a marked name into the one under the clean name.
local function mergeMob(into, from)
	for _, field in ipairs({ "classification", "creatureType", "family" }) do
		if into[field] == nil then
			into[field] = from[field]
		end
	end
	local function lower(a, b)
		return (a and b) and math.min(a, b) or a or b
	end
	local function higher(a, b)
		return (a and b) and math.max(a, b) or a or b
	end
	into.points = higher(into.points, from.points)
	into.first, into.last = lower(into.first, from.first), higher(into.last, from.last)
	into.minLevel, into.maxLevel = lower(into.minLevel, from.minLevel), higher(into.maxLevel, from.maxLevel)
	if from.bonus then
		into.bonus = (into.bonus or 0) + from.bonus
	end
	if type(into.places) ~= "table" then
		into.places = {}
	end
	for zone, p in pairs(type(from.places) == "table" and from.places or {}) do
		local q = into.places[zone]
		if type(q) ~= "table" or type(p) ~= "table" then
			into.places[zone] = q or p
		else
			q.count = (q.count or 0) + (p.count or 0)
			q.first, q.last = lower(q.first, p.first), higher(q.last, p.last)
		end
	end
end

-- Names saved before markers were stripped (1.5.1 and earlier): the dex's mobs and raid
-- entries and the souls on shards. A mob that is also under its clean name is merged
-- into it. A name that would be empty is left as it is. Returns how many were repaired.
function Whisper.repairNames(db)
	local fixed = 0
	local function clean(name)
		if type(name) == "string" and name:find("{", 1, true) then
			local stripped = Whisper.stripMarkers(name)
			if stripped ~= name and validName(stripped) then
				return stripped
			end
		end
	end
	if type(db.mobs) == "table" then
		local renames = {}
		for key, entry in pairs(db.mobs) do
			local name = type(entry) == "table" and clean(key)
			if name then
				renames[key] = name
			end
		end
		for key, name in pairs(renames) do
			local entry = db.mobs[key]
			db.mobs[key] = nil
			entry.name = name
			if type(db.mobs[name]) == "table" then
				mergeMob(db.mobs[name], entry)
			else
				db.mobs[name] = entry
			end
			fixed = fixed + 1
		end
	end
	if type(db.raids) == "table" then
		for _, entry in pairs(db.raids) do
			local name = type(entry) == "table" and clean(entry.name)
			if name then
				entry.name = name
				fixed = fixed + 1
			end
		end
	end
	if type(db.shardSouls) == "table" then
		for _, entry in pairs(db.shardSouls) do
			local soul = type(entry) == "table" and entry.soul
			local name = type(soul) == "table" and clean(soul.name)
			if name then
				soul.name = name
				fixed = fixed + 1
			end
		end
	end
	return fixed
end

-- Whether to send the whisper now. Every field must be exactly as listed; nil (could
-- not be read) means no.
function Whisper.shouldAsk(s)
	return s.nameHidden == true
		and s.hasTarget == true
		and s.mouseoverOther == false
		and s.focusOther == false
		and s.chatLocked == false
		and s.afk == false
		and s.dnd == false
end

-- Whether to hold the ask for later ("boss names after the fight"):
-- everything is right for asking except that chat is locked, as it is for the whole of
-- a boss encounter. The whisper then waits for the lock to lift (lateStep).
function Whisper.shouldDefer(s)
	return s.nameHidden == true
		and s.hasTarget == true
		and s.mouseoverOther == false
		and s.focusOther == false
		and s.chatLocked == true
		and s.afk ~= true -- AFK and DND can't be read during an encounter: checked at the send
		and s.dnd ~= true
end

-- What to do now with an ask that was held: "send", "wait" or "fail". heldEpoch and
-- epochNow are the caller's target-change counts when the ask was held and now: %t names
-- the target at the send, so after any target change the name can no longer be asked
-- for. s: the same reads as shouldAsk (mouseover and focus mattered at the cast only).
function Whisper.lateStep(heldEpoch, epochNow, s)
	if heldEpoch == nil or heldEpoch ~= epochNow or s.hasTarget ~= true then
		return "fail"
	end
	if s.chatLocked ~= false or s.afk ~= false or s.dnd ~= false then
		return "wait"
	end
	return "send"
end

-- Pending whispers. The clock only runs while the client lets the reply through (out of
-- combat, chat not locked): the caller passes restricted = true otherwise. Whatever the
-- state, an entry is dropped CEILING seconds after it was sent.
local Queue = {}
Queue.__index = Queue

function Whisper.newQueue()
	return setmetatable({ entries = {}, n = 0 }, Queue)
end

-- Stores pend (the caller's capture state) and gives it pend.token: hex of the send time
-- (ms, low 20 bits, fixed width) then the counter, so a reply to a whisper from before a
-- /reload (the counter restarts, the clock doesn't) can't match. Never contains ":".
function Queue:add(pend, now)
	self.n = self.n + 1
	local token = string.format("%05x%x", math.floor((now or 0) * 1000) % 0x100000, self.n)
	pend.token = token
	self.entries[token] = { pend = pend, sentAt = now, waited = 0, last = now, seq = self.n }
	return token
end

function Queue:get(token)
	local e = self.entries[token]
	return e and e.pend or nil
end

function Queue:remove(token)
	local e = self.entries[token]
	if not e then
		return nil
	end
	self.entries[token] = nil
	return e.pend
end

function Queue:count()
	local n = 0
	for _ in pairs(self.entries) do
		n = n + 1
	end
	return n
end

-- Returns the pends that gave up, oldest first, and removes them.
function Queue:tick(now, restricted)
	local gone = {}
	for token, e in pairs(self.entries) do
		if not restricted then
			e.waited = e.waited + (now - e.last)
		end
		e.last = now
		if e.waited >= Whisper.TIMEOUT or now - e.sentAt >= Whisper.CEILING then
			gone[#gone + 1] = e
			self.entries[token] = nil
		end
	end
	table.sort(gone, function(a, b)
		return a.seq < b.seq
	end)
	local expired = {}
	for i, e in ipairs(gone) do
		expired[i] = e.pend
	end
	return expired
end
