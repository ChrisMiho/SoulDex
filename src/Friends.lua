-- The friends store and leaderboard (pure; no WoW API). The store maps a
-- normalised name to { summary, seen, added }.
local _, ns = ...

local Friends = {}
ns.Friends = Friends

local ONLINE_WINDOW = 600

-- string.lower/upper only handle ASCII in Lua 5.1, so the Latin-1 Supplement
-- letters (UTF-8 "\195" + \128-\158 capitals, \160-\190 lowercase; \151 and \183
-- are the multiplication and division signs) are mapped by hand.
local function lowerCase(s)
	s = s:lower()
	return (s:gsub("\195([\128-\158])", function(b)
		if b == "\151" then
			return nil
		end
		return "\195" .. string.char(b:byte() + 32)
	end))
end

local function upperFirst(s)
	local lead, second = s:byte(1, 2)
	if lead == 195 and second and second >= 160 and second <= 190 and second ~= 183 then
		return "\195" .. string.char(second - 32) .. s:sub(3)
	end
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- The one spelling a name is stored and compared by: realm dropped, each word's
-- first letter capitalised, the rest lower case (so "ëlric" and "Ëlric" are the
-- same, and WoW: Forever's two-part names stay "Forgot Shards").
function Friends.normalise(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("%-.*$", "")
	if name == "" then
		return nil
	end
	return (lowerCase(name):gsub("[^ ]+", upperFirst))
end

-- WoW: Forever splits a character's name in two: UnitName returns "Forgot", "Shards"
-- for "Forgot Shards" (the second value is not a realm there). Joins them back.
function Friends.fullName(name, second)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	if type(second) == "string" and second ~= "" then
		return name .. " " .. second
	end
	return name
end

-- Brings a saved store up to the current spelling rule: keys that normalise
-- differently are merged into their normalised key (newest seen/summary wins, added
-- if either was), and the local player's own entry is dropped.
function Friends.tidy(store, me)
	local myKey = Friends.normalise(me)
	local oldKeys = {}
	for key in pairs(store) do
		if Friends.normalise(key) ~= key then
			oldKeys[#oldKeys + 1] = key
		end
	end
	for _, key in ipairs(oldKeys) do
		local old, newKey = store[key], Friends.normalise(key)
		store[key] = nil
		if newKey then
			local cur = store[newKey]
			if not cur then
				store[newKey] = old
			else
				cur.added = cur.added or old.added
				if (old.seen or 0) > (cur.seen or 0) then
					cur.seen, cur.summary = old.seen, old.summary or cur.summary
				end
			end
		end
	end
	if myKey then
		store[myKey] = nil
	end
	return store
end

local function isSeen(entry, now)
	return entry.seen ~= nil and now - entry.seen <= ONLINE_WINDOW
end

function Friends.add(store, name)
	name = Friends.normalise(name)
	if not name then
		return nil
	end
	store[name] = store[name] or {}
	store[name].added = true
	return name
end

-- Deletes a person, except an added one who is online right now: they are only
-- un-added, and stay listed like any guild or group member.
function Friends.remove(store, name, now)
	name = Friends.normalise(name)
	local entry = name and store[name]
	if not entry then
		return
	end
	if entry.added and isSeen(entry, now) then
		entry.added = false
	else
		store[name] = nil
	end
end

-- Deletes everyone not added whose name isn't in keep (a set of store keys). Returns
-- how many were deleted.
function Friends.purge(store, keep)
	local gone = {}
	for name, entry in pairs(store) do
		if not entry.added and not keep[name] then
			gone[#gone + 1] = name
		end
	end
	for _, name in ipairs(gone) do
		store[name] = nil
	end
	return #gone
end

-- Someone outside the store is only kept when found in your group or guild.
function Friends.merge(store, sender, summary, now, inGroupOrGuild)
	local name = Friends.normalise(sender)
	if not name then
		return nil
	end
	local entry = store[name]
	if not entry then
		if not inGroupOrGuild then
			return nil
		end
		entry = { added = false }
		store[name] = entry
	end
	entry.summary = summary
	entry.seen = now
	return entry
end

-- The numbers other players see for a dex.
function Friends.summaryOf(dex)
	return {
		score = dex:score(),
		mobs = dex:uniqueMobs(),
		players = dex:uniquePlayers(),
		raids = dex:raidsCompleted(),
	}
end

-- Your own leaderboard entry: { name, summary }. name is already a store key.
function Friends.me(dex, name)
	return { name = name, summary = Friends.summaryOf(dex) }
end

local function row(name, summary, extra)
	summary = summary or {}
	local r = {
		name = name,
		score = summary.score or 0,
		mobs = summary.mobs or 0,
		players = summary.players or 0,
		raids = summary.raids or 0,
	}
	for k, v in pairs(extra) do
		r[k] = v
	end
	return r
end

function Friends.leaderboard(store, me, now)
	local rows = {}
	local myName = Friends.normalise(me.name) or me.name or "?" -- "?" while the name is unreadable
	rows[1] = row(myName, me.summary, { online = true, isMe = true, added = false })
	for name, entry in pairs(store) do
		if name ~= myName then
			rows[#rows + 1] = row(name, entry.summary, {
				online = isSeen(entry, now),
				isMe = false,
				added = entry.added == true,
				heard = entry.summary ~= nil,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.name < b.name
	end)
	return rows
end
