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

-- The one spelling a name is stored and compared by: realm dropped, first
-- letter capitalised, the rest lower case (so "ëlric" and "Ëlric" are the same).
function Friends.normalise(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("%-.*$", "")
	if name == "" then
		return nil
	end
	return upperFirst(lowerCase(name))
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

-- Deletes an added person who is not currently seen; otherwise just un-adds.
function Friends.remove(store, name, now)
	name = Friends.normalise(name)
	local entry = name and store[name]
	if not entry then
		return
	end
	if entry.added and not isSeen(entry, now) then
		store[name] = nil
	else
		entry.added = false
	end
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
	local myName = Friends.normalise(me.name) or me.name
	rows[1] = row(myName, me.summary, { online = true, isMe = true, added = false })
	for name, entry in pairs(store) do
		if name ~= myName then
			rows[#rows + 1] = row(name, entry.summary, {
				online = isSeen(entry, now),
				isMe = false,
				added = entry.added == true,
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
