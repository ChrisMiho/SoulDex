-- Friends glue: swaps summaries and dexes with other Soul-Dex users over AceComm-3.0,
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
local REQUEST_TTL = 300 -- a "D" is only accepted this long after we asked for it
local ANSWER_WAIT = 60 -- then the Friends tab says it is still waiting; at REQUEST_TTL, nobody answered
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
	return a == ns.Friends.normalise(ns.Friends.fullName(myName, second)) or a == ns.Friends.normalise(myName)
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

-- A typed name as a store key, or nil when it can't be a character name.
function Net.cleanName(text)
	if type(text) ~= "string" then
		return nil
	end
	text = text:match("^%s*(.-)%s*$")
	if text:find("[%s%d]") then
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

-- Where a browse request stands: "asking" until ANSWER_WAIT, "waiting" until the
-- request's TTL runs out (a late "D" is still accepted), then "expired".
function Net.browseStage(asked, now)
	local age = asked and now - asked
	if not age or age > REQUEST_TTL then
		return "expired"
	elseif age > ANSWER_WAIT then
		return "waiting"
	end
	return "asking"
end

function Net.mySummary(dex)
	return {
		score = dex:score(),
		mobs = dex:uniqueMobs(),
		players = dex:uniquePlayers(),
		raids = dex:raidsCompleted(),
	}
end

-- Whether your own row is listed: only once someone else is on the board.
function Net.showSelf(rows)
	return #rows > 1
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
			text = "Guild and group members with Soul-Dex appear here.",
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

local Friends, Comm = ns.Friends, ns.Comm

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

local function myName()
	return Friends.normalise(Friends.fullName(UnitName("player")))
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
	return Comm.encodeSummary(Net.mySummary(ns.dex))
end

local function broadcastNow()
	state.lastBroadcast = GetTime()
	local msg = summaryMessage()
	for _, channel in ipairs(Net.channels(IsInGuild(), IsInRaid(), IsInGroup())) do
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
	askForSummaries()
	if state.enabled and Net.allowed(state.lastBroadcast, GetTime(), HEARTBEAT) then
		requestBroadcast()
	end
	refreshFriends() -- online/offline changes with time
end

-- Incoming ------------------------------------------------------------------------------

local handlers = {}

function handlers.S(name, _, message, distribution)
	local summary = Comm.decodeSummary(message)
	if not summary then
		return
	end
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

function handlers.D(name, _, message)
	state.requests[name] = nil
	if state.asking == name then
		state.asking = nil
	end
	local kind, db = Comm.decode(message)
	if kind ~= "D" then
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
	local target = Ambiguate(sender, "none")
	if Net.isMe(target, UnitName("player")) then
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
	if handlers[kind] and Net.accepts(kind, distribution, entry ~= nil and entry.added, requested) then
		handlers[kind](name, target, message, distribution)
	end
end

-- Public API (the slash command and the Friends tab) -----------------------------------------

local function loaded()
	if ns.db and ns.db.friends then
		return true
	end
	ns.Print("Soul-Dex is still loading.")
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

function Net.removeFriend(text)
	if not loaded() then
		return
	end
	local name = Net.cleanName(text)
	local entry = name and ns.db.friends[name]
	if not entry or not entry.added then
		ns.Print((name or tostring(text)) .. " isn't on your friends list.")
		return
	end
	Friends.remove(ns.db.friends, name, time())
	ns.Print("Removed " .. name .. ".")
	refreshFriends()
end

-- Asks someone for their dex; "D" opens it (handlers.D).
function Net.browse(name)
	if not state.enabled then
		ns.Print("Friends need AceComm-3.0 (a packaged build).")
		return
	end
	local asked = GetTime()
	state.requests[name] = asked
	state.asking = name
	state.noAnswer = nil
	whisper(Comm.encodeRequest("R"), name)
	refreshFriends()
	C_Timer.After(ANSWER_WAIT, function()
		if state.asking == name and state.requests[name] == asked then
			refreshFriends() -- now reads "Still waiting for <name>'s dex..."
		end
	end)
	C_Timer.After(REQUEST_TTL, function()
		if state.asking == name and state.requests[name] == asked then
			state.asking = nil
			state.noAnswer = name
			refreshFriends()
		end
	end)
end

-- Friends tab ------------------------------------------------------------------------------

local BACK_BG, BACK_BORDER, BACK_HOVER = "251b36", "5a4486", "3d2d5c"
local PANE_BG, DIVIDER = "0d0a14", "3d2d5c"
local ROW_H, LINE_H, BOX_H, BUTTON_H = 16, 15, 16, 16

local tab = {} -- frames, built once
local removeButtons = {} -- leaderboard row -> its "×" button
local removable = {} -- leaderboard row -> true when it shows an added friend

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

-- Each pooled leaderboard row gets a hover-only "×" for added people.
local function decorateRows(added)
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
		removable[row] = row.value ~= nil and added[row.value] == true
		remove:Hide()
	end
end

local function backButton(parent, text, width)
	local UI, C = ns.UI, ns.UIFormat.COLORS
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, BUTTON_H)
	UI.backdrop(button, BACK_BG, BACK_BORDER)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("CENTER", 0, 0)
	button.label:SetText(text)
	UI.textColor(button.label, C.TITLE)
	button:SetScript("OnEnter", function(self)
		UI.backdrop(self, BACK_HOVER, BACK_BORDER)
		UI.textColor(self.label, C.WHITE)
	end)
	button:SetScript("OnLeave", function(self)
		UI.backdrop(self, BACK_BG, BACK_BORDER)
		UI.textColor(self.label, C.TITLE)
	end)
	return button
end

local function buildTab(left, right)
	local UI, C = ns.UI, ns.UIFormat.COLORS
	local leftW, rightW, h = UI.FRIENDS_LEFT_W, UI.FRIENDS_RIGHT_W, UI.FRIENDS_H

	tab.list = UI.newList(left, leftW, h - BOX_H - 4, ROW_H, false)
	tab.list.frame:SetPoint("TOPLEFT", 0, 0)

	local box = CreateFrame("EditBox", nil, left, "BackdropTemplate")
	box:SetSize(leftW, BOX_H)
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

	tab.info = UI.newList(right, rightW, h - BUTTON_H - 6, LINE_H, true)
	tab.info.frame:SetPoint("TOPLEFT", 0, 0)

	tab.browse = backButton(right, "Browse dex", 76)
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
		return "Still waiting for " .. name .. "'s dex..."
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
	local me = { name = myName(), summary = Net.mySummary(dex) }
	-- Your own row is only there to rank you (the Me tab); the list shows other people.
	local rows, others, byName, added = Friends.leaderboard(db.friends, me, time()), {}, {}, {}
	for _, r in ipairs(rows) do
		if not r.isMe then
			others[#others + 1] = r
			byName[r.name] = r
			added[r.name] = r.added
		end
	end
	local selectedRow = byName[state.selected] or others[1]
	state.selected = selectedRow and selectedRow.name
	tab.list:set(Net.leaderRows(rows, state.selected), selectPerson, true)
	decorateRows(added)
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
		elseif IsInGroup() then
			requestBroadcast()
		end
	end)
	C_Timer.NewTicker(POLL_EVERY, tick)

	-- Whispering an offline friend prints "No player named ... is currently playing."; hide
	-- that line for names Soul-Dex itself whispered a moment ago.
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
