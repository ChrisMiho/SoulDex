local _, ns = ...

-- Pure module: the capture window. A Drain Soul channel (or a Shadowburn cast) opens
-- a capture holding the target's details, read while it was alive; a new Soul Shard
-- that appears while a capture is live belongs to that target. No WoW API; time is
-- passed in as `now` (seconds).
--
-- A capture: { kind = "drainsoul"|"shadowburn", info = <target info>, castGUID,
--              started, expires, used }
-- info is the target's details, or { unknown = true, isPlayer = bool|nil } when the
-- name was hidden. info.guid (the target's GUID, when readable) tells targets apart.

local Catch = {}
ns.Catch = Catch

Catch.STOP_GRACE = 3 -- seconds a shard may lag behind the end of the channel
Catch.MAX_LIFE = 20 -- a channel lasts at most 15 s; no capture outlives this
Catch.SHADOWBURN = 5 -- seconds Shadowburn's target has to die

local Window = {}
Window.__index = Window

function Catch.new()
	return setmetatable({ captures = {} }, Window)
end

local function live(c, now)
	return now <= c.expires and now <= c.started + Catch.MAX_LIFE
end

local function prune(self, now)
	local kept = {}
	for _, c in ipairs(self.captures) do
		if live(c, now) then
			kept[#kept + 1] = c
		end
	end
	self.captures = kept
end

local function capAt(c, t)
	if t < c.expires then
		c.expires = t
	end
end

local function sameTarget(a, b)
	return a.guid ~= nil and a.guid == b.guid
end

-- kind: "drainsoul" or "shadowburn"; info: the target (see above); castGUID may be nil.
function Window:startCapture(kind, info, castGUID, now)
	prune(self, now)
	local kept = {}
	for _, c in ipairs(self.captures) do
		if not sameTarget(c.info, info) then
			-- Only one channel runs at a time: an older one whose stop we missed ends now.
			capAt(c, now + Catch.STOP_GRACE)
			kept[#kept + 1] = c
		end
	end
	local expires = now + Catch.MAX_LIFE
	if kind == "shadowburn" then
		expires = now + Catch.SHADOWBURN + Catch.STOP_GRACE
	end
	kept[#kept + 1] = { kind = kind, info = info, castGUID = castGUID, started = now, expires = expires }
	self.captures = kept
end

-- The Drain Soul channel ended (target died, or the cast was broken). A nil castGUID on
-- either side matches.
function Window:channelStopped(castGUID, now)
	for _, c in ipairs(self.captures) do
		if c.kind == "drainsoul" and (castGUID == nil or c.castGUID == nil or c.castGUID == castGUID) then
			capAt(c, now + Catch.STOP_GRACE)
		end
	end
end

-- A spell event whose unit or spell could not be read. A channel start we can't read may
-- be a new Drain Soul on an unknown target: drop everything. Anything else: end soon.
function Window:restricted(isChannelStart, now)
	if isChannelStart then
		self.captures = {}
		return
	end
	for _, c in ipairs(self.captures) do
		capAt(c, now + Catch.STOP_GRACE)
	end
end

-- The one live, unused capture, or nil. Two live unused captures on different targets
-- are ambiguous, so neither is returned (never a wrong name).
function Window:current(now)
	prune(self, now)
	local found
	for _, c in ipairs(self.captures) do
		if not c.used then
			if found then
				return nil
			end
			found = c
		end
	end
	return found
end

-- Like current, but hands the capture out once: one channel kills one target.
function Window:take(now)
	local c = self:current(now)
	if c then
		c.used = true
	end
	return c
end
