-- The dex window: title bar with the rank chip and progress line, six tabs, two scrolling
-- lists (or one full-width list for Milestones, or the rank crest, tiles and records of
-- the Me tab) and the slide-in trophy card (src/UIDetail.lua). Game code; the row and
-- card contents come from the pure ns.View and ns.UIFormat.
local _, ns = ...

local UI = {}
ns.UI = UI

local F = ns.UIFormat
local C = F.COLORS

local WIDTH, HEIGHT = 380, 280
local PAD = 7
local TITLE_H, TAB_H = 20, 18
local LEFT_W = 124
local BODY_W = WIDTH - 2 * PAD
local BODY_H = HEIGHT - 2 * PAD - TITLE_H - TAB_H - 10
local RIGHT_X = LEFT_W + 5 -- right list starts after the divider
local PANE_X = LEFT_W + 3 -- the detail pane covers the right list
local LEFT_ROW_H, RIGHT_ROW_H = 16, 17
local FULL_ROW_H = 16 -- Me and Milestones: the rank lines and nine stats fit without scrolling

UI.TABS = { "Me", "Mobs", "Players", "Raids", "Milestones", "Friends" }

-- Friends gets a wider left column than the other tabs, so two-part names fit in the
-- leaderboard ("2. Psepsis Doomchov"); its right side only holds short numbers.
local FRIENDS_LEFT_W = 164
local FRIENDS_RIGHT_X = FRIENDS_LEFT_W + 5

-- Sizes of the two Friends tab frames handed to the builder (see setFriendsTab).
UI.FRIENDS_LEFT_W, UI.FRIENDS_RIGHT_W, UI.FRIENDS_H = FRIENDS_LEFT_W, BODY_W - FRIENDS_RIGHT_X, BODY_H

local TILE_H, TILE_GAP = 30, 3

-- Shared painting helpers (src/UIList.lua), kept on UI for callers.
local L = ns.UIList
UI.textColor, UI.fill, UI.backdrop, UI.newList, UI.button = L.textColor, L.fill, L.backdrop, L.new, L.button
local setShown = L.setShown

-- Window state ----------------------------------------------------------------------

local state = {
	tab = "Mobs",
	dex = nil, -- the dex on screen; nil = your own (ns.dex)
	owner = nil, -- whose dex it is when browsing a friend
	savedAt = nil, -- when browsing a saved copy of their dex: the time() it arrived
	compare = nil, -- the dex rows are compared with while browsing (Task 13)
	sel = {}, -- selection on the left, per tab
	msOpen = {}, -- Milestones groups whose earned rows are showing
	detail = nil, -- { tab, value } of the open detail pane
	friendsBuilder = nil,
}

local frame, titleLeft, titleRight, divider, myDexButton
local chip, rankFill, emblem
local leftList, rightList, fullList, pane
local meBox, crest, tiles, recordList
local friendsBox, friendsLeft, friendsRight, friendsNote
local tabButtons = {}

local function dexNow()
	return state.dex or ns.dex
end

local function other()
	if state.owner then
		return state.compare
	end
	return nil
end

local function isTab(name)
	for _, tab in ipairs(UI.TABS) do
		if tab == name then
			return true
		end
	end
	return false
end

-- Drawing ---------------------------------------------------------------------------

local function detailCard(tab, value)
	local dex, View = dexNow(), ns.View
	local card
	if tab == "Mobs" then
		local d = View.mobDetail(dex, value, state.sel.Mobs)
		card = d and F.mobCard(d)
	elseif tab == "Players" then
		local d = View.playerDetail(dex, value)
		card = d and F.playerCard(d, nil, RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE)
	elseif tab == "Raids" then
		local d = View.raidDetail(dex, value)
		card = d and F.mobCard(d)
	end
	-- A card with no icon of its own wears the rank emblem of the dex on screen.
	if card and not card.icon then
		card.icon = ns.Ranks.of(dex:score()).emblem
		card.ownArt = true
	end
	return card
end

local function closeDetail(instant)
	state.detail = nil
	if pane then
		pane:close(instant)
	end
end

local function openDetail(value)
	local card = detailCard(state.tab, value)
	if not card then
		return
	end
	state.detail = { tab = state.tab, value = value }
	pane:open(card)
end

local draw

local function selectLeft(value)
	state.sel[state.tab] = value
	closeDetail(true)
	draw("select")
end

local function styleTabs()
	for _, button in ipairs(tabButtons) do
		local on = button.tab == state.tab
		UI.backdrop(button, on and "DIVIDER" or "TAB_BG", on and "BORDER" or "DIVIDER")
		UI.textColor(button.label, on and "WHITE" or "TEXT")
		setShown(button.underline, on)
	end
end

local function drawLists(dex, keepLeft, keepRight)
	local View, tab = ns.View, state.tab
	local leftRows, rightRows
	if tab == "Mobs" then
		local places = View.places(dex)
		local place = F.pick(places, "place", state.sel.Mobs)
		state.sel.Mobs = place
		leftRows = F.placeRows(places, place, dex:uniqueMobs(), state.owner ~= nil)
		rightRows = place and F.mobRows(View.mobsAt(dex, place, other()))
			or { F.note("No souls claimed yet. Go drain something.") }
	elseif tab == "Players" then
		local classes = View.classes(dex)
		local class = F.pick(classes, "class", state.sel.Players)
		state.sel.Players = class
		leftRows = F.classRows(classes, class, RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE,
			dex:uniquePlayers(), state.owner ~= nil)
		rightRows = class and F.playerRows(View.playersOf(dex, class, other())) or { F.note("No player souls yet.") }
	else
		local raids = View.raids(dex)
		-- Selected by raid key: a TBD raid has no instance id until a soul is claimed there.
		local key = F.pick(raids, "key", state.sel.Raids)
		state.sel.Raids = key
		leftRows = F.raidRows(raids, key)
		local raid = key and ns.Raids.byKey(key)
		if raid then
			rightRows = F.raidMobRows(View.raidMobs(dex, raid.instanceID, other()))
			if raid.tbd then
				table.insert(rightRows, 1, F.tbdNote(raid))
			end
		else
			rightRows = { F.note("No raid data.") }
		end
	end
	leftList:set(leftRows, selectLeft, keepLeft)
	rightList:set(rightRows, openDetail, keepRight)
end

-- The Me tab: the rank crest on the left, six tiles and the records list on the right.
-- Browsing a friend shows their rank and numbers, and no place among friends.
local function drawMe(dex, keepScroll)
	local card
	if state.owner then
		card = ns.View.meCard(dex, false, nil, 0)
	else
		card = ns.View.meCard(dex, ns.db and ns.db.friends, ns.Net and ns.Net.me(dex), time())
	end
	local rank = ns.Ranks.of(dex:score())
	crest.icon:SetTexture(rank.emblem)
	crest.rank:SetText(rank.name)
	crest.place:SetText("RANK " .. rank.index .. " OF " .. rank.count)
	crest.score:SetText(ns.View.thousands(rank.score) .. " pts")
	if rank.nextName then
		crest.next:SetText(ns.View.thousands(rank.toNext) .. " pts to |cff" .. C.ACCENT .. rank.nextName .. "|r")
	else
		crest.next:SetText("The highest rank")
	end
	local fill = L.barWidth(rank.progress, LEFT_W - 16)
	setShown(crest.fill, fill ~= nil)
	if fill then
		crest.fill:SetWidth(fill)
	end
	for i, tile in ipairs(tiles) do
		local data = card.tiles[i]
		setShown(tile, data ~= nil)
		if data then
			local value = tostring(data.value or F.DASH)
			tile.value:SetText(data.star and (value .. " " .. F.MARKS.ACCENT_STAR) or value)
			UI.textColor(tile.value, data.color or "WHITE")
			tile.label:SetText(data.label:upper())
		end
	end
	local rows = { { text = "RECORDS", color = C.HEADER, header = true } }
	for _, line in ipairs(F.recordLines(card.records, time(), nil, RAID_CLASS_COLORS)) do
		rows[#rows + 1] = line
	end
	recordList:set(rows, nil, keepScroll)
end

-- A click on a Milestones group's "N earned" row opens or closes its earned milestones.
local function toggleMilestones(value)
	local group = type(value) == "string" and value:match("^group:(.+)$")
	if group then
		state.msOpen[group] = not state.msOpen[group] or nil
		draw("refresh")
	end
end

local function drawFriends()
	local builder = state.friendsBuilder
	setShown(friendsNote, builder == nil)
	if builder then
		builder(friendsLeft, friendsRight)
	end
end

-- action: "open", "tab", "select" or "refresh" (see UIFormat.keepScroll).
draw = function(action)
	local dex = dexNow()
	if not frame or not dex then
		return
	end
	local tab = state.tab
	local keepLeft, keepRight = F.keepScroll(action)
	local left, right = ns.View.header(dex, tab)
	titleLeft:ClearAllPoints()
	if state.owner then
		left = F.browseTitle(state.owner, state.savedAt, time())
		titleLeft:SetPoint("LEFT", myDexButton, "RIGHT", 5, 0)
	else
		titleLeft:SetPoint("LEFT", TITLE_H, 0)
	end
	titleLeft:SetPoint("RIGHT", chip, "LEFT", -6, 0)
	-- The rank of the dex on screen: its name on the chip, its progress on the line below.
	local rank = ns.Ranks.of(dex:score())
	chip.label:SetText(rank.name)
	emblem:SetTexture(rank.emblem)
	chip:SetWidth(math.ceil(chip.label:GetStringWidth() or 0) + 12)
	local fill = L.barWidth(rank.progress, BODY_W)
	setShown(rankFill, fill ~= nil)
	if fill then
		rankFill:SetWidth(fill)
	end
	setShown(myDexButton, state.owner ~= nil)
	titleLeft:SetText(left)
	titleRight:SetText(right)
	styleTabs()

	local collection = tab == "Mobs" or tab == "Players" or tab == "Raids"
	leftList:show(collection)
	rightList:show(collection)
	fullList:show(tab == "Milestones")
	setShown(meBox, tab == "Me")
	setShown(divider, tab ~= "Milestones")
	local split = (tab == "Friends" and FRIENDS_LEFT_W or LEFT_W) + 2
	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", split, 0)
	divider:SetPoint("BOTTOMLEFT", split, 0)
	setShown(friendsBox, tab == "Friends")

	if collection then
		drawLists(dex, keepLeft, keepRight)
	elseif tab == "Me" then
		drawMe(dex, keepRight)
	elseif tab == "Milestones" then
		local rows = F.milestoneGroups(ns.Milestones.list(dex), ns.Milestones.GROUPS, state.msOpen)
		fullList:set(rows, toggleMilestones, keepRight)
	else
		drawFriends()
	end

	local detail = state.detail
	if detail then
		local card = detail.tab == tab and detailCard(tab, detail.value)
		if card then
			pane:setCard(card, true)
		else
			closeDetail(true)
		end
	end
end

-- Building --------------------------------------------------------------------------

local function savePosition()
	local db = ns.db
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if db and db.window and point then
		db.window.point, db.window.relPoint, db.window.x, db.window.y = point, relPoint, x, y
	end
end

-- The saved window scale, or the default for a missing or damaged one.
local function savedScale()
	local w = ns.db and ns.db.window
	return ns.Settings.scale(w and w.scale) or ns.Settings.SCALE_DEFAULT
end

local function placeWindow()
	local w = ns.db and ns.db.window or {}
	local scale = savedScale()
	frame:SetScale(scale)
	frame:ClearAllPoints()
	if w.point then
		frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
	else
		-- Offsets are in the window's own scaled units: 60 on screen at every size.
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60 / scale)
	end
end

-- The bottom-right corner: drag it to zoom the whole window (the SIZE setting), its
-- top-left corner staying put. The new size is saved when the mouse is let go.
local function buildGrip()
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	local drag -- while dragging: where it began
	local function follow()
		local x, y = GetCursorPosition()
		local eff = drag.eff
		local scale = ns.Settings.dragScale(drag.scale, WIDTH * eff, HEIGHT * eff, x - drag.x, drag.y - y)
		if scale ~= frame:GetScale() then
			-- Point offsets are in the window's own scaled units: convert, so the
			-- top-left corner stays where it is on screen.
			frame:SetScale(scale)
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", drag.left * drag.scale / scale, drag.top * drag.scale / scale)
		end
	end
	grip:SetScript("OnMouseDown", function()
		local left, top = frame:GetLeft(), frame:GetTop()
		if not left or not top then
			return
		end
		local x, y = GetCursorPosition()
		drag = { x = x, y = y, left = left, top = top, scale = frame:GetScale(), eff = frame:GetEffectiveScale() }
		grip:SetScript("OnUpdate", follow)
	end)
	grip:SetScript("OnMouseUp", function()
		if not drag then
			return
		end
		grip:SetScript("OnUpdate", nil)
		drag = nil
		local w = ns.db and ns.db.window
		if w then
			w.scale = ns.Settings.scale(frame:GetScale())
		end
		savePosition()
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize")
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

local function textButton(parent, text, size)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.label:SetPoint("CENTER")
	button.label:SetText(text)
	UI.textColor(button.label, "TITLE")
	button:SetScript("OnEnter", function(self)
		UI.textColor(self.label, "WHITE")
	end)
	button:SetScript("OnLeave", function(self)
		UI.textColor(self.label, "TITLE")
	end)
	return button
end
UI.textButton = textButton

local function buildTitle()
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", PAD, -PAD)
	bar:SetPoint("TOPRIGHT", -PAD, -PAD)
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		savePosition()
	end)

	-- The emblem of the rank of the dex on screen; the refresh sets its texture.
	emblem = bar:CreateTexture(nil, "ARTWORK")
	emblem:SetSize(TITLE_H - 4, TITLE_H - 4)
	emblem:SetPoint("LEFT", 1, 0)

	local close = textButton(bar, "\195\151", 14)
	close:SetPoint("RIGHT", 0, 1)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local gear = CreateFrame("Button", nil, bar)
	gear:SetSize(12, 12)
	gear:SetPoint("RIGHT", close, "LEFT", -3, 0)
	local icon = gear:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local glow = gear:CreateTexture(nil, "HIGHLIGHT")
	glow:SetAllPoints()
	UI.fill(glow, "WHITE", 0.2)
	gear:SetScript("OnClick", function()
		if ns.Options then
			ns.Options.toggle()
		end
	end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Options")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	titleRight = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	titleRight:SetPoint("RIGHT", gear, "LEFT", -6, 0)
	UI.textColor(titleRight, "TEXT")
	-- The rank chip, left of the totals.
	chip = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	chip:SetSize(60, 14)
	chip:SetPoint("RIGHT", titleRight, "LEFT", -6, 0)
	UI.backdrop(chip, "CHIP_BG", "CHIP_EDGE")
	chip.label = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	chip.label:SetPoint("CENTER", 0, 0)
	UI.textColor(chip.label, "ACCENT")
	-- "« Friends": shown while browsing a friend's dex (draw anchors the title after it).
	-- Back to the list you browsed from, on your own dex.
	myDexButton = UI.button(bar, "\194\171 Friends", 60, 14, function()
		state.tab = "Friends"
		if ns.db and ns.db.window then
			ns.db.window.tab = "Friends"
		end
		UI.showDex(nil, nil)
	end)
	myDexButton:SetPoint("LEFT", 0, 0)
	myDexButton:Hide()

	titleLeft = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleLeft:SetPoint("LEFT", TITLE_H, 0)
	titleLeft:SetPoint("RIGHT", chip, "LEFT", -6, 0)
	titleLeft:SetJustifyH("LEFT")
	titleLeft:SetWordWrap(false)
	UI.textColor(titleLeft, "TITLE")

	-- Under the title: the rank progress line, a track with a fel-green fill.
	local track = frame:CreateTexture(nil, "BORDER")
	track:SetHeight(2)
	track:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
	track:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -1)
	UI.fill(track, "TRACK")
	rankFill = frame:CreateTexture(nil, "ARTWORK")
	rankFill:SetHeight(2)
	rankFill:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
	UI.fill(rankFill, "ACCENT")
end

-- The Me tab: the rank crest in the left column, tiles and records in the right.
local function buildMe(body)
	meBox = CreateFrame("Frame", nil, body)
	meBox:SetAllPoints()

	crest = CreateFrame("Frame", nil, meBox)
	crest:SetPoint("TOPLEFT", 0, 0)
	crest:SetSize(LEFT_W, BODY_H)
	crest.icon = crest:CreateTexture(nil, "ARTWORK")
	crest.icon:SetSize(52, 52)
	crest.icon:SetPoint("TOP", 0, -8)
	crest.rank = crest:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	crest.rank:SetPoint("TOP", crest.icon, "BOTTOM", 0, -6)
	UI.textColor(crest.rank, "ACCENT")
	crest.place = crest:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	crest.place:SetPoint("TOP", crest.rank, "BOTTOM", 0, -2)
	crest.place:SetTextHeight(8)
	UI.textColor(crest.place, "HEADER")
	crest.score = crest:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	crest.score:SetPoint("TOP", crest.place, "BOTTOM", 0, -8)
	UI.textColor(crest.score, "WHITE")
	local track = crest:CreateTexture(nil, "BORDER")
	track:SetSize(LEFT_W - 16, 4)
	track:SetPoint("TOP", crest.score, "BOTTOM", 0, -7)
	UI.fill(track, "TRACK")
	crest.fill = crest:CreateTexture(nil, "ARTWORK")
	crest.fill:SetHeight(4)
	crest.fill:SetPoint("LEFT", track, "LEFT", 0, 0)
	UI.fill(crest.fill, "GOOD")
	crest.next = crest:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	crest.next:SetPoint("TOP", track, "BOTTOM", 0, -5)
	crest.next:SetWidth(LEFT_W - 8)
	UI.textColor(crest.next, "MUTED")

	local rightW = BODY_W - RIGHT_X
	local tileW = (rightW - 2 * TILE_GAP) / 3
	tiles = {}
	for i = 1, 6 do
		local tile = CreateFrame("Frame", nil, meBox, "BackdropTemplate")
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		tile:SetSize(tileW, TILE_H)
		tile:SetPoint("TOPLEFT", RIGHT_X + col * (tileW + TILE_GAP), -2 - row * (TILE_H + TILE_GAP))
		UI.backdrop(tile, "TILE_BG", "TILE_EDGE")
		tile.value = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		tile.value:SetPoint("TOP", 0, -4)
		tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		tile.label:SetPoint("BOTTOM", 0, 3)
		tile.label:SetTextHeight(7.5)
		UI.textColor(tile.label, "HEADER")
		tiles[i] = tile
	end
	local top = 2 + 2 * (TILE_H + TILE_GAP) + 2
	recordList = UI.newList(meBox, rightW, BODY_H - top, LEFT_ROW_H, true)
	recordList.frame:SetPoint("TOPLEFT", RIGHT_X, -top)
	meBox:Hide()
end

local function buildBody()
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_H + 6))
	body:SetSize(BODY_W, BODY_H)
	if body.SetClipsChildren then
		body:SetClipsChildren(true) -- the detail pane slides in from outside
	end

	leftList = UI.newList(body, LEFT_W, BODY_H, LEFT_ROW_H, false)
	leftList.frame:SetPoint("TOPLEFT", 0, 0)
	rightList = UI.newList(body, BODY_W - RIGHT_X, BODY_H, RIGHT_ROW_H, true)
	rightList.frame:SetPoint("TOPLEFT", RIGHT_X, 0)
	fullList = UI.newList(body, BODY_W, BODY_H, FULL_ROW_H, true)
	fullList.frame:SetPoint("TOPLEFT", 0, 0)

	divider = body:CreateTexture(nil, "ARTWORK")
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", LEFT_W + 2, 0)
	divider:SetPoint("BOTTOMLEFT", LEFT_W + 2, 0)
	UI.fill(divider, "DIVIDER")

	friendsBox = CreateFrame("Frame", nil, body)
	friendsBox:SetAllPoints()
	friendsLeft = CreateFrame("Frame", nil, friendsBox)
	friendsLeft:SetPoint("TOPLEFT", 0, 0)
	friendsLeft:SetSize(FRIENDS_LEFT_W, BODY_H)
	friendsRight = CreateFrame("Frame", nil, friendsBox)
	friendsRight:SetPoint("TOPLEFT", FRIENDS_RIGHT_X, 0)
	friendsRight:SetSize(BODY_W - FRIENDS_RIGHT_X, BODY_H)
	friendsNote = friendsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	friendsNote:SetPoint("CENTER")
	friendsNote:SetText("Friends arrive soon")
	UI.textColor(friendsNote, "MUTED")

	buildMe(body)

	pane = ns.UIDetail.create(body, PANE_X, BODY_W - PANE_X, BODY_H, function()
		state.detail = nil
	end)
end

local function buildTabs()
	local previous
	for i, name in ipairs(UI.TABS) do
		local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
		button.tab = name
		button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.label:SetPoint("CENTER", 0, 0)
		button.label:SetText(name)
		-- The active tab's fel-green underline.
		button.underline = button:CreateTexture(nil, "OVERLAY")
		button.underline:SetHeight(2)
		button.underline:SetPoint("BOTTOMLEFT", 3, 0)
		button.underline:SetPoint("BOTTOMRIGHT", -3, 0)
		UI.fill(button.underline, "ACCENT")
		button:SetSize(math.max(34, math.ceil(button.label:GetStringWidth() or 0) + 14), TAB_H - 2)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
		else
			button:SetPoint("BOTTOMLEFT", PAD, PAD)
		end
		button:SetScript("OnClick", function(self)
			UI.selectTab(self.tab)
		end)
		tabButtons[i] = button
		previous = button
	end
end

local function build()
	frame = CreateFrame("Frame", "SoulDexFrame", UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	UI.backdrop(frame, "BG", "BORDER", 0.97)
	-- Shading: lighter purple at the top fading to near-black at the bottom.
	local shade = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	shade:SetPoint("TOPLEFT", 1, -1)
	shade:SetPoint("BOTTOMRIGHT", -1, 1)
	L.gradient(shade, "VERTICAL", "SHADE_BOTTOM", 0.97, "SHADE_TOP", 0.97)
	placeWindow()
	buildGrip()
	table.insert(UISpecialFrames, "SoulDexFrame") -- Escape closes it
	buildTitle()
	buildBody()
	buildTabs()
	-- Closing the window while browsing a friend: it reopens on your own dex.
	frame:SetScript("OnHide", function()
		closeDetail(true)
		state.dex, state.owner, state.compare, state.savedAt = nil, nil, nil, nil
	end)
	frame:Hide()
end

-- Public API --------------------------------------------------------------------------

local function ready()
	if ns.db and dexNow() then
		return true
	end
	ns.Print("SoulDex is still loading.")
	return false
end

function UI.toggle()
	if not ready() then
		return
	end
	if not frame then
		build()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		draw("open")
	end
end

-- Shows `dex` (nil = yours). ownerName nil means it is your own; otherwise you are
-- browsing that friend's dex and rows compare against setCompare's dex. savedAt: the
-- time() a saved copy of their dex arrived, shown in the title (nil for a fresh one).
function UI.showDex(dex, ownerName, savedAt)
	state.dex = dex
	state.owner = ownerName
	state.savedAt = ownerName and savedAt or nil
	if not ownerName then
		state.compare = nil
	end
	if not ready() then
		return
	end
	if not frame then
		build()
	end
	closeDetail(true)
	frame:Show()
	draw("open")
end

function UI.refresh()
	if frame and frame:IsShown() then
		draw("refresh")
	end
end

-- The window's scale (Settings.scale: 0.6 to 1.6), saved; returns the scale now in use.
-- nil or junk leaves it as it is. A window that was dragged somewhere keeps that corner
-- where it is on screen: its saved offsets are in the window's own scaled units.
function UI.setScale(value)
	local scale = ns.Settings.scale(value)
	local w = ns.db and ns.db.window
	if scale and w then
		local old = savedScale()
		if type(w.x) == "number" and type(w.y) == "number" then
			w.x, w.y = w.x * old / scale, w.y * old / scale
		end
		w.scale = scale
		if frame then
			placeWindow()
		end
	end
	return savedScale()
end

function UI.scale()
	return savedScale()
end

-- Back to the middle of the screen at the default scale (/souldex reset): the way out
-- when the window ended up somewhere it can't be reached.
function UI.resetWindow()
	local w = ns.db and ns.db.window
	if not w then
		return
	end
	w.point, w.relPoint, w.x, w.y, w.scale = nil, nil, nil, nil, nil
	if frame then
		placeWindow()
	end
end

-- Switches the colour theme (an id from ns.Themes; an unknown one gives the default),
-- saves it for this character and repaints the window and the options at once. The
-- popups take it on their next show. Returns the id now in use.
function UI.setTheme(id)
	id = F.applyTheme(id)
	if ns.db and ns.db.settings then
		ns.db.settings.theme = id
	end
	L.repaint()
	UI.refresh()
	return id
end

function UI.isShown()
	return frame ~= nil and frame:IsShown() and true or false
end

function UI.currentTab()
	return state.tab
end

function UI.isBrowsing()
	return state.owner ~= nil
end

-- Whose dex is on screen (nil = your own).
function UI.owner()
	return state.owner
end

function UI.setCompare(otherDex)
	state.compare = otherDex
	UI.refresh()
end

-- builderFn(leftFrame, rightFrame) draws the Friends tab; called each time it is drawn.
function UI.setFriendsTab(builderFn)
	state.friendsBuilder = builderFn
	UI.refresh()
end

function UI.selectTab(name)
	if not isTab(name) then
		return
	end
	state.tab = name
	if ns.db and ns.db.window then
		ns.db.window.tab = name
	end
	closeDetail(true)
	if frame and frame:IsShown() then
		draw("tab")
	end
end

-- Opens the detail pane for a row value of the current tab (what a row click does).
function UI.openDetail(value)
	if frame and frame:IsShown() then
		openDetail(value)
	end
end

-- Hooks -----------------------------------------------------------------------------

ns.onLoaded = ns.onLoaded or {}
ns.onCatch = ns.onCatch or {}

table.insert(ns.onLoaded, function(db)
	-- The saved theme, before any window or popup is drawn in it.
	F.applyTheme(type(db.settings) == "table" and db.settings.theme)
	db.window = type(db.window) == "table" and db.window or {}
	if isTab(db.window.tab) then
		state.tab = db.window.tab
	end
end)

-- New catches redraw your own dex; browsing a friend stays put.
table.insert(ns.onCatch, function()
	if not state.owner then
		UI.refresh()
	end
end)
