-- Friends glue: swaps summaries and dexes with other SoulDex users over AceComm-3.0,
-- draws the Friends tab (leaderboard, add/remove, the selected person's numbers) and
-- opens a friend's dex for browsing. The decision helpers are pure and tested; the
-- wiring below them is game code. Wall-clock time() for every saved `seen`, GetTime()
-- for throttles.
--
-- Messages (src/Comm.lua): "S" summary, "Q" ask for a summary, "R" ask for the dex,
-- "D" the dex. Summaries go to the guild and group; everything else is a whisper.
local _, ns = ...

local Net = {}
ns.Net = Net

local SUMMARY_GAP = 30 -- seconds between summary broadcasts
local HEARTBEAT = 300 -- re-broadcast while quiet, so you stay "online" (Friends: seen < 600 s ago)
local NEWCOMER_AFTER = HEARTBEAT + 60 -- not heard from this long: answer their summary with ours
local DEX_REPLY_GAP = 30 -- at most one "R" reply per sender
local SUMMARY_REPLY_GAP = 10 -- at most one "Q" reply per sender
local POLL_EVERY = 60 -- ask added friends for a summary
local LOGIN_DELAY = 5
local ANSWER_WAIT = 60 -- no dex yet: say so in chat and ask once more
local REQUEST_TTL = 90 -- still nothing: "No answer from <name>." and a late "D" is ignored
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
	elseif kind == "D" then
		return distribution == "WHISPER" and requested == true
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
-- time) until REQUEST_TTL, then "expired" (a late "D" is ignored).
function Net.browseStage(asked, now)
	local age = asked and now - asked
	if not age or age > REQUEST_TTL then
		return "expired"
	elseif age > ANSWER_WAIT then
		return "retrying"
	end
	return "asking"
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
-- its ranked place (highlighted, not selectable) when Net.showSelf, otherwise it is left out
-- and the help text shows.
function Net.leaderRows(rows, selected)
	local C = ns.UIFormat.COLORS
	local out = {}
	if not Net.showSelf(rows) then
		rows = {}
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
			right = tostring(r.score),
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
	local status, statusColor = "online", C.GREEN
	if not row.online then
		status, statusColor = "offline", C.DIM
	end
	local function kv(label, value)
		return { text = label, color = C.MUTED, right = value, rightColor = C.TEXT }
	end
	local lines = {
		{ text = row.name, color = C.WHITE, right = status, rightColor = statusColor, big = true },
		{ hr = true },
		{ text = "Score", color = C.MUTED, right = row.score .. " pts", rightColor = C.GREEN },
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
	return lines
end

-- Game wiring ---------------------------------------------------------------------------

local Friends, Comm, Capture = ns.Friends, ns.Comm, ns.Capture

local state = {
	enabled = false, -- AceComm found and registered
	lastBroadcast = nil, -- GetTime() of the last summary broadcast
	queued = false, -- a throttled broadcast is waiting
	summaryReplies = {}, -- name -> GetTime() of the last "Q" answer
	dexReplies = {}, -- name -> GetTime() of the last "R" answer
	requests = {}, -- name -> GetTime() we asked them for their dex
	whispered = {}, -- name -> GetTime() we last whispered them
	asking = nil, -- name shown as "Asking <name>..."
	noAnswer = nil, -- name shown as "No answer from <name>."
	selected = nil, -- leaderboard selection
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

local function send(msg, distribution, target, prio)
	if state.enabled and msg then
		Net:SendCommMessage(Comm.PREFIX, msg, distribution, target, prio)
	end
end

local function whisper(msg, target, prio)
	local key = Friends.normalise(target)
	if key then
		state.whispered[key] = GetTime()
	end
	send(msg, "WHISPER", target, prio)
end

local function summaryMessage()
	return Comm.encodeSummary(Friends.summaryOf(ns.dex))
end

local function broadcastNow()
	state.lastBroadcast = GetTime()
	local msg = summaryMessage()
	for _, channel in ipairs(Net.channels(yes(IsInGuild), yes(IsInRaid), yes(IsInGroup))) do
		send(msg, channel)
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
	Net.forgetOlder(state.requests, now, REQUEST_TTL)
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
			requestBroadcast() -- so they learn about you too
		end
		refreshFriends()
	end
end

function handlers.Q(name, target)
	local now = GetTime()
	if Net.allowed(state.summaryReplies[name], now, SUMMARY_REPLY_GAP) then
		state.summaryReplies[name] = now
		whisper(summaryMessage(), target)
	end
end

function handlers.R(name, target)
	local now = GetTime()
	if Net.allowed(state.dexReplies[name], now, DEX_REPLY_GAP) then
		state.dexReplies[name] = now
		whisper(Comm.encodeDex(ns.db), target, "BULK")
	end
end

-- db is nil when the dex couldn't be read.
function handlers.D(name, _, db)
	state.requests[name] = nil
	if state.asking == name then
		state.asking = nil
	end
	if not db then
		ns.Print("Couldn't read " .. name .. "'s dex.")
		refreshFriends()
		return
	end
	local UI = ns.UI
	if UI then
		UI.showDex(ns.Dex.new(db), name)
		UI.setCompare(ns.dex)
		if UI.currentTab() == "Friends" then
			UI.selectTab("Mobs")
		end
	end
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
	local kind = message:sub(1, 1)
	local entry = ns.db.friends[name]
	local asked = state.requests[name]
	local requested = asked ~= nil and GetTime() - asked <= REQUEST_TTL
	if not handlers[kind] or not Net.accepts(kind, distribution, entry ~= nil and entry.added, requested) then
		return
	end
	local decoded, payload = Comm.decode(message)
	if decoded == kind then
		handlers[kind](name, target, payload, distribution)
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

-- Names of everyone in your group and guild right now (store keys), as a set.
local function presentNames()
	local plain = Capture.plainString
	local keep = {}
	local function note(name, second)
		local key = plain(name) and Friends.normalise(Friends.fullName(name, plain(second) and second or nil))
		if key then
			keep[key] = true
		end
	end
	local members = Capture.call(GetNumGroupMembers)
	local prefix = yes(IsInRaid) and "raid" or "party"
	for i = 1, Capture.plainNumber(members) and members or 0 do
		note(Capture.call(UnitName, prefix .. i))
	end
	local guildSize = Capture.call(GetNumGuildMembers)
	for i = 1, Capture.plainNumber(guildSize) and guildSize or 0 do
		note(Capture.call(GetGuildRosterInfo, i))
	end
	return keep
end

-- Drops everyone you haven't added who isn't in your guild or group right now.
function Net.cleanUp()
	if not loaded() then
		return
	end
	local removed = Friends.purge(ns.db.friends, presentNames())
	ns.Print(removed == 1 and "Removed 1 person." or ("Removed " .. removed .. " people."))
	refreshFriends()
end

-- Asks someone for their dex; "D" opens it (handlers.D). No answer after ANSWER_WAIT:
-- one more ask; none by REQUEST_TTL: give up.
function Net.browse(name)
	if not state.enabled then
		ns.Print("Friends need AceComm-3.0 (a packaged build).")
		return
	end
	local asked = GetTime()
	state.requests = { [name] = asked } -- a late dex from someone asked earlier is not wanted now
	state.asking = name
	state.noAnswer = nil
	local request = Comm.encodeRequest("R")
	whisper(request, name)
	refreshFriends()
	local function stillAsking()
		return state.asking == name and state.requests[name] == asked
	end
	C_Timer.After(ANSWER_WAIT, function()
		if stillAsking() then
			ns.Print("No answer from " .. name .. " yet, asking again...")
			whisper(request, name)
			refreshFriends()
		end
	end)
	C_Timer.After(REQUEST_TTL, function()
		if stillAsking() then
			ns.Print("No answer from " .. name .. ".")
			state.requests[name] = nil
			state.asking = nil
			state.noAnswer = name
			refreshFriends()
		end
	end)
end

-- Friends tab ------------------------------------------------------------------------------

local PANE_BG, DIVIDER = "0d0a14", "3d2d5c"
local ROW_H, LINE_H, BOX_H, BUTTON_H = 16, 15, 16, 16

local CLEANUP_W = 58
local CLEANUP_POPUP = "SOULDEX_CLEANUP"

local tab = {} -- frames, built once
local removeButtons = {} -- leaderboard row -> its "×" button
local removable = {} -- leaderboard row -> true when it shows a person (not the hint)

local function onRowEnter(row)
	if removable[row] then
		row.right:Hide()
		removeButtons[row]:Show()
	end
end

local function onRowLeave(row)
	if not row:IsMouseOver() then
		removeButtons[row]:Hide()
		row.right:Show()
	end
end

-- Each pooled leaderboard row gets a hover-only "×" that removes that person.
local function decorateRows()
	local UI, C = ns.UI, ns.UIFormat.COLORS
	for _, row in ipairs(tab.list.rows) do
		local remove = removeButtons[row]
		if not remove then
			remove = UI.textButton(row, "\195\151", 12)
			remove:SetPoint("RIGHT", -2, 0)
			remove:SetScript("OnClick", function()
				Net.removeFriend(row.value)
			end)
			remove:SetScript("OnLeave", function(self)
				UI.textColor(self.label, C.TITLE)
				onRowLeave(row)
			end)
			row:SetScript("OnEnter", onRowEnter)
			row:SetScript("OnLeave", onRowLeave)
			removeButtons[row] = remove
		end
		removable[row] = row.value ~= nil
		remove:Hide()
	end
end

local function buildTab(left, right)
	local UI, C = ns.UI, ns.UIFormat.COLORS
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
	UI.backdrop(box, PANE_BG, DIVIDER)
	local hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", 4, 0)
	hint:SetText("Add...")
	UI.textColor(hint, C.MUTED)
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
	UI.textColor(tab.status, C.MUTED)
end

local function selectPerson(name)
	state.selected = name
	state.noAnswer = nil
	ns.UI.refresh()
end

local function statusText(name)
	if state.asking == name then
		if Net.browseStage(state.requests[name], GetTime()) == "asking" then
			return "Asking " .. name .. "..."
		end
		return "Asking " .. name .. " again..."
	elseif state.noAnswer == name then
		return "No answer from " .. name .. "."
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

local function start(db)
	db.friends = type(db.friends) == "table" and db.friends or {}
	Friends.tidy(db.friends, myName())
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
	frame:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" then
			if not entered then
				entered = true
				C_Timer.After(LOGIN_DELAY, function()
					requestBroadcast()
					askForSummaries()
				end)
			end
		elseif yes(IsInGroup) then
			requestBroadcast()
		end
	end)
	C_Timer.NewTicker(POLL_EVERY, tick)

	-- Whispering an offline friend prints "No player named ... is currently playing."; hide
	-- that line for names SoulDex itself whispered a moment ago.
	if ChatFrame_AddMessageEventFilter then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
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
