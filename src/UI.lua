-- The dex window: title bar with the rank chip and progress line, six tabs, two scrolling
-- lists (or one full-width list for Milestones, or the rank crest, tiles and records of
-- the Me tab) and the slide-in trophy card (src/UIDetail.lua). Game code; the row and
-- card contents come from the pure ns.View and ns.UIFormat.
local _, ns = ...

local UI = {}
ns.UI = UI

local F = ns.UIFormat
local C = F.COLORS

local WIDTH, HEIGHT = 380, 300
local PAD = 7
local TITLE_H, TAB_H = 20, 18
local TOOLBAR_H = 20 -- the search box and the Sort and Show buttons, under the title (spec 5.9)
local LEFT_W = 124
local BODY_W = WIDTH - 2 * PAD
local BODY_H = HEIGHT - 2 * PAD - TITLE_H - TAB_H - 10 - TOOLBAR_H
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

local SORT_W, SHOW_W, TOOL_GAP = 98, 104, 3
local BANNER_H = 14 -- the window grows by this while browsing, for the banner over the tabs
local CHIP_H = 18 -- and by this, for the compare filter's row over the lists (spec 5.9)
local BODY_Y = PAD + TITLE_H + 6 + TOOLBAR_H -- the body's top edge under the window's
local VIEW_W = 48-- a Me tab view button (All, Mobs, PvP)
local HANDLE_W = 7 -- the invisible grip over the column divider

-- A search result's kind and the tab whose card it opens.
local KIND_TAB = { mob = "Mobs", player = "Players", raid = "Raids" }

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
	detail = nil, -- { tab, value, search } of the open detail pane (search: the search it came from)
	friendsBuilder = nil,
	search = "", -- the search box's text
	filter = nil, -- the Show choice (nil = the first); not saved
}

local frame, titleLeft, titleRight, divider, myDexButton, banner, bodyFrame, chipBar
local searchBox, searchHint, sortButton, showButton
local splitHandle, splitDrag
local appliedSplit = LEFT_W -- the left list's width as it is drawn now
local chip, rankFill, emblem
local leftList, rightList, fullList, pane
local meBox, crest, tiles, recordList
local friendsBox, friendsLeft, friendsRight, friendsNote
local tabButtons = {}
local viewButtons = {} -- the Me tab's All, Mobs and PvP buttons, in the toolbar
local chips = {} -- the compare filter's buttons while browsing, in chipBar

-- A view button as it rests: the chosen one is lit like the chosen tab.
-- A compare chip: lit when chosen; a side's chip keeps that side's colour.
local function paintChip(button)
	UI.backdrop(button, button.on and "DIVIDER" or "TAB_BG", button.on and "BORDER" or "BUTTON_EDGE")
	UI.textColor(button.label, button.color or (button.on and "WHITE" or "TITLE"))
end

local function paintViewButton(button)
	UI.backdrop(button, button.on and "DIVIDER" or "TAB_BG", button.on and "BORDER" or "BUTTON_EDGE")
	UI.textColor(button.label, button.on and "WHITE" or "TITLE")
end

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

local function isCollection(tab)
	return tab == "Mobs" or tab == "Players" or tab == "Raids"
end

-- Search, sort and split state ------------------------------------------------------

-- The search being shown (trimmed), or nil while fewer than View.FIND_MIN letters are typed.
local function activeSearch()
	local text = state.search:match("^%s*(.-)%s*$")
	if #text >= ns.View.FIND_MIN then
		return text
	end
	return nil
end

-- Ends the search: the box is emptied (its OnTextChanged then sees nothing new).
local function clearSearch()
	state.search = ""
	if searchBox then
		searchBox:SetText("")
		searchBox:ClearFocus()
	end
end

-- A click elsewhere in the window: the search box lets go of the keyboard (its text stays).
local function unfocusSearch()
	if searchBox then
		searchBox:ClearFocus()
	end
end

-- The saved Sort choice of a tab, read through Browse.valid so junk is harmless.
local function sortFor(tab, browsing)
	local w = ns.db and ns.db.window
	local saved = w and type(w.sort) == "table" and w.sort[tab] or nil
	return ns.Browse.valid(ns.Browse.sorts(tab, browsing), saved)
end

-- The Me tab's saved view (spec 5.8), read through View.meView so junk is harmless.
local function meViewNow()
	local w = ns.db and ns.db.window
	return ns.View.meView(w and w.meView)
end

-- The left list's width on Mobs, Players and Raids: the one being dragged, else the saved one.
local function splitNow()
	if splitDrag then
		return splitDrag.split
	end
	local w = ns.db and ns.db.window
	return ns.Settings.split(w and w.split)
end

local function applySplit(width)
	if width == appliedSplit or not leftList then
		return
	end
	appliedSplit = width
	leftList:setWidth(width)
	rightList:setWidth(BODY_W - (width + 5))
	rightList.frame:ClearAllPoints()
	rightList.frame:SetPoint("TOPLEFT", width + 5, 0)
end

-- The divider and the split's grip at the left list's edge.
local function placeDivider(split)
	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", split + 2, 0)
	divider:SetPoint("BOTTOMLEFT", split + 2, 0)
	splitHandle:ClearAllPoints()
	splitHandle:SetPoint("TOPLEFT", split + 2 - math.floor(HANDLE_W / 2), 0)
	splitHandle:SetPoint("BOTTOMLEFT", split + 2 - math.floor(HANDLE_W / 2), 0)
end

-- Drawing ---------------------------------------------------------------------------

-- fromSearch: a search result's card; it and the All row's show a mob over every zone.
local function detailCard(tab, value, fromSearch)
	local dex, View = dexNow(), ns.View
	local card
	if tab == "Mobs" then
		local place = state.sel.Mobs
		local whole = fromSearch or place == ns.Browse.ALL
		local d = View.mobDetail(dex, value, not whole and place or nil, whole)
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

-- value: a row's value; a search result's is { kind, id } and opens the card of its kind.
local function openDetail(value)
	unfocusSearch()
	local tab, search = state.tab, nil
	if type(value) == "table" then
		tab, search = KIND_TAB[value.kind], activeSearch()
		value = value.id
		if not tab or not search then
			return
		end
	end
	local card = detailCard(tab, value, search ~= nil)
	if not card then
		return
	end
	state.detail = { tab = tab, value = value, search = search }
	pane:open(card)
end

local draw

local function selectLeft(value)
	state.sel[state.tab] = value
	clearSearch()
	closeDetail(true)
	draw("select")
end

-- The tabs, and what says whose dex is on screen: while browsing a friend the window's
-- edge and the tabs are blue and a banner over the tabs names the friend, in a window
-- made taller by the banner's height (spec 5.7) and by the compare filter's row, which
-- pushes the body down (spec 5.9).
local function styleTabs()
	local browsing = state.owner ~= nil
	for _, button in ipairs(tabButtons) do
		local on = button.tab == state.tab
		local edge = on and "BORDER" or "DIVIDER"
		if browsing then
			edge = on and F.BROWSE or F.BROWSE_DIM
		end
		UI.backdrop(button, on and "DIVIDER" or "TAB_BG", edge)
		UI.textColor(button.label, on and "WHITE" or "TEXT")
		UI.fill(button.underline, browsing and F.BROWSE or "ACCENT")
		setShown(button.underline, on)
	end
	frame:SetHeight(browsing and HEIGHT + BANNER_H + CHIP_H or HEIGHT)
	bodyFrame:ClearAllPoints()
	bodyFrame:SetPoint("TOPLEFT", PAD, -(BODY_Y + (browsing and CHIP_H or 0)))
	UI.backdrop(frame, "BG", browsing and F.BROWSE or "BORDER", 0.97)
	setShown(banner, browsing)
	if browsing then
		banner:SetText(F.browseBanner(state.owner))
	end
end

-- The left-list selection on Mobs and Players: All (a fresh window, or a row that went
-- away) or a row that is still listed; nil when nothing is listed.
local function pickOrAll(rows, field, current)
	if F.pick(rows, field, nil) == nil then
		return nil
	end
	if current ~= nil and F.pick(rows, field, current) == current then
		return current
	end
	return ns.Browse.ALL
end

-- The compare filter's chips (browsing, with a dex to compare with, outside a search):
-- each with its count, the chosen one lit. counts nil hides them.
local function drawChips(counts, filter)
	setShown(chipBar, counts ~= nil)
	if not counts then
		return
	end
	local x = 0
	for i, item in ipairs(F.compareChips(counts)) do
		local button = chips[i]
		button.id, button.color, button.on = item.id, item.color or false, item.id == filter
		button.label:SetText(item.text)
		local width = math.ceil(button.label:GetStringWidth() or 0) + 16
		button:SetWidth(width)
		button:ClearAllPoints()
		button:SetPoint("LEFT", x, 0)
		x = x + width + TOOL_GAP
		paintChip(button)
	end
end

local function drawLists(dex, keepLeft, keepRight)
	local View, Browse, tab = ns.View, ns.Browse, state.tab
	local browsing, them = state.owner ~= nil, other()
	local comparing = browsing and them ~= nil
	local filter = Browse.valid(Browse.filters(tab, browsing), state.filter)
	if browsing and not comparing then
		filter = "all" -- nothing to compare with yet
	end
	local sort = sortFor(tab, browsing)
	-- During a search the right list holds its results, so the usual rows are not built.
	local search = activeSearch()
	-- What an emptied list says: under a compare filter, in that filter's words. all nil
	-- (Mobs and Players): always; a raid's list: only when the filter emptied it.
	local function filtered(rows, all)
		if #rows == 0 and (all == nil or #all > 0) then
			return { comparing and F.compareEmpty(filter) or F.emptyNote() }
		end
		return rows
	end
	-- The left list follows the compare filter: the zones or classes of that side's souls.
	local shown = Browse.subset(dex, them, tab, filter)
	local leftRows, rightRows
	if tab == "Mobs" then
		local places = View.places(shown)
		local place = pickOrAll(places, "place", state.sel.Mobs)
		state.sel.Mobs = place
		leftRows = F.placeRows(places, place, Browse.size(shown, "Mobs"))
		if not place then
			rightRows = { comparing and F.compareEmpty(filter) or F.note("No souls claimed yet. Go drain something.") }
		elseif not search then
			rightRows = filtered(F.mobRows(Browse.apply(Browse.mobs(dex, place, them), filter, sort)))
		end
	elseif tab == "Players" then
		local classes = View.classes(shown)
		local class = pickOrAll(classes, "class", state.sel.Players)
		state.sel.Players = class
		leftRows = F.classRows(classes, class, RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE,
			Browse.size(shown, "Players"))
		if not class then
			rightRows = { comparing and F.compareEmpty(filter) or F.note("No player souls yet.") }
		elseif not search then
			rightRows = filtered(F.playerRows(Browse.apply(Browse.players(dex, class, them), filter, sort)))
		end
	else
		local raids = View.raids(dex)
		-- Selected by raid key: a TBD raid has no instance id until a soul is claimed there.
		local key = F.pick(raids, "key", state.sel.Raids)
		state.sel.Raids = key
		leftRows = F.raidRows(raids, key)
		local raid = key and ns.Raids.byKey(key)
		if not raid then
			rightRows = { F.note("No raid data.") }
		elseif not search then
			local all = View.raidMobs(dex, raid.instanceID, them)
			rightRows = filtered(F.raidMobRows(Browse.apply(all, filter, nil)), all)
			if raid.tbd then
				table.insert(rightRows, 1, F.tbdNote(raid))
			end
		end
	end
	if search then
		-- Every soul of the dex on screen whose name holds the text; not compare-coloured.
		rightRows = F.findRows(View.find(dex, search), LOCALIZED_CLASS_NAMES_MALE)
		if #rightRows == 0 then
			rightRows = { F.emptyNote(search) }
		end
	end
	drawChips(comparing and not search and Browse.counts(dex, them, tab) or nil, filter)
	leftList:set(leftRows, selectLeft, keepLeft)
	rightList:set(rightRows, openDetail, keepRight)
end

-- The Me tab: the rank crest on the left, six tiles and the records list on the right.
-- Browsing a friend shows their rank and numbers, and no place among friends.
local function drawMe(dex, keepScroll)
	local card
	if state.owner then
		card = ns.View.meCard(dex, false, nil, 0, meViewNow())
	else
		card = ns.View.meCard(dex, ns.db and ns.db.friends, ns.Net and ns.Net.me(dex), time(), meViewNow())
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
	for _, line in ipairs(F.recordLines(card.records, time(), nil, RAID_CLASS_COLORS, LOCALIZED_CLASS_NAMES_MALE)) do
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

-- The toolbar. On Mobs, Players and Raids: the search box with its hint, and Sort and Show
-- with this tab's choices, each hidden when the tab has none and during a search; the
-- search box fills what they leave. On Me: the three view buttons. Empty on the others.
local function drawToolbar()
	local Browse, tab, browsing = ns.Browse, state.tab, state.owner ~= nil
	local searching = activeSearch() ~= nil
	setShown(searchBox, isCollection(tab))
	local view = meViewNow()
	for _, button in ipairs(viewButtons) do
		setShown(button, tab == "Me")
		button.on = button.view == view
		paintViewButton(button)
	end
	local filters = Browse.filters(tab, browsing)
	local showSort = #Browse.sorts(tab, browsing) > 0 and not searching
	local showFilter = #filters > 0 and not searching and not browsing -- browsing: the chips
	setShown(searchHint, state.search == "")
	setShown(sortButton, showSort)
	setShown(showButton, showFilter)
	if showSort then
		sortButton.label:SetText(F.toolLabel("sort", sortFor(tab, browsing), browsing))
	end
	if showFilter then
		showButton.label:SetText(F.toolLabel("show", Browse.valid(filters, state.filter), browsing))
	end
	-- Right to left: Show (anchored to the right edge), Sort, then the search box.
	local edge = showFilter and showButton or nil
	sortButton:ClearAllPoints()
	if edge then
		sortButton:SetPoint("RIGHT", edge, "LEFT", -TOOL_GAP, 0)
	else
		sortButton:SetPoint("RIGHT", 0, 0)
	end
	if showSort then
		edge = sortButton
	end
	searchBox:ClearAllPoints()
	searchBox:SetPoint("TOPLEFT", 0, 0)
	if edge then
		searchBox:SetPoint("BOTTOMRIGHT", edge, "BOTTOMLEFT", -TOOL_GAP, 0)
	else
		searchBox:SetPoint("BOTTOMRIGHT", 0, 0)
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

	local collection = isCollection(tab)
	drawToolbar()
	leftList:show(collection)
	rightList:show(collection)
	fullList:show(tab == "Milestones")
	setShown(meBox, tab == "Me")
	setShown(divider, tab ~= "Milestones")
	local split = LEFT_W
	if collection then
		split = splitNow()
		applySplit(split)
	elseif tab == "Friends" then
		split = FRIENDS_LEFT_W
	end
	setShown(splitHandle, collection)
	placeDivider(split)
	setShown(friendsBox, tab == "Friends")

	setShown(chipBar, false) -- drawLists shows it when there is something to compare
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
		-- A search result's card stays while that search does; any other, while its tab is on.
		local keep
		if detail.search then
			keep = detail.search == activeSearch()
		else
			keep = detail.tab == tab
		end
		local card = keep and detailCard(detail.tab, detail.value, detail.search ~= nil)
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

-- The toolbar ------------------------------------------------------------------------

-- What the search box holds, or "" for anything that is not plain readable text.
local function typedSearch(box)
	local text = box:GetText()
	if ns.Capture and ns.Capture.plainString(text) then
		return text
	end
	return ""
end

-- A click on Sort or Show steps forward through the tab's choices, a right-click back.
local function stepSort(back)
	unfocusSearch()
	local tab, w = state.tab, ns.db and ns.db.window
	local list = ns.Browse.sorts(tab, state.owner ~= nil)
	if #list == 0 or not w then
		return
	end
	if type(w.sort) ~= "table" then
		w.sort = {}
	end
	w.sort[tab] = ns.Browse.step(list, w.sort[tab], back)
	draw("select")
end

-- The open card closes: its row may be one the new choice leaves out.
local function stepFilter(back)
	unfocusSearch()
	local list = ns.Browse.filters(state.tab, state.owner ~= nil)
	if #list == 0 then
		return
	end
	state.filter = ns.Browse.step(list, state.filter, back)
	closeDetail(true)
	draw("select")
end

local function buildToolbar()
	local bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", PAD, -(PAD + TITLE_H + 5))
	bar:SetSize(BODY_W, 16)

	searchBox = CreateFrame("EditBox", nil, bar, "BackdropTemplate")
	searchBox:SetAutoFocus(false)
	searchBox:SetMaxLetters(40)
	searchBox:SetFontObject(GameFontHighlightSmall)
	searchBox:SetTextInsets(4, 4, 0, 0)
	UI.backdrop(searchBox, "TAB_BG", "BUTTON_EDGE")
	searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	searchHint:SetPoint("LEFT", 4, 0)
	searchHint:SetText("Search all souls")
	UI.textColor(searchHint, "MUTED")
	-- UI.setSearch keeps the box in step with SetText, which runs this again: only a change
	-- searches.
	searchBox:SetScript("OnTextChanged", function(self)
		local text = typedSearch(self)
		if text ~= state.search then
			UI.setSearch(text)
		end
	end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
		if state.search ~= "" then
			UI.setSearch("")
		end
	end)
	searchBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)

	showButton = UI.button(bar, "Show:", SHOW_W, 16, function(_, button)
		stepFilter(button == "RightButton")
	end)
	showButton:SetPoint("RIGHT", 0, 0)
	sortButton = UI.button(bar, "Sort:", SORT_W, 16, function(_, button)
		stepSort(button == "RightButton")
	end)
	for _, button in ipairs({ showButton, sortButton }) do
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	end

	-- The Me tab's views, where the search box is on the collection tabs.
	for i, id in ipairs(ns.View.ME_VIEWS) do
		local button = UI.button(bar, ns.View.ME_LABELS[id], VIEW_W, 16, function()
			UI.setMeView(id)
		end)
		button.view = id
		button:SetPoint("LEFT", (i - 1) * (VIEW_W + TOOL_GAP), 0)
		button:SetScript("OnLeave", paintViewButton)
		button:Hide()
		viewButtons[i] = button
	end
end

-- The column split: an invisible grip over the divider. Dragging it widens the left list
-- (Settings.split's limits); the width is saved when the mouse is let go. While dragging
-- only the lists and the divider move; the rows are drawn again once, when it ends.
local function buildSplitHandle(body)
	splitHandle = CreateFrame("Button", nil, body)
	splitHandle:SetWidth(HANDLE_W)
	splitHandle:SetFrameLevel(body:GetFrameLevel() + 10) -- above the lists, under the detail pane
	splitHandle:EnableMouse(true)
	local function follow()
		local x = GetCursorPosition()
		local width = ns.Settings.split(splitDrag.start + (x - splitDrag.x) / splitDrag.eff)
		if width ~= splitDrag.split then
			splitDrag.split = width
			applySplit(width)
			placeDivider(width)
		end
	end
	local function stop()
		if not splitDrag then
			return
		end
		splitHandle:SetScript("OnUpdate", nil)
		local width = splitDrag.split
		splitDrag = nil
		local w = ns.db and ns.db.window
		if w then
			w.split = width
		end
		if frame:IsShown() then
			draw("refresh")
		end
	end
	splitHandle:SetScript("OnMouseDown", function()
		unfocusSearch()
		local x = GetCursorPosition()
		local start = splitNow()
		splitDrag = { x = x, start = start, split = start, eff = frame:GetEffectiveScale() or 1 }
		splitHandle:SetScript("OnUpdate", follow)
	end)
	splitHandle:SetScript("OnMouseUp", stop)
	splitHandle:SetScript("OnHide", stop) -- the window closed mid-drag
	splitHandle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize columns")
		GameTooltip:Show()
	end)
	splitHandle:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
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
	bodyFrame = body
	body:SetPoint("TOPLEFT", PAD, -BODY_Y)
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
	buildSplitHandle(body)

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

	-- The compare filter's chips, in the row the body leaves free while browsing.
	chipBar = CreateFrame("Frame", nil, frame)
	chipBar:SetPoint("TOPLEFT", PAD, -BODY_Y)
	chipBar:SetSize(BODY_W, CHIP_H - 2)
	for i = 1, 4 do
		local button = UI.button(chipBar, "", 40, CHIP_H - 2, function(self)
			UI.setFilter(self.id)
		end)
		button:SetScript("OnLeave", paintChip)
		chips[i] = button
	end
	chipBar:Hide()
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
	-- The browsing banner, in the room the taller window leaves over the tabs.
	banner = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	banner:SetPoint("BOTTOMLEFT", PAD + 2, PAD + TAB_H + 1)
	banner:SetPoint("RIGHT", -PAD, 0)
	banner:SetJustifyH("LEFT")
	banner:SetWordWrap(false)
	UI.textColor(banner, F.BROWSE)
	banner:Hide()
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
	buildToolbar()
	buildBody()
	buildTabs()
	-- Closing the window while browsing a friend: it reopens on your own dex. The search
	-- and the Show choice end with it.
	frame:SetScript("OnHide", function()
		closeDetail(true)
		clearSearch()
		state.filter = nil
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
-- A newer copy of the friend's dex already on screen keeps the search, the Show choice
-- and an open card that is still in it.
function UI.showDex(dex, ownerName, savedAt)
	local again = frame ~= nil and frame:IsShown() and ownerName ~= nil and ownerName == state.owner
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
	if again then
		draw("refresh")
		return
	end
	closeDetail(true)
	clearSearch()
	state.filter = nil
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
	w.point, w.relPoint, w.x, w.y, w.scale, w.split = nil, nil, nil, nil, nil, nil
	if frame then
		placeWindow()
		applySplit(ns.Settings.SPLIT_DEFAULT)
		UI.refresh()
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
	clearSearch()
	closeDetail(true)
	if frame and frame:IsShown() then
		draw("tab")
	end
end

-- Sets the search text as if it were typed: with View.FIND_MIN letters or more, the right
-- list shows what matches over the whole dex on screen, from Mobs when the tab has no lists.
function UI.setSearch(text)
	state.search = type(text) == "string" and text or ""
	if searchBox and typedSearch(searchBox) ~= state.search then
		searchBox:SetText(state.search)
	end
	closeDetail(true)
	-- Typing keeps the left list where it is; a search that moves to Mobs starts it afresh.
	local action = "select"
	if activeSearch() and not isCollection(state.tab) then
		state.tab = "Mobs"
		action = "tab"
		if ns.db and ns.db.window then
			ns.db.window.tab = "Mobs"
		end
	end
	if frame and frame:IsShown() then
		draw(action)
	end
end

function UI.search()
	return state.search
end

-- Picks the Show choice (your own Mobs tab) or the compare filter (browsing): an id of
-- Browse.filters for the tab on screen; anything else is the first. Not saved. The open
-- card closes: its row may be one the new choice leaves out.
function UI.setFilter(id)
	unfocusSearch()
	state.filter = ns.Browse.valid(ns.Browse.filters(state.tab, state.owner ~= nil), id)
	closeDetail(true)
	if frame and frame:IsShown() then
		draw("select")
	end
end

-- Picks the Me tab's view (one of View.ME_VIEWS; anything else is "all") and saves it.
function UI.setMeView(view)
	if ns.db and ns.db.window then
		ns.db.window.meView = ns.View.meView(view)
	end
	if frame and frame:IsShown() then
		draw("select")
	end
end

function UI.meView()
	return meViewNow()
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
