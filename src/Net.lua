-- Friends glue: swaps summaries and dexes with other SoulDex users over AceComm-3.0,
-- draws the Friends tab (leaderboard, add/remove, the selected person's numbers) and
-- opens a friend's dex for browsing. The decision helpers are pure and tested; the
-- wiring below them is game code. Wall-clock time() for every saved `seen`, GetTime()
-- for throttles.
--
-- Messages (src/Comm.lua): "S" summary, "Q" ask for a summary, "R" ask for the dex,
-- "W" the dex is coming (with its size), "D" the dex, "V" the sender's SoulDex version.
-- Summaries and versions go to the guild and group; everything else is a whisper (a
-- version is also whispered once to whoever asks for a summary).
local _, ns = ...

local Net = {}
ns.Net = Net

local SUMMARY_GAP = 30 -- seconds between summary broadcasts
local HEARTBEAT = 300 -- re-broadcast while quiet, so you stay "online" (Friends: seen < 600 s ago)
local NEWCOMER_AFTER = HEARTBEAT + 60 -- not heard from this long: answer their summary with ours
local DEX_REPLY_GAP = 30 -- at most one "R" reply per sender
local DEX_ANY_GAP = 10 -- between dexes to different people (and only one is sent at a time)
local SUMMARY_REPLY_GAP = 10 -- at most one "Q" reply per sender
local POLL_EVERY = 60 -- ask added friends for a summary
local LOGIN_DELAY = 5
local ANSWER_WAIT = 60 -- no dex yet: say so in chat and ask once more
local REQUEST_TTL = 90 -- still nothing: "No answer from <name>." and a late "D" is ignored
local TRANSFER_RATE = 300 -- bytes a second an announced dex is assumed to arrive at (on the slow side)
local TRANSFER_MARGIN = 30 -- seconds added to that estimate
local TRANSFER_MAX = 600 -- never wait longer than this for an announced dex
local NOT_FOUND_WINDOW = 5 -- hide "No player named ..." this long after whispering them

local GROUP_CHANNELS = { GUILD = true, PARTY = true, RAID = true }

-- Pure helpers -----------------------------------------------------------------------

-- Channels a summary goes to.
function Net.channels(inGuild, inRaid, inGroup)
	local out = {}
	if inGuild then
		out[#out + 1] = "GUILD"
	end
	if inRaid then
		out[#out + 1] = "RAID"
	elseif inGroup then
		out[#out + 1] = "PARTY"
	end
	return out
end

-- Seconds until a throttled send may go (0 = now). last nil = never sent.
function Net.wait(last, now, gap)
	if last == nil then
		return 0
	end
	return math.max(0, last + gap - now)
end

function Net.allowed(last, now, gap)
	return Net.wait(last, now, gap) <= 0
end

-- Whether to act on a message. kind: first letter of the message; distribution: AceComm's.
-- added: the sender is on your friends list; requested: you asked them for their dex.
function Net.accepts(kind, distribution, added, requested)
	if kind == "S" then
		return GROUP_CHANNELS[distribution] == true or (distribution == "WHISPER" and added == true)
	elseif kind == "Q" or kind == "R" then
		return distribution == "WHISPER"
	elseif kind == "D" or kind == "W" then
		return distribution == "WHISPER" and requested == true
	elseif kind == "V" then
		return GROUP_CHANNELS[distribution] == true or (distribution == "WHISPER" and added == true)
	end
	return false
end

-- Whether sender (Ambiguate'd) is the local player.
-- myName, second are UnitName("player")'s two values (WoW: Forever splits names in two).
function Net.isMe(sender, myName, second)
	local a = ns.Friends.normalise(sender)
	if a == nil then
		return false
	end
	return a == ns.Friends.normalise(ns.Friends.fullName(myName, second))
end

-- Someone we haven't heard from lately (or ever): answer their summary with ours.
function Net.isNewcomer(entry, now)
	return not entry or not entry.seen or now - entry.seen > NEWCOMER_AFTER
end

-- Added friends to ask for a summary: not heard from in the last `gap` seconds. Sorted.
function Net.dueQueries(store, now, gap)
	local out = {}
	for name, entry in pairs(store) do
		if entry.added and (not entry.seen or now - entry.seen >= gap) then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

-- A typed name as a store key, or nil when it can't be a character name. WoW: Forever
-- names have two words ("Forgot Shards"), so one space between words is kept.
function Net.cleanName(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:match("^%s*(.-)%s*$"):gsub("%s+", " ")
	local _, spaces = text:gsub(" ", "")
	if spaces > 1 or text:find("%d") then
		return nil
	end
	return ns.Friends.normalise(text)
end

-- The name in a "No player named '%s' is currently playing." line, or nil. fmt is
-- the game's ERR_CHAT_PLAYER_NOT_FOUND_S.
function Net.notFoundName(msg, fmt)
	if type(msg) ~= "string" or type(fmt) ~= "string" then
		return nil
	end
	local pattern = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	pattern = pattern:gsub("%%%%s", "(.+)")
	return msg:match("^" .. pattern .. "$")
end

-- Where a browse request stands: "asking" until ANSWER_WAIT, "retrying" (asked a second
-- time) until the deadline, then "expired" (a late "D" is ignored). Once the dex is
-- announced ("W") it is "receiving" until the deadline. deadline nil: asked + REQUEST_TTL.
function Net.browseStage(asked, now, deadline, receiving)
	if not asked or now > (deadline or asked + REQUEST_TTL) then
		return "expired"
	elseif receiving then
		return "receiving"
	elseif now - asked > ANSWER_WAIT then
		return "retrying"
	end
	return "asking"
end

-- Seconds to allow for a dex of this many bytes to arrive.
function Net.transferTime(bytes)
	if type(bytes) ~= "number" or bytes < 0 then
		bytes = 0
	end
	return math.min(TRANSFER_MAX, math.ceil(bytes / TRANSFER_RATE) + TRANSFER_MARGIN)
end

-- A request's deadline once its dex is announced at `now`: later, never sooner.
function Net.extendDeadline(deadline, now, bytes)
	return math.max(deadline or 0, now + Net.transferTime(bytes))
end

-- Seconds an announced dex is still expected to take (the estimate without its margin).
function Net.receiveLeft(comingAt, bytes, now)
	return math.max(0, comingAt + Net.transferTime(bytes) - TRANSFER_MARGIN - now)
end

-- The Friends tab's status line for the person being asked. left: Net.receiveLeft.
function Net.browseStatus(name, stage, left)
	if stage == "receiving" then
		local text = "Receiving " .. name .. "'s dex..."
		if type(left) ~= "number" then
			return text
		elseif left <= 60 then
			return text .. " <1 min"
		end
		return text .. " ~" .. math.ceil(left / 60) .. " min"
	elseif stage == "asking" then
		return "Asking " .. name .. "..."
	end
	return "Asking " .. name .. " again..."
end

-- How long a dex send may stay "in flight" when its finished-callback never comes.
function Net.sendCeiling(bytes)
	return 2 * Net.transferTime(bytes)
end

-- Whether to answer an "R" now. lastToThem / lastToAnyone: GetTime() of the last dex
-- sent to this person / to anyone. flight: the dex being sent right now, if any
-- ({ started, ceiling }): while it is going out nobody gets another one.
function Net.maySendDex(now, lastToThem, lastToAnyone, flight)
	if flight and now - flight.started < flight.ceiling then
		return false
	end
	return Net.allowed(lastToThem, now, DEX_REPLY_GAP) and Net.allowed(lastToAnyone, now, DEX_ANY_GAP)
end

-- Whether Clean up can tell who is absent. inGuild: IsInGuild() (nil when unreadable);
-- guildSize: GetNumGuildMembers() (nil when unreadable); namesOk: every group and guild
-- name could be read. In a guild whose roster isn't loaded, nobody is provably absent.
function Net.cleanUpSafe(inGuild, guildSize, namesOk)
	if not namesOk then
		return false
	elseif inGuild == false then
		return true
	elseif inGuild ~= true then
		return false
	end
	return type(guildSize) == "number" and guildSize > 0
end

-- The chat line for someone else's version, or nil when there is nothing to say: it is
-- not newer than yours (Version.isNewer), or the player was already told this session.
function Net.versionNotice(theirs, mine, told)
	local Version = ns.Version
	if told or not Version or not Version.isNewer(theirs, mine) then
		return nil
	end
	return "A newer SoulDex is out: " .. Version.display(theirs) .. ". You have " .. Version.display(mine) .. "."
end

-- Drops entries of t (key -> GetTime()) older than age seconds.
function Net.forgetOlder(t, now, age)
	for key, at in pairs(t) do
		if now - at > age then
			t[key] = nil
		end
	end
end

-- Whether your own row is listed: only once someone else with a summary is on the board
-- (an added person we haven't heard from yet doesn't count).
function Net.showSelf(rows)
	for _, r in ipairs(rows) do
		if not r.isMe and r.heard then
			return true
		end
	end
	return false
end

-- Leaderboard rows (Friends.leaderboard) as UIFormat line descriptors. Your own row keeps
-- its ranked place (highlighted, not selectable) when Net.showSelf, otherwise it is left
-- out: people you added but haven't heard from stay listed (so they can be selected and
-- removed), and the help text shows only when nobody is left.
function Net.leaderRows(rows, selected)
	local C = ns.UIFormat.COLORS
	local out = {}
	if not Net.showSelf(rows) then
		local others = {}
		for _, r in ipairs(rows) do
			if not r.isMe then
				others[#others + 1] = r
			end
		end
		rows = others
	end
	for i, r in ipairs(rows) do
		local color = C.TEXT
		if r.isMe then
			color = C.TITLE
		elseif not r.online then
			color = C.DIM
		end
		out[#out + 1] = {
			text = i .. ". " .. r.name .. (r.isMe and " (you)" or ""),
			color = color,
			right = ns.View.thousands(r.score),
			rightColor = r.online and C.MUTED or C.DIM,
			value = (not r.isMe) and r.name or nil,
			selected = (not r.isMe) and r.name == selected,
		}
	end
	if #rows == 0 then
		out[#out + 1] = {
			text = "Guild and group members with SoulDex appear here.",
			color = C.MUTED,
			wrap = true,
		}
		out[#out + 1] = { text = "/souldex add <name>", color = C.MUTED }
	end
	return out
end

-- The right-hand lines for one leaderboard row. entry: its db.friends entry.
function Net.personLines(row, entry, fmt)
	local F = ns.UIFormat
	local C = F.COLORS
	local status, statusColor = "online", C.GOOD
	if not row.online then
		status, statusColor = "offline", C.DIM
	end
	local function kv(label, value)
		return { text = label, color = C.MUTED, right = value, rightColor = C.TEXT }
	end
	local lines = {
		{ text = row.name, color = C.WHITE, right = status, rightColor = statusColor, big = true },
		{ hr = true },
		{ text = "Rank", color = C.MUTED, right = ns.Ranks.of(row.score).name, rightColor = C.ACCENT },
		{ text = "Score", color = C.MUTED, right = ns.View.thousands(row.score) .. " pts", rightColor = C.GOOD },
		kv("Unique mobs", tostring(row.mobs)),
		kv("Players", tostring(row.players)),
		kv("Raids completed", tostring(row.raids)),
	}
	if entry and entry.summary then
		if not row.online then
			lines[#lines + 1] = kv("Last seen", F.dateText(entry.seen, fmt) or F.DASH)
		end
	else
		lines[#lines + 1] = { hr = true }
		lines[#lines + 1] = { text = "Not heard from yet.", color = C.MUTED }
	end
	if entry and type(entry.dex) == "string" then
		local saved = ns.Friends.dexCurrent(entry) and "up to date" or F.dateText(entry.dexAt, fmt) or F.DASH
		lines[#lines + 1] = kv("Dex saved", saved)
	end
	return lines
end

-- What Browse dex does. hasCopy: a saved copy of their dex; online: Friends.isOnline;
-- current: the copy is still their whole dex (Friends.dexCurrent). copy: open the
-- saved copy at once; ask: ask them for a fresh one; quiet: that ask prints nothing in
-- chat (the copy is already on screen).
function Net.browsePlan(hasCopy, online, current)
	if not hasCopy then
		return { copy = false, ask = true, quiet = false }
	end
	return { copy = true, ask = online == true and current ~= true, quiet = true }
end

-- Game wiring ---------------------------------------------------------------------------

local Friends, Comm, Capture = ns.Friends, ns.Comm, ns.Capture

local state = {
	enabled = false, -- AceComm found and registered
	lastBroadcast = nil, -- GetTime() of the last summary broadcast
	queued = false, -- a throttled broadcast is waiting
	summaryReplies = {}, -- name -> GetTime() of the last "Q" answer
	dexReplies = {}, -- name -> GetTime() of the last "R" answer
	lastDexSend = nil, -- GetTime() of the last "R" answer to anyone
	dexFlight = nil, -- the dex being sent right now: { name, started, ceiling }
	request = nil, -- the dex we asked for: { name, asked, deadline, comingAt, bytes } (GetTime())
	whispered = {}, -- name -> GetTime() we last whispered them
	asking = nil, -- name shown as "Asking <name>..." / "Receiving <name>'s dex..."
	noAnswer = nil, -- name whose request ran out
	noAnswerText = nil, -- the line shown for them
	versionDue = true, -- send "V" with the next summary broadcast (login, a newcomer)
	versionWhispered = {}, -- name -> true once "V" was whispered to them
	versionTold = false, -- the newer-version line was printed this session
	selected = nil, -- leaderboard selection
	classes = {}, -- store key -> class token, for guild and group members whose class could be read
}

-- True only for a readable true from fn() (IsInGuild, IsInRaid, IsInGroup).
local function yes(fn)
	local v = Capture.call(fn)
	return Capture.readable(v) and v == true
end

-- UnitName("player")'s two parts, each nil unless readable.
local function myParts()
	local first, second = Capture.call(UnitName, "player")
	return Capture.plainString(first) and first or nil, Capture.plainString(second) and second or nil
end

local function myName()
	return Friends.normalise(Friends.fullName(myParts()))
end

-- UnitClass's class token for unit (a unit id, or a group member's name), or nil.
local function classToken(unit)
	local _, token = Capture.call(UnitClass, unit)
	return Capture.plainString(token) and token or nil
end

-- SoulDex is for warlocks: anyone else running it sends nothing, so they never show up
-- on other people's Friends tab. An unreadable class counts as a warlock.
local function iAmWarlock()
	return not Friends.notWarlock(classToken("player"))
end

-- The class of everyone in your group and guild whose class can be read (store key ->
-- class token). GetGuildRosterInfo's 11th value is the class token.
local function rosterClasses()
	local plain, out = Capture.plainString, {}
	local members = Capture.call(GetNumGroupMembers)
	local prefix = yes(IsInRaid) and "raid" or "party"
	for i = 1, Capture.plainNumber(members) and members or 0 do
		local name, second = Capture.call(UnitName, prefix .. i)
		local key = plain(name) and Friends.normalise(Friends.fullName(name, plain(second) and second or nil))
		local class = classToken(prefix .. i)
		if key and class then
			out[key] = class
		end
	end
	local guildSize = Capture.call(GetNumGuildMembers)
	for i = 1, Capture.plainNumber(guildSize) and guildSize or 0 do
		local info = { Capture.call(GetGuildRosterInfo, i) }
		local key = plain(info[1]) and Friends.normalise(info[1])
		local class = plain(info[11]) and info[11] or nil
		if key and class then
			out[key] = class
		end
	end
	return out
end

-- A person's class token, or nil when it can't be told. target: their name as a unit
-- (UnitClass reads group members by name).
local function classOf(name, target)
	return state.classes[name] or classToken(target)
end

-- Your leaderboard entry (shared with the Me tab's rank).
function Net.me(dex)
	return Friends.me(dex, myName())
end

local function refreshFriends()
	local UI = ns.UI
	if UI and UI.currentTab() == "Friends" then
		UI.refresh()
	end
end

-- Our live request to name, or nil.
local function requestTo(name)
	local req = state.request
	return req and req.name == name and req or nil
end

-- callback(arg, bytesSent, bytesTotal): AceComm calls it as each piece goes out.
local function send(msg, distribution, target, prio, callback, arg)
	if state.enabled and msg and iAmWarlock() then
		Net:SendCommMessage(Comm.PREFIX, msg, distribution, target, prio, callback, arg)
	end
end

local function whisper(msg, target, prio, callback, arg)
	if not msg then
		return
	end
	local key = Friends.normalise(target)
	if key then
		state.whispered[key] = GetTime()
	end
	-- A long message (a dex) goes out in pieces over minutes. If the other player logs
	-- off meanwhile, every later piece earns a "No player named ..." line: the time is
	-- stamped again as each piece is sent, so the chat filter (start) hides them all.
	local function pieceSent(a, sent, total)
		if key then
			state.whispered[key] = GetTime()
		end
		if callback then
			callback(a, sent, total)
		end
	end
	send(msg, "WHISPER", target, prio, pieceSent, arg)
end

local function summaryMessage()
	return Comm.encodeSummary(Friends.summaryOf(ns.dex))
end

local function broadcastNow()
	state.lastBroadcast = GetTime()
	local msg = summaryMessage()
	local channels = Net.channels(yes(IsInGuild), yes(IsInRaid), yes(IsInGroup))
	for _, channel in ipairs(channels) do
		send(msg, channel)
	end
	-- The version rides along once per login and when a newcomer is heard, not every time.
	if state.versionDue and #channels > 0 then
		state.versionDue = false
		local version = Comm.encodeVersion(ns.version)
		for _, channel in ipairs(channels) do
			send(version, channel)
		end
	end
end

-- Sends a summary now, or once the 30 s throttle allows (never dropped, never doubled).
local function requestBroadcast()
	if not state.enabled or state.queued then
		return
	end
	local wait = Net.wait(state.lastBroadcast, GetTime(), SUMMARY_GAP)
	if wait <= 0 then
		broadcastNow()
	else
		state.queued = true
		C_Timer.After(wait, function()
			state.queued = false
			broadcastNow()
		end)
	end
end

local function askForSummaries()
	if not state.enabled then
		return
	end
	local request = Comm.encodeRequest("Q")
	for _, name in ipairs(Net.dueQueries(ns.db.friends, time(), POLL_EVERY)) do
		whisper(request, name)
	end
end

local function tick()
	local now = GetTime()
	Net.forgetOlder(state.summaryReplies, now, SUMMARY_REPLY_GAP)
	Net.forgetOlder(state.dexReplies, now, DEX_REPLY_GAP)
	Net.forgetOlder(state.whispered, now, NOT_FOUND_WINDOW)
	askForSummaries()
	if state.enabled and Net.allowed(state.lastBroadcast, GetTime(), HEARTBEAT) then
		requestBroadcast()
	end
	refreshFriends() -- online/offline changes with time
end

-- Incoming ------------------------------------------------------------------------------

local handlers = {}

-- Each handler gets (name, target, payload, distribution); payload is Comm.decode's.
function handlers.S(name, _, summary, distribution)
	local store, now = ns.db.friends, time()
	local newcomer = Net.isNewcomer(store[name], now)
	-- accepts() only lets through group/guild channels and added friends' whispers.
	if Friends.merge(store, name, summary, now, true) then
		if newcomer and GROUP_CHANNELS[distribution] then
			state.versionDue = true
			requestBroadcast() -- so they learn about you (and your version) too
		end
		refreshFriends()
	end
end

function handlers.Q(name, target)
	local now = GetTime()
	if Net.allowed(state.summaryReplies[name], now, SUMMARY_REPLY_GAP) then
		state.summaryReplies[name] = now
		whisper(summaryMessage(), target)
		if not state.versionWhispered[name] then
			state.versionWhispered[name] = true
			whisper(Comm.encodeVersion(ns.version), target)
		end
	end
end

-- AceComm's progress callback for a dex: the send is over once every byte went out.
local function dexSent(flight, sent, total)
	if state.dexFlight == flight and type(sent) == "number" and type(total) == "number" and sent >= total then
		state.dexFlight = nil
	end
end

-- One dex goes out at a time: while it does, further requests (the asker's own 60 s
-- retry, or anyone else's) are ignored and simply time out on their side.
function handlers.R(name, target)
	local now = GetTime()
	if not Net.maySendDex(now, state.dexReplies[name], state.lastDexSend, state.dexFlight) then
		return
	end
	local msg = Comm.encodeDex(ns.db)
	local flight = { name = name, started = now, ceiling = Net.sendCeiling(#msg) }
	state.dexReplies[name] = now
	state.lastDexSend = now
	state.dexFlight = flight -- before sending: the callback can fire inside SendCommMessage
	whisper(Comm.encodeComing(#msg), target) -- normal priority, so it lands ahead of the dex
	whisper(msg, target, "BULK", dexSent, flight)
end

-- The dex we asked for is on its way: wait for it as long as its size needs.
function handlers.W(name, _, bytes)
	local req = requestTo(name)
	if not req or req.comingAt then
		return
	end
	local now = GetTime()
	req.comingAt, req.bytes = now, bytes
	req.deadline = Net.extendDeadline(req.deadline, now, bytes)
	refreshFriends()
end

function handlers.V(_, _, version)
	local text = Net.versionNotice(version, ns.version, state.versionTold)
	if text then
		state.versionTold = true
		ns.Print(text)
	end
end

-- Opens a friend's dex in the window. savedAt: the time() a saved copy arrived (nil for
-- one that just came in).
local function openDex(db, name, savedAt)
	local UI = ns.UI
	if UI then
		UI.showDex(ns.Dex.new(db), name, savedAt)
		UI.setCompare(ns.dex)
		-- From the Friends tab it opens on their Me tab, the overview of that warlock.
		if UI.currentTab() == "Friends" then
			UI.selectTab("Me")
		end
	end
end

-- db is nil when the dex couldn't be read; message is the dex as it came over the wire.
function handlers.D(name, _, db, _, message)
	local req = requestTo(name)
	local quiet = req ~= nil and req.quiet
	if req then
		state.request = nil
	end
	if state.asking == name then
		state.asking = nil
	end
	if not db then
		if not quiet then
			ns.Print("Couldn't read " .. name .. "'s dex.")
		end
		refreshFriends()
		return
	end
	local entry = ns.db.friends[name]
	Friends.keepDex(ns.db.friends, name, message, time(), entry and entry.summary)
	refreshFriends()
	local UI = ns.UI
	if quiet then
		-- Their saved copy was opened at once: swap in the fresh one only while it is
		-- still on screen, never pulling the player away from where they went since.
		if UI and UI.isShown() and UI.owner() == name then
			openDex(db, name, nil)
		end
		return
	end
	if UI and not UI.isShown() then
		-- A dex can take minutes: don't reopen a window the player has closed since.
		ns.Print(name .. "'s dex arrived while SoulDex was closed. It's saved: press Browse dex to see it.")
		return
	end
	openDex(db, name, nil)
end

-- AceComm callback (RegisterComm's default method name, called as Net:OnCommReceived).
function Net.OnCommReceived(_, prefix, message, distribution, sender)
	if prefix ~= Comm.PREFIX or type(message) ~= "string" or type(sender) ~= "string" or not ns.db then
		return
	end
	local target = Capture.call(Ambiguate, sender, "none")
	if not Capture.plainString(target) or Net.isMe(target, myParts()) then
		return
	end
	local name = Friends.normalise(target)
	if not name then
		return
	end
	if Friends.notWarlock(classOf(name, target)) then
		if ns.db.friends[name] then
			ns.db.friends[name] = nil -- saved before SoulDex checked classes
			refreshFriends()
		end
		return
	end
	local kind = message:sub(1, 1)
	local entry = ns.db.friends[name]
	local req = requestTo(name)
	local requested = req ~= nil and GetTime() <= req.deadline
	if not handlers[kind] or not Net.accepts(kind, distribution, entry ~= nil and entry.added, requested) then
		return
	end
	local decoded, payload = Comm.decode(message)
	if decoded == kind then
		handlers[kind](name, target, payload, distribution, message)
	elseif kind == "D" then
		handlers.D(name, target, nil) -- asked for, but unreadable: say so
	end
end

-- Public API (the slash command and the Friends tab) -----------------------------------------

local function loaded()
	if ns.db and ns.db.friends then
		return true
	end
	ns.Print("SoulDex is still loading.")
	return false
end

function Net.addFriend(text)
	if not loaded() then
		return
	end
	local name = Net.cleanName(text)
	if not name then
		ns.Print("That isn't a character name.")
		return
	end
	if name == myName() then
		ns.Print("That's you.")
		return
	end
	if Friends.notWarlock(classOf(name, name)) then
		ns.Print(name .. " isn't a warlock.")
		return
	end
	Friends.add(ns.db.friends, name)
	state.selected = name
	if state.enabled then
		whisper(Comm.encodeRequest("Q"), name)
		ns.Print("Added " .. name .. ". Their score shows when they're online.")
	else
		ns.Print("Added " .. name .. ".")
	end
	refreshFriends()
end

-- Removes anyone on the Friends tab. Someone you didn't add comes back if they send
-- their score again from your guild or group.
function Net.removeFriend(text)
	if not loaded() then
		return
	end
	local name = Net.cleanName(text)
	local entry = name and ns.db.friends[name]
	if not entry then
		ns.Print((name or tostring(text)) .. " isn't on your friends list.")
		return
	end
	Friends.remove(ns.db.friends, name, time())
	ns.Print("Removed " .. name .. ".")
	refreshFriends()
end

-- Names of everyone in your group and guild right now (store keys), as a set. Also
-- returns whether every name could be read, and the guild roster's size (nil when unreadable).
local function presentNames()
	local plain = Capture.plainString
	local keep, namesOk = {}, true
	-- True when the name went into the set.
	local function note(name, second)
		if not Capture.readable(name) then
			namesOk = false
			return false
		end
		local key = plain(name) and Friends.normalise(Friends.fullName(name, plain(second) and second or nil))
		if key then
			keep[key] = true
		end
		return key ~= nil
	end
	local members = Capture.call(GetNumGroupMembers)
	local prefix = yes(IsInRaid) and "raid" or "party"
	for i = 1, Capture.plainNumber(members) and members or 0 do
		note(Capture.call(UnitName, prefix .. i)) -- a slot past the party's end has no name: fine
	end
	local guildSize = Capture.call(GetNumGuildMembers)
	guildSize = Capture.plainNumber(guildSize) and guildSize or nil
	for i = 1, guildSize or 0 do
		-- Only the first value: the next one is the member's guild rank, not a second name part.
		local name = Capture.call(GetGuildRosterInfo, i)
		if not note(name) then
			namesOk = false
		end
	end
	return keep, namesOk, guildSize
end

-- Drops everyone you haven't added who isn't in your guild or group right now. Removes
-- nobody when it can't tell who is there (Net.cleanUpSafe).
function Net.cleanUp()
	if not loaded() then
		return
	end
	local inGuild = Capture.call(IsInGuild)
	if not Capture.readable(inGuild) or type(inGuild) ~= "boolean" then
		inGuild = nil
	end
	local keep, namesOk, guildSize = presentNames()
	if not Net.cleanUpSafe(inGuild, guildSize, namesOk) then
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			Capture.call(C_GuildInfo.GuildRoster) -- ask for the roster, for the next try
		end
		ns.Print("Can't read your guild and group right now, so nobody was removed. Try Clean up again in a moment.")
		return
	end
	local removed = Friends.purge(ns.db.friends, keep)
	ns.Print(removed == 1 and "Removed 1 person." or ("Removed " .. removed .. " people."))
	refreshFriends()
end

-- Opens someone's saved dex at once when there is one (Net.browsePlan), and asks them
-- for a fresh one unless they're offline; "D" opens it (handlers.D). No answer after
-- ANSWER_WAIT: one more ask; none by REQUEST_TTL: give up. Once they announce it ("W")
-- there is no second ask, and the wait lasts as long as the dex's size needs
-- (handlers.W). With a saved copy on screen the ask says nothing in chat.
function Net.browse(name)
	if not state.enabled then
		ns.Print("Friends need AceComm-3.0 (a packaged build).")
		return
	end
	local store = ns.db and ns.db.friends or {}
	local saved, savedAt = Friends.savedDex(store, name)
	local copy = saved and Comm.decodeDex(saved)
	if saved and not copy then
		Friends.dropDex(store, name) -- unreadable (an older wire format): ask as before
	end
	local upToDate = Friends.dexCurrent(store[name])
	local plan = Net.browsePlan(copy ~= nil and copy ~= false, Friends.isOnline(store[name], time()), upToDate)
	if plan.copy then
		openDex(copy, name, not upToDate and savedAt or nil) -- a current copy needs no date
	end
	if not plan.ask then
		refreshFriends()
		return
	end
	local asked = GetTime()
	local current = requestTo(name)
	if current and current.comingAt and asked <= current.deadline then
		refreshFriends() -- already on its way: asking again would only be ignored
		return
	end
	local quiet = plan.quiet
	local req = { name = name, asked = asked, deadline = asked + REQUEST_TTL, quiet = quiet }
	state.request = req -- a late dex from someone asked earlier is not wanted now
	state.asking = name
	state.noAnswer = nil
	local request = Comm.encodeRequest("R")
	whisper(request, name)
	refreshFriends()
	local function stillAsking()
		return state.asking == name and state.request == req
	end
	C_Timer.After(ANSWER_WAIT, function()
		if stillAsking() and not req.comingAt then
			if not quiet then
				ns.Print("No answer from " .. name .. " yet, asking again...")
			end
			whisper(request, name)
			refreshFriends()
		end
	end)
	local function giveUp()
		if not stillAsking() then
			return
		end
		local left = req.deadline - GetTime()
		if left > 0 then
			C_Timer.After(left, giveUp) -- the deadline moved: the dex was announced
			return
		end
		local text = req.comingAt and (name .. "'s dex didn't arrive in time.") or ("No answer from " .. name .. ".")
		if quiet then
			text = text .. " Showing the copy saved " .. (ns.UIFormat.dateText(savedAt) or "earlier") .. "."
		else
			ns.Print(text)
		end
		state.request = nil
		state.asking = nil
		state.noAnswer, state.noAnswerText = name, text
		refreshFriends()
	end
	C_Timer.After(REQUEST_TTL, giveUp)
end

-- Friends tab ------------------------------------------------------------------------------

local ROW_H, LINE_H, BOX_H, BUTTON_H = 16, 15, 16, 16

local CLEANUP_W = 58
local CLEANUP_POPUP = "SOULDEX_CLEANUP"

local tab = {} -- frames, built once
local removeButtons = {} -- leaderboard row -> its "×" button
local removable = {} -- leaderboard row -> true when it shows a person (not the hint)

-- Hovering a person: the "×" takes the score's place, and a tooltip shows the full name
-- (a long two-part name can still be cut off in the list).
local function onRowEnter(row)
	if removable[row] then
		row.right:Hide()
		removeButtons[row]:Show()
		if not GameTooltip then
			return
		end
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(row.value)
		GameTooltip:Show()
	end
end

local function onRowLeave(row)
	if not row:IsMouseOver() then
		removeButtons[row]:Hide()
		row.right:Show()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end
end

-- Each pooled leaderboard row gets a hover-only "×" that removes that person.
local function decorateRows()
	local UI = ns.UI
	for _, row in ipairs(tab.list.rows) do
		local remove = removeButtons[row]
		if not remove then
			remove = UI.textButton(row, "\195\151", 12)
			remove:SetPoint("RIGHT", -2, 0)
			remove:SetScript("OnClick", function()
				Net.removeFriend(row.value)
			end)
			remove:SetScript("OnLeave", function(self)
				UI.textColor(self.label, "TITLE")
				onRowLeave(row)
			end)
			row:SetScript("OnEnter", onRowEnter)
			row:SetScript("OnLeave", onRowLeave)
			removeButtons[row] = remove
		end
		removable[row] = row.value ~= nil
		remove:Hide()
		-- A redraw under the mouse: keep the "×" of the row it is still over.
		if removable[row] and row.IsMouseOver and row:IsShown() and row:IsMouseOver() then
			onRowEnter(row)
		end
	end
end

local function buildTab(left, right)
	local UI = ns.UI
	local leftW, rightW, h = UI.FRIENDS_LEFT_W, UI.FRIENDS_RIGHT_W, UI.FRIENDS_H

	tab.list = UI.newList(left, leftW, h - BOX_H - 4, ROW_H, false)
	tab.list.frame:SetPoint("TOPLEFT", 0, 0)

	local box = CreateFrame("EditBox", nil, left, "BackdropTemplate")
	box:SetSize(leftW - CLEANUP_W - 4, BOX_H)
	box:SetPoint("BOTTOMLEFT", 0, 0)
	box:SetAutoFocus(false)
	box:SetMaxLetters(48)
	box:SetFontObject(GameFontHighlightSmall)
	box:SetTextInsets(4, 4, 0, 0)
	UI.backdrop(box, "PANE_BG", "DIVIDER")
	local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", 4, 0)
	hint:SetText("Add...")
	UI.textColor(hint, "MUTED")
	local function showHint(self)
		ns.UIList.setShown(hint, (self:GetText() or "") == "" and not self:HasFocus())
	end
	box:SetScript("OnEnterPressed", function(self)
		local text = self:GetText() or ""
		self:SetText("")
		self:ClearFocus()
		if text:match("%S") then
			Net.addFriend(text)
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", showHint)
	box:SetScript("OnEditFocusLost", showHint)
	box:SetScript("OnTextChanged", showHint)
	tab.box = box

	StaticPopupDialogs[CLEANUP_POPUP] = {
		text = "Remove everyone you haven't added who isn't in your guild or group right now?\n\n"
			.. "They come back if they send their score again.",
		button1 = "Remove",
		button2 = "Cancel",
		OnAccept = Net.cleanUp,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	tab.cleanUp = UI.button(left, "Clean up", CLEANUP_W, BUTTON_H)
	tab.cleanUp:SetPoint("BOTTOMRIGHT", 0, 0)
	tab.cleanUp:SetScript("OnClick", function()
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			Capture.call(C_GuildInfo.GuildRoster) -- fresh guild names while the dialog is up
		end
		StaticPopup_Show(CLEANUP_POPUP)
	end)

	tab.info = UI.newList(right, rightW, h - BUTTON_H - 6, LINE_H, true)
	tab.info.frame:SetPoint("TOPLEFT", 0, 0)

	tab.browse = UI.button(right, "Browse dex", 76, BUTTON_H)
	tab.browse:SetPoint("BOTTOMLEFT", 4, 2)
	tab.browse:SetScript("OnClick", function()
		if state.selected then
			Net.browse(state.selected)
		end
	end)
	tab.status = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tab.status:SetPoint("LEFT", tab.browse, "RIGHT", 6, 0)
	tab.status:SetPoint("RIGHT", right, "RIGHT", -4, 0)
	tab.status:SetJustifyH("LEFT")
	tab.status:SetWordWrap(false)
	UI.textColor(tab.status, "MUTED")
end

local function selectPerson(name)
	state.selected = name
	state.noAnswer = nil
	ns.UI.refresh()
end

local function statusText(name)
	if state.asking == name then
		local req, now = requestTo(name) or {}, GetTime()
		local stage = Net.browseStage(req.asked, now, req.deadline, req.comingAt ~= nil)
		return Net.browseStatus(name, stage, req.comingAt and Net.receiveLeft(req.comingAt, req.bytes, now))
	elseif state.noAnswer == name then
		return state.noAnswerText or ("No answer from " .. name .. ".")
	end
	return ""
end

-- setFriendsTab builder: called every time the Friends tab draws.
local function drawTab(left, right)
	if not tab.list then
		buildTab(left, right)
	end
	local dex, db = ns.dex, ns.db
	if not dex or not db or not db.friends then
		return
	end
	local me = Net.me(dex)
	-- Your own row is only there to rank you (the Me tab); the list shows other people.
	local rows, others, byName = Friends.leaderboard(db.friends, me, time()), {}, {}
	for _, r in ipairs(rows) do
		if not r.isMe then
			others[#others + 1] = r
			byName[r.name] = r
		end
	end
	local selectedRow = byName[state.selected] or others[1]
	state.selected = selectedRow and selectedRow.name
	tab.list:set(Net.leaderRows(rows, state.selected), selectPerson, true)
	decorateRows()
	tab.info:set(selectedRow and Net.personLines(selectedRow, db.friends[selectedRow.name]) or {}, nil, false)
	ns.UIList.setShown(tab.browse, selectedRow ~= nil)
	tab.status:SetText(selectedRow and statusText(selectedRow.name) or "")
end

-- Start ------------------------------------------------------------------------------------

-- Re-reads guild and group classes and drops anyone saved who turns out not to be a warlock.
local function refreshClasses()
	if not (ns.db and ns.db.friends) then
		return
	end
	state.classes = rosterClasses()
	if Friends.dropNonWarlocks(ns.db.friends, state.classes) > 0 then
		refreshFriends()
	end
end

local function start(db)
	db.friends = type(db.friends) == "table" and db.friends or {}
	Friends.tidy(db.friends, myName(), time())
	refreshClasses()
	if ns.UI then
		ns.UI.setFriendsTab(drawTab)
	end

	local AceComm = LibStub and LibStub("AceComm-3.0", true)
	if not AceComm then
		ns.Print("Friends are offline: AceComm-3.0 is missing (install a packaged build).")
		return
	end
	AceComm:Embed(Net)
	Net:RegisterComm(Comm.PREFIX)
	state.enabled = true

	local entered = false
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	frame:RegisterEvent("GUILD_ROSTER_UPDATE")
	frame:SetScript("OnEvent", function(_, event)
		if event == "GUILD_ROSTER_UPDATE" then
			refreshClasses()
		elseif event == "PLAYER_ENTERING_WORLD" then
			if not entered then
				entered = true
				C_Timer.After(LOGIN_DELAY, function()
					requestBroadcast()
					askForSummaries()
				end)
			end
		else -- GROUP_ROSTER_UPDATE
			refreshClasses()
			if yes(IsInGroup) then
				requestBroadcast()
			end
		end
	end)
	C_Timer.NewTicker(POLL_EVERY, tick)

	-- Whispering an offline friend prints "No player named ... is currently playing."; hide
	-- that line for names SoulDex itself whispered a moment ago.
	if ChatFrame_AddMessageEventFilter then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
			if not Capture.plainString(msg) then
				return false -- unreadable (a secret value): no string work on it
			end
			local name = Friends.normalise(Net.notFoundName(msg, ERR_CHAT_PLAYER_NOT_FOUND_S))
			local at = name and state.whispered[name]
			return at ~= nil and GetTime() - at <= NOT_FOUND_WINDOW
		end)
	end

	ns.onCatch = ns.onCatch or {}
	table.insert(ns.onCatch, requestBroadcast)
end

ns.onLoaded = ns.onLoaded or {}
table.insert(ns.onLoaded, start)
