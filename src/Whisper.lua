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
		and not name:find("[:|%c]")
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
	if validName(rest) then
		return token, rest
	end
	return token, nil
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

-- Whether to hold the ask for later (the experimental "boss names after the fight"):
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
