-- The dex window: title bar, five tabs, two scrolling lists (or one full-width list
-- for Milestones) and the slide-in detail pane (src/UIDetail.lua). Game code; the
-- row and line contents come from the pure ns.View and ns.UIFormat.
local _, ns = ...

local UI = {}
ns.UI = UI

local F = ns.UIFormat
local C = F.COLORS

local WIDTH, HEIGHT = 360, 232
local PAD = 6
local TITLE_H, TAB_H = 18, 18
local LEFT_W = 124
local BODY_W = WIDTH - 2 * PAD
local BODY_H = HEIGHT - 2 * PAD - TITLE_H - TAB_H - 4
local RIGHT_X = LEFT_W + 5 -- right list starts after the divider
local PANE_X = LEFT_W + 3 -- the detail pane covers the right list
local LEFT_ROW_H, RIGHT_ROW_H = 16, 17

UI.TABS = { "Mobs", "Players", "Raids", "Milestones", "Friends" }

-- Sizes of the two Friends tab frames handed to the builder (see setFriendsTab).
UI.FRIENDS_LEFT_W, UI.FRIENDS_RIGHT_W, UI.FRIENDS_H = LEFT_W, BODY_W - RIGHT_X, BODY_H

local WINDOW_BG, BORDER, DIVIDER = "14101c", "6b4fa0", "3d2d5c"
local TAB_BG = "251b36"
local BACK_BG, BACK_BORDER, BACK_HOVER = "251b36", "5a4486", "3d2d5c"

-- Shared painting helpers (src/UIList.lua), kept on UI for callers.
local L = ns.UIList
UI.textColor, UI.fill, UI.backdrop, UI.newList = L.textColor, L.fill, L.backdrop, L.new
local setShown = L.setShown

-- Window state ----------------------------------------------------------------------

local state = {
	tab = "Mobs",
	dex = nil, -- the dex on screen; nil = your own (ns.dex)
	owner = nil, -- whose dex it is when browsing a friend
	compare = nil, -- the dex rows are compared with while browsing (Task 13)
	sel = {}, -- selection on the left, per tab
	detail = nil, -- { tab, value } of the open detail pane
	friendsBuilder = nil,
}

local frame, titleLeft, titleRight, divider, myDexButton
local leftList, rightList, fullList, pane
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

local function detailLines(tab, value)
	local dex, View = dexNow(), ns.View
	if tab == "Mobs" then
		local d = View.mobDetail(dex, value, state.sel.Mobs)
		return d and F.mobDetailLines(d)
	elseif tab == "Players" then
		local d = View.playerDetail(dex, value)
		return d and F.playerDetailLines(d, nil, RAID_CLASS_COLORS)
	elseif tab == "Raids" then
		local d = View.raidDetail(dex, value)
		return d and F.mobDetailLines(d)
	end
	return nil
end

local function closeDetail(instant)
	state.detail = nil
	if pane then
		pane:close(instant)
	end
end

local function openDetail(value)
	local lines = detailLines(state.tab, value)
	if not lines then
		return
	end
	state.detail = { tab = state.tab, value = value }
	pane:open(lines)
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
		UI.backdrop(button, on and DIVIDER or TAB_BG, DIVIDER)
		UI.textColor(button.label, on and C.WHITE or C.TEXT)
	end
end

local function drawLists(dex, keepLeft, keepRight)
	local View, tab = ns.View, state.tab
	local leftRows, rightRows
	if tab == "Mobs" then
		local places = View.places(dex)
		local place = F.pick(places, "place", state.sel.Mobs)
		state.sel.Mobs = place
		leftRows = F.placeRows(places, place)
		rightRows = place and F.mobRows(View.mobsAt(dex, place, other())) or { F.note("No souls caught yet.") }
	elseif tab == "Players" then
		local classes = View.classes(dex)
		local class = F.pick(classes, "class", state.sel.Players)
		state.sel.Players = class
		leftRows = F.classRows(classes, class, RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE)
		rightRows = class and F.playerRows(View.playersOf(dex, class, other())) or { F.note("No player souls yet.") }
	else
		local raids = View.raids(dex)
		local id = F.pick(raids, "instanceID", state.sel.Raids)
		state.sel.Raids = id
		leftRows = F.raidRows(raids, id)
		rightRows = id and F.raidMobRows(View.raidMobs(dex, id, other())) or { F.note("No raid data.") }
	end
	leftList:set(leftRows, selectLeft, keepLeft)
	rightList:set(rightRows, openDetail, keepRight)
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
		left = "Soul-Dex \194\183 Viewing " .. state.owner
		titleLeft:SetPoint("LEFT", myDexButton, "RIGHT", 5, 0)
	else
		titleLeft:SetPoint("LEFT", 2, 0)
	end
	titleLeft:SetPoint("RIGHT", titleRight, "LEFT", -6, 0)
	setShown(myDexButton, state.owner ~= nil)
	titleLeft:SetText(left)
	titleRight:SetText(right)
	styleTabs()

	local collection = tab == "Mobs" or tab == "Players" or tab == "Raids"
	leftList:show(collection)
	rightList:show(collection)
	fullList:show(tab == "Milestones")
	setShown(divider, tab ~= "Milestones")
	setShown(friendsBox, tab == "Friends")

	if collection then
		drawLists(dex, keepLeft, keepRight)
	elseif tab == "Milestones" then
		fullList:set(F.milestoneRows(ns.Milestones.list(dex)), nil, keepRight)
	else
		drawFriends()
	end

	local detail = state.detail
	if detail then
		local lines = detail.tab == tab and detailLines(tab, detail.value)
		if lines then
			pane:setLines(lines, true)
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

local function placeWindow()
	local w = ns.db and ns.db.window or {}
	frame:ClearAllPoints()
	if w.point then
		frame:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x or 0, w.y or 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	end
end

local function textButton(parent, text, size)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.label:SetPoint("CENTER")
	button.label:SetText(text)
	UI.textColor(button.label, C.TITLE)
	button:SetScript("OnEnter", function(self)
		UI.textColor(self.label, C.WHITE)
	end)
	button:SetScript("OnLeave", function(self)
		UI.textColor(self.label, C.TITLE)
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
	UI.fill(glow, C.WHITE, 0.2)
	gear:SetScript("OnClick", function()
		if ns.Options then
			ns.Options.toggle()
		end
	end)

	titleRight = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	titleRight:SetPoint("RIGHT", gear, "LEFT", -6, 0)
	UI.textColor(titleRight, C.TITLE)
	-- "« My dex": shown while browsing a friend's dex (draw anchors the title after it).
	myDexButton = CreateFrame("Button", nil, bar, "BackdropTemplate")
	myDexButton:SetSize(56, 14)
	myDexButton:SetPoint("LEFT", 0, 0)
	UI.backdrop(myDexButton, BACK_BG, BACK_BORDER)
	myDexButton.label = myDexButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	myDexButton.label:SetPoint("CENTER", 0, 0)
	myDexButton.label:SetText("\194\171 My dex")
	UI.textColor(myDexButton.label, C.TITLE)
	myDexButton:SetScript("OnEnter", function(self)
		UI.backdrop(self, BACK_HOVER, BACK_BORDER)
		UI.textColor(self.label, C.WHITE)
	end)
	myDexButton:SetScript("OnLeave", function(self)
		UI.backdrop(self, BACK_BG, BACK_BORDER)
		UI.textColor(self.label, C.TITLE)
	end)
	myDexButton:SetScript("OnClick", function()
		UI.showDex(nil, nil)
	end)
	myDexButton:Hide()

	titleLeft = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleLeft:SetPoint("LEFT", 2, 0)
	titleLeft:SetPoint("RIGHT", titleRight, "LEFT", -6, 0)
	titleLeft:SetJustifyH("LEFT")
	titleLeft:SetWordWrap(false)
	UI.textColor(titleLeft, C.TITLE)

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	UI.fill(rule, DIVIDER)
end

local function buildBody()
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_H + 2))
	body:SetSize(BODY_W, BODY_H)
	if body.SetClipsChildren then
		body:SetClipsChildren(true) -- the detail pane slides in from outside
	end

	leftList = UI.newList(body, LEFT_W, BODY_H, LEFT_ROW_H, false)
	leftList.frame:SetPoint("TOPLEFT", 0, 0)
	rightList = UI.newList(body, BODY_W - RIGHT_X, BODY_H, RIGHT_ROW_H, true)
	rightList.frame:SetPoint("TOPLEFT", RIGHT_X, 0)
	fullList = UI.newList(body, BODY_W, BODY_H, RIGHT_ROW_H, true)
	fullList.frame:SetPoint("TOPLEFT", 0, 0)

	divider = body:CreateTexture(nil, "ARTWORK")
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", LEFT_W + 2, 0)
	divider:SetPoint("BOTTOMLEFT", LEFT_W + 2, 0)
	UI.fill(divider, DIVIDER)

	friendsBox = CreateFrame("Frame", nil, body)
	friendsBox:SetAllPoints()
	friendsLeft = CreateFrame("Frame", nil, friendsBox)
	friendsLeft:SetPoint("TOPLEFT", 0, 0)
	friendsLeft:SetSize(LEFT_W, BODY_H)
	friendsRight = CreateFrame("Frame", nil, friendsBox)
	friendsRight:SetPoint("TOPLEFT", RIGHT_X, 0)
	friendsRight:SetSize(BODY_W - RIGHT_X, BODY_H)
	friendsNote = friendsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	friendsNote:SetPoint("CENTER")
	friendsNote:SetText("Friends arrive soon")
	UI.textColor(friendsNote, C.MUTED)

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
	UI.backdrop(frame, WINDOW_BG, BORDER, 0.97)
	placeWindow()
	table.insert(UISpecialFrames, "SoulDexFrame") -- Escape closes it
	buildTitle()
	buildBody()
	buildTabs()
	-- Closing the window while browsing a friend: it reopens on your own dex.
	frame:SetScript("OnHide", function()
		closeDetail(true)
		state.dex, state.owner, state.compare = nil, nil, nil
	end)
	frame:Hide()
end

-- Public API --------------------------------------------------------------------------

local function ready()
	if ns.db and dexNow() then
		return true
	end
	ns.Print("Soul-Dex is still loading.")
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
-- browsing that friend's dex and rows compare against setCompare's dex.
function UI.showDex(dex, ownerName)
	state.dex = dex
	state.owner = ownerName
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

function UI.currentTab()
	return state.tab
end

function UI.isBrowsing()
	return state.owner ~= nil
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
