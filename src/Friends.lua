-- The friends store and leaderboard (pure; no WoW API). The store maps a
-- normalised name to { summary, seen, added }.
local _, ns = ...

local Friends = {}
ns.Friends = Friends

local ONLINE_WINDOW = 600

function Friends.normalise(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("%-.*$", "")
	if name == "" then
		return nil
	end
	return name:sub(1, 1):upper() .. name:sub(2):lower()
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
