local _, ns = ...

-- Pure module: matches a newly appeared Soul Shard to the death it came from.
-- No WoW API; time is passed in as `now` (seconds).

local Catch = {}
ns.Catch = Catch

Catch.WINDOW = 3 -- seconds from death to shard
Catch.GRACE = 1 -- aura removed this long before the death still counts
Catch.SHADOWBURN = 5 -- seconds Shadowburn can precede the death
Catch.DRAIN_SOUL = 15 -- seconds a Drain Soul channel can last
Catch.CACHE_TTL = 600 -- drop cached details older than this

local Matcher = {}
Matcher.__index = Matcher

function Catch.new()
	return setmetatable({ cache = {}, auras = {}, queue = {}, clock = 0 }, Matcher)
end

local function tick(self, now)
	if now and now > self.clock then
		self.clock = now
	end
end

function Matcher:noteUnit(guid, info, now)
	tick(self, now)
	local entry = self.cache[guid]
	if not entry then
		entry = { info = {} }
		self.cache[guid] = entry
	end
	for k, v in pairs(info) do
		if v ~= nil then
			entry.info[k] = v
		end
	end
	entry.seen = now or self.clock
end

function Matcher:noteAura(guid, kind, now)
	tick(self, now)
	local byKind = self.auras[guid]
	if not byKind then
		byKind = {}
		self.auras[guid] = byKind
	end
	byKind[kind] = { applied = now }
end

function Matcher:noteAuraGone(guid, kind, now)
	tick(self, now)
	local a = self.auras[guid] and self.auras[guid][kind]
	if a then
		a.gone = now
	end
end

local function qualifies(self, guid, now)
	local byKind = self.auras[guid]
	if not byKind then
		return false
	end
	for kind, a in pairs(byKind) do
		local live = a.gone == nil or now - a.gone <= Catch.GRACE
		-- A missed removal event must not keep an aura live: cap it at its longest duration.
			local cap = kind == "shadowburn" and Catch.SHADOWBURN or Catch.DRAIN_SOUL + Catch.GRACE
			if live and now - a.applied <= cap then
			return true
		end
	end
	return false
end

local function prune(self, now)
	for guid, entry in pairs(self.cache) do
		if now - entry.seen > Catch.CACHE_TTL then
			self.cache[guid] = nil
		end
	end
	for guid, byKind in pairs(self.auras) do
		local newest = 0
		for _, a in pairs(byKind) do
			newest = math.max(newest, a.gone or a.applied or 0)
		end
		if now - newest > Catch.CACHE_TTL then
			self.auras[guid] = nil
		end
	end
end

function Matcher:noteDeath(guid, name, now)
	tick(self, now)
	prune(self, now)
	for _, c in ipairs(self.queue) do
		if c.guid == guid and now - c.time <= Catch.WINDOW then
			return -- same death already queued
		end
	end
	if not qualifies(self, guid, now) then
		return
	end
	local info = {}
	local entry = self.cache[guid]
	if entry then
		for k, v in pairs(entry.info) do
			info[k] = v
		end
	end
	info.name = name
	self.queue[#self.queue + 1] = { guid = guid, info = info, time = now }
	self.auras[guid] = nil
end

local function expire(self, now)
	local live = {}
	for _, c in ipairs(self.queue) do
		if now - c.time <= Catch.WINDOW then
			live[#live + 1] = c
		end
	end
	self.queue = live
end

function Matcher:takeCandidate(now)
	expire(self, now)
	-- The most recent death wins; older ones stay queued until they expire.
	return table.remove(self.queue)
end

function Matcher:hasPending(now)
	expire(self, now)
	return #self.queue > 0
end
