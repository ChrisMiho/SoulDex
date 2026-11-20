-- Smoke test: the window code loads and runs against minimal frame stubs.
-- Every frame method is a no-op unless listed below.
describe("UI", function()
	local STUBBED = {
		"CreateFrame", "UIParent", "UISpecialFrames", "GameFontNormal", "GameFontHighlightSmall",
		"RAID_CLASS_COLORS", "SoulDexFrame", "SoulDexOptionsFrame", "date", "UnitName", "time", "LibStub",
		"Settings", "SoulDexSettingsPanel",
		"StaticPopupDialogs", "StaticPopup_Show", "IsInGuild", "GetCursorPosition",
	}
	local saved, created, ns

	local Stub = {}
	local methods = {
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetScript = function(self, name, fn) self.scripts[name] = fn end,
		SetText = function(self, text) self.text = text end,
		GetText = function(self) return self.text end,
		SetSize = function(self, w, h) self.w, self.h = w, h end,
		SetWidth = function(self, w) self.w = w end,
		SetScale = function(self, scale) self.scale = scale end,
		SetAlpha = function(self, alpha) self.alpha = alpha end,
		SetPoint = function(self, ...) self.point = { ... } end,
		SetChecked = function(self, value) self.checked = value end,
		GetChecked = function(self) return self.checked end,
		GetStringWidth = function() return 30 end,
		GetStringHeight = function() return 24 end,
		GetFrameLevel = function() return 1 end,
		GetPoint = function() return "TOPLEFT", nil, "BOTTOMLEFT", 100, 500 end,
		SetVerticalScroll = function(self, y) self.vscroll = y end,
	}
	Stub.__index = function(_, key)
		return methods[key] or function() end
	end
	local function stub(kind)
		local s = setmetatable({ kind = kind, shown = true, scripts = {} }, Stub)
		s.CreateTexture = function() return stub("Texture") end
		s.CreateFontString = function() return stub("FontString") end
		return s
	end

	local function find(kind, pred)
		for _, f in ipairs(created) do
			if f.kind == kind and pred(f) then
				return f
			end
		end
	end

	before_each(function()
		saved = {}
		for _, name in ipairs(STUBBED) do
			saved[name] = _G[name]
		end
		created = {}
		_G.CreateFrame = function(kind, name)
			local f = stub(kind)
			created[#created + 1] = f
			if name then
				_G[name] = f
			end
			return f
		end
		_G.UIParent = stub("Frame")
		_G.UISpecialFrames = {}
		_G.GameFontNormal, _G.GameFontHighlightSmall = {}, {}
		_G.RAID_CLASS_COLORS = { ROGUE = { r = 1, g = 0.96, b = 0.41 } }
		_G.date = os.date
		_G.time = function() return 5000 end

		ns = {
			RaidData = {
				{ key = "BD", name = "The Barrow Deeps", bossCount = 8, tbd = true, mobs = {} },
				{
					key = "MC",
					name = "Molten Core",
					instanceID = 409,
					mobs = { { id = 12118, name = "Lucifron", boss = true }, { id = 11671, name = "Core Hound" } },
				},
			},
			Print = function() end,
		}
		for _, file in ipairs({
			"Themes", "Settings", "Raids", "Points", "Rarity", "Ranks", "Flavour", "Dex", "Milestones", "View", "Browse",
			"UIFormat", "UIList", "UI", "UIDetail", "Options",
		}) do
			LoadAddonFile("src/" .. file .. ".lua", ns)
		end
	end)

	after_each(function()
		for _, name in ipairs(STUBBED) do
			_G[name] = saved[name]
		end
	end)

	local function loadDb()
		local db = { settings = ns.Settings.normalise(nil), window = { tab = "Players" } }
		ns.db = db
		ns.dex = ns.Dex.new(db)
		for _, fn in ipairs(ns.onLoaded) do
			fn(db)
		end
		local ctx = { time = 1000, myLevel = 20, zone = "Elwynn Forest", group = "Eastern Kingdoms", x = 1, y = 2 }
		ns.dex:recordMob({ name = "Hogger", level = 11, classification = "elite" }, ctx)
		ns.dex:recordPlayer({ name = "Stab", realm = "R", level = 38, class = "ROGUE", race = "Orc" }, ctx)
		ns.dex:recordRaid({ name = "Lucifron", classification = "elite" }, ctx, 409, 12118)
		return db
	end

	it("loads and exposes its API", function()
		for _, fn in ipairs({ "toggle", "showDex", "refresh", "setFriendsTab", "setCompare", "selectTab" }) do
			assert.equal("function", type(ns.UI[fn]), fn)
		end
		assert.equal("function", type(ns.Options.toggle))
		assert.equal("function", type(ns.UIList.new))
		-- progress bar fills: nothing for no or zero progress, never wider than the row
		assert.is_nil(ns.UIList.barWidth(nil, 100))
		assert.is_nil(ns.UIList.barWidth(0, 100))
		assert.equal(1, ns.UIList.barWidth(0.001, 100))
		assert.equal(50, ns.UIList.barWidth(0.5, 100))
		assert.equal(100, ns.UIList.barWidth(3, 100))
		assert.equal(2, #ns.onLoaded) -- the window's and the options page's
		assert.equal(1, #ns.onCatch)
	end)

	it("does nothing but print before the saved variables load", function()
		local printed
		ns.Print = function(text) printed = text end
		ns.UI.toggle()
		assert.is_truthy(printed)
		assert.is_nil(_G.SoulDexFrame)
	end)

	it("opens, draws every tab and detail, and closes", function()
		local db = loadDb()
		ns.UI.toggle()
		local frame = _G.SoulDexFrame
		assert.is_true(frame.shown)
		assert.same({ "SoulDexFrame" }, _G.UISpecialFrames)

		ns.UI.openDetail("Stab-R") -- remembered tab: Players
		for _, tab in ipairs({ "Me", "Mobs", "Raids", "Milestones", "Friends", "Players" }) do
			ns.UI.selectTab(tab)
			assert.equal(tab, db.window.tab)
		end
		ns.UI.selectTab("Mobs")
		ns.UI.openDetail("Hogger")
		ns.UI.selectTab("Raids")
		ns.UI.openDetail(12118)
		ns.onCatch[1]({}, {})

		ns.UI.toggle()
		assert.is_false(frame.shown)
	end)

	it("selects a TBD raid with no instance id and shows its note; other raids still list", function()
		loadDb()
		local F, View = ns.UIFormat, ns.View
		local selected, noted, notes, listedFor = nil, nil, {}, nil
		local raidRows, tbdNote, note, raidMobs = F.raidRows, F.tbdNote, F.note, View.raidMobs
		F.raidRows = function(rows, sel)
			selected = sel
			return raidRows(rows, sel)
		end
		F.tbdNote = function(raid)
			noted = raid
			return tbdNote(raid)
		end
		F.note = function(text)
			notes[text] = true
			return note(text)
		end
		View.raidMobs = function(dex, instanceID, other)
			listedFor = instanceID
			return raidMobs(dex, instanceID, other)
		end
		ns.UI.toggle()
		ns.UI.selectTab("Raids")
		assert.equal("BD", selected)
		assert.equal("BD", noted.key)
		assert.is_nil(notes["No raid data."])
		assert.is_truthy(find("Button", function(f) return f.value == "BD" end))

		noted = nil
		local row = find("Button", function(f) return f.value == "MC" end)
		row.scripts.OnClick(row)
		assert.equal("MC", selected)
		assert.equal(409, listedFor)
		assert.is_nil(noted)
		ns.UI.openDetail(12118)
	end)

	it("draws the Me tab on an empty dex and on a populated one", function()
		local db = loadDb()
		ns.dex = ns.Dex.new({})
		ns.UI.toggle()
		ns.UI.selectTab("Me")
		assert.equal("Me", db.window.tab)
		local function rowWith(text)
			return find("Button", function(f)
				local left = rawget(f, "left")
				return left and left.text == text
			end)
		end
		local function textShown(text)
			return find("Frame", function(f)
				for _, key in ipairs({ "rank", "place", "label", "value" }) do
					local fs = rawget(f, key)
					if fs and fs.text == text then
						return true
					end
				end
				return false
			end)
		end
		assert.is_truthy(rowWith("RECORDS"))
		assert.is_truthy(rowWith("Most claimed"))
		assert.is_truthy(textShown("Initiate")) -- the crest and the chip
		assert.is_truthy(textShown("RANK 1 OF 8"))
		assert.is_truthy(textShown("SOULS TAKEN")) -- a tile
		assert.is_truthy(textShown("AMONG FRIENDS"))
		assert.is_nil(rowWith("Unknown souls"))
		ns.dex = ns.Dex.new(db)
		ns.dex:recordUnknown({ time = 5, zone = "Elwynn Forest", group = "Eastern Kingdoms" })
		ns.onCatch[1]({}, {})
		assert.is_truthy(rowWith("Unknown souls"))
		assert.is_truthy(rowWith("Zones hunted"))
		ns.UI.showDex(ns.Dex.new({}), "Ann") -- browsing: no error, still on Me
		assert.equal("Me", ns.UI.currentTab())
		assert.is_nil(textShown("AMONG FRIENDS")) -- Ann's dex has no place among your friends
		assert.is_truthy(textShown("ZONES"))
	end)

	it("the Me tab has three views; the choice is saved and shown", function()
		local db = loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Me")
		local function viewButton(text)
			return find("Button", function(f)
				local label = rawget(f, "label")
				return rawget(f, "view") and label and label.text == text
			end)
		end
		local function tileShown(text)
			return find("Frame", function(f)
				local label = rawget(f, "label")
				return f.shown and rawget(f, "value") and label and label.text == text
			end)
		end
		local all, mobs, pvp = viewButton("All"), viewButton("Mobs"), viewButton("PvP")
		assert.is_true(all.shown and mobs.shown and pvp.shown)
		assert.is_true(all.on)
		assert.is_truthy(tileShown("SOULS TAKEN"))

		pvp.scripts.OnClick(pvp)
		assert.equal("pvp", db.window.meView)
		assert.equal("pvp", ns.UI.meView())
		assert.is_true(pvp.on)
		assert.is_falsy(all.on)
		assert.is_truthy(tileShown("PLAYER SOULS"))
		assert.is_nil(tileShown("SOULS TAKEN"))

		mobs.scripts.OnClick(mobs)
		assert.is_truthy(tileShown("MOB SOULS"))
		ns.UI.setMeView("junk")
		assert.equal("all", db.window.meView)

		db.window.meView = 42 -- damaged saved data
		ns.UI.refresh()
		assert.equal("all", ns.UI.meView())

		ns.UI.selectTab("Mobs") -- the view buttons belong to Me only
		assert.is_false(all.shown)
	end)

	it("the search box shows on Mobs, Players and Raids only", function()
		loadDb()
		ns.UI.toggle()
		local box = find("EditBox", function() return true end)
		for tab, shown in pairs({ Me = false, Mobs = true, Players = true, Raids = true, Milestones = false,
			Friends = false }) do
			ns.UI.selectTab(tab)
			assert.equal(shown, box.shown, tab)
		end
	end)

	it("keeps the left list's scroll on selection and both on a catch; a tab switch resets", function()
		local db = loadDb()
		db.window.tab = "Mobs"
		for _, fn in ipairs(ns.onLoaded) do
			fn(db)
		end
		for i = 1, 20 do
			local ctx = { time = 1000, zone = string.format("Zone %02d", i), group = "Kalimdor" }
			ns.dex:recordMob({ name = "Mob " .. i }, ctx)
			ns.dex:recordMob({ name = "Other " .. i }, { time = 1000, zone = "Zone 20", group = "Kalimdor" })
		end
		ns.UI.toggle()
		local scrolls = {}
		for _, f in ipairs(created) do
			if f.kind == "ScrollFrame" then
				scrolls[#scrolls + 1] = f
			end
		end
		local left, right = scrolls[1], scrolls[2]
		left.scripts.OnMouseWheel(left, -3)
		right.scripts.OnMouseWheel(right, -1)
		assert.is_true(left.vscroll > 0)
		local leftScroll = left.vscroll

		local row = find("Button", function(f) return f.value == "Zone 20" end)
		row.scripts.OnClick(row)
		assert.equal(leftScroll, left.vscroll)
		assert.equal(0, right.vscroll)

		right.scripts.OnMouseWheel(right, -1)
		local rightScroll = right.vscroll
		assert.is_true(rightScroll > 0)
		ns.onCatch[1]({}, {})
		assert.equal(leftScroll, left.vscroll)
		assert.equal(rightScroll, right.vscroll)

		ns.UI.selectTab("Players")
		assert.equal(0, left.vscroll)
		assert.equal(0, right.vscroll)
	end)

	it("hands the Friends tab to a registered builder", function()
		loadDb()
		local got
		ns.UI.setFriendsTab(function(left, right) got = { left, right } end)
		ns.UI.toggle()
		ns.UI.selectTab("Friends")
		assert.is_table(got[1])
		assert.is_table(got[2])
	end)

	it("zooms the window by dragging its corner, keeping the top-left corner in place", function()
		local db = loadDb()
		ns.UI.toggle()
		local frame = _G.SoulDexFrame
		frame.scale = 1
		frame.GetScale = function(self) return self.scale end
		frame.GetEffectiveScale = function(self) return self.scale end
		frame.GetLeft = function() return 100 end
		frame.GetTop = function() return 600 end
		local grip -- the first button taking mouse-downs (the column split's handle comes later)
		for _, f in ipairs(created) do
			if not grip and f.kind == "Button" and f.scripts.OnMouseDown then
				grip = f
			end
		end
		local cursor = { 500, 300 }
		_G.GetCursorPosition = function() return cursor[1], cursor[2] end
		grip.scripts.OnMouseDown(grip)
		cursor = { 538, 270 } -- 38 right, 30 down on a 380 x 300 window
		grip.scripts.OnUpdate(grip)
		assert.equal(1.1, frame.scale)
		assert.same({ "TOPLEFT", _G.UIParent, "BOTTOMLEFT", 100 / 1.1, 600 / 1.1 }, frame.point)
		grip.scripts.OnMouseUp(grip)
		assert.equal(1.1, db.window.scale)
		assert.is_nil(grip.scripts.OnUpdate)
		assert.equal(1.1, ns.UI.scale())
	end)

	it("browses another dex and back", function()
		loadDb()
		local friend = ns.Dex.new({})
		friend:recordMob({ name = "Wolf" }, { time = 5, zone = "Durotar", group = "Kalimdor" })
		ns.UI.showDex(friend, "Pal")
		ns.UI.setCompare(ns.dex)
		ns.UI.selectTab("Mobs")
		ns.UI.openDetail("Wolf")
		assert.is_true(ns.UI.isBrowsing())
		ns.UI.showDex(nil, nil)
		assert.is_false(ns.UI.isBrowsing())
	end)

	it("shows '« Friends' while browsing; it goes back to the Friends list on your own dex", function()
		loadDb()
		local friend = ns.Dex.new({})
		ns.UI.showDex(friend, "Pal")
		ns.UI.selectTab("Mobs")
		local button = find("Button", function(f)
			local label = rawget(f, "label")
			return label and label.text == "\194\171 Friends"
		end)
		assert.is_true(button.shown)
		button.scripts.OnClick(button)
		assert.is_false(ns.UI.isBrowsing())
		assert.is_false(button.shown)
		assert.equal("Friends", ns.UI.currentTab())

		ns.UI.showDex(friend, "Pal")
		local frame = _G.SoulDexFrame
		frame:Hide()
		frame.scripts.OnHide(frame)
		assert.is_false(ns.UI.isBrowsing())
	end)

	it("draws the Friends tab: leaderboard, add box and remove", function()
		_G.UnitName = function() return "Fel" end
		_G.time = function() return 5000 end
		_G.LibStub = nil
		local popup
		_G.StaticPopupDialogs = {}
		_G.StaticPopup_Show = function(name) popup = name end
		_G.IsInGuild = function() return false end -- Clean up removes nobody unless it can tell
		for _, file in ipairs({ "Comm", "Friends", "Shards", "Capture", "Net" }) do
			LoadAddonFile("src/" .. file .. ".lua", ns)
		end
		local db = loadDb()
		db.friends.Ann = { added = true, seen = 4990, summary = { score = 99, mobs = 1, players = 0, raids = 0 } }
		ns.UI.toggle()
		ns.UI.selectTab("Friends")
		local function rowWith(text)
			return find("Button", function(f)
				local left = rawget(f, "left")
				return left and left.text == text
			end)
		end
		assert.is_truthy(rowWith("1. Ann"))
		assert.is_truthy(rowWith("2. Fel (you)"))

		local box -- the add box: the last edit box built (the window's search box comes first)
		for _, f in ipairs(created) do
			if f.kind == "EditBox" then
				box = f
			end
		end
		box.GetText = function() return "bob" end
		box.scripts.OnEnterPressed(box)
		assert.is_true(db.friends.Bob.added)

		local row = find("Button", function(f) return f.value == "Ann" end)
		row.scripts.OnClick(row)
		assert.is_truthy(rowWith("Raids completed"))
		local function shownCrosses()
			local out = {}
			for _, f in ipairs(created) do
				local label = rawget(f, "label")
				if label and label.text == "\195\151" and f.shown then
					out[f] = true
				end
			end
			return out
		end
		local tip = {}
		local savedTooltip = _G.GameTooltip
		_G.GameTooltip = {
			SetOwner = function() end,
			SetText = function(_, text) tip.name = text end,
			Show = function() tip.shown = true end,
			Hide = function() tip.shown = false end,
		}
		local before = shownCrosses()
		row.scripts.OnEnter(row) -- Ann is added: hovering shows her ×
		-- and a tooltip with her full name
		assert.equal("Ann", tip.name)
		assert.is_true(tip.shown)
		local remove
		for f in pairs(shownCrosses()) do
			if not before[f] then
				assert.is_nil(remove)
				remove = f
			end
		end
		-- a redraw while the mouse is still over the row keeps its ×
		row.IsMouseOver = function() return true end
		ns.UI.refresh()
		assert.is_true(remove.shown)
		row.IsMouseOver = nil
		row.scripts.OnLeave(row)
		assert.is_false(tip.shown)
		_G.GameTooltip = savedTooltip
		remove.scripts.OnClick(remove)
		assert.is_false(db.friends.Ann.added) -- seen recently: kept, but no longer added

		-- "Clean up" asks first; accepting drops Ann (no longer added, not in guild or group)
		local cleanUp = find("Button", function(f)
			local label = rawget(f, "label")
			return label and label.text == "Clean up"
		end)
		cleanUp.scripts.OnClick(cleanUp)
		assert.equal("SOULDEX_CLEANUP", popup)
		assert.is_not_nil(db.friends.Ann)
		_G.StaticPopupDialogs[popup].OnAccept()
		assert.is_nil(db.friends.Ann)
		assert.is_true(db.friends.Bob.added)
	end)

	it("saves option switches as they are clicked", function()
		local db = loadDb()
		ns.Options.toggle()
		local check = find("CheckButton", function() return true end)
		check.checked = false
		check.scripts.OnClick(check)
		assert.is_false(db.settings.popup)
		assert.is_true(db.settings.sound)
	end)

	local function button(text)
		return find("Button", function(f) return f.label and f.label.text == text end)
	end

	-- The percent shown in the n-th SIZE row built: its - button is anchored to that text.
	local function shownSize(n)
		local minus
		local seen = 0
		for _, f in ipairs(created) do
			if f.kind == "Button" and f.label and f.label.text == "-" then
				seen = seen + 1
				if seen == n then
					minus = f
				end
			end
		end
		return minus and minus.point[2].text
	end

	-- The n-th button with this label (the SIZE rows each have a - and a +).
	local function nth(text, n)
		for _, f in ipairs(created) do
			if f.kind == "Button" and f.label and f.label.text == text then
				n = n - 1
				if n == 0 then
					return f
				end
			end
		end
	end

	it("scales the window within its limits and saves the scale", function()
		local db = loadDb()
		assert.equal(1, ns.UI.scale())
		assert.equal(1.2, ns.UI.setScale("120"))
		assert.equal(1.2, db.window.scale)
		ns.UI.toggle()
		assert.equal(1.2, _G.SoulDexFrame.scale)
		assert.equal(1.6, ns.UI.setScale(9))
		assert.equal(1.6, _G.SoulDexFrame.scale)
		assert.equal(1.6, ns.UI.setScale("big")) -- junk changes nothing
		db.window.scale = "broken"
		assert.equal(1, ns.UI.scale())
	end)

	it("resets the window to the middle at normal size", function()
		local db = loadDb()
		db.window.point, db.window.x, db.window.y, db.window.scale = "TOPLEFT", 4000, -4000, 1.5
		ns.UI.toggle()
		ns.UI.resetWindow()
		assert.is_nil(db.window.point)
		assert.is_nil(db.window.scale)
		assert.equal(1, _G.SoulDexFrame.scale)
		assert.equal("Players", db.window.tab) -- the tab is kept
	end)

	it("keeps a dragged window's corner in place when its size changes", function()
		local db = loadDb()
		db.window.point, db.window.relPoint, db.window.x, db.window.y = "TOPLEFT", "BOTTOMLEFT", 100, 500
		ns.UI.toggle()
		ns.UI.setScale(1.25)
		-- 100 and 500 screen units are 80 and 400 of a window drawn at 125%
		assert.equal(80, db.window.x)
		assert.equal(400, db.window.y)
		assert.same({ "TOPLEFT", _G.UIParent, "BOTTOMLEFT", 80, 400 }, _G.SoulDexFrame.point)
		ns.UI.setScale(1)
		assert.equal(100, db.window.x)
		assert.equal(500, db.window.y)
	end)

	it("the options' - and + step the window size and stop at the limits", function()
		local db = loadDb()
		ns.Options.toggle()
		local minus, plus = nth("-", 1), nth("+", 1)
		plus.scripts.OnClick()
		assert.equal(1.1, db.window.scale)
		minus.scripts.OnClick()
		minus.scripts.OnClick()
		assert.equal(0.9, db.window.scale)
		for _ = 1, 10 do
			minus.scripts.OnClick()
		end
		assert.equal(ns.Settings.SCALE_MIN, db.window.scale)
		assert.is_true(minus.alpha < 1) -- dimmed: it can go no further
		assert.equal(1, plus.alpha)
	end)

	it("open options follow a size set from outside them", function()
		local db = loadDb()
		ns.Options.refresh() -- nothing built yet: no error
		ns.Options.toggle()
		ns.UI.setScale(1.3)
		assert.equal("100%", shownSize(1))
		ns.Options.refresh()
		assert.equal("130%", shownSize(1))
		assert.equal(1.3, db.window.scale)
	end)

	it("Reset window puts the size back too", function()
		local db = loadDb()
		ns.Options.toggle()
		nth("+", 1).scripts.OnClick()
		assert.equal(1.1, db.window.scale)
		button("Reset window").scripts.OnClick()
		assert.is_nil(db.window.scale)
		assert.equal("100%", shownSize(1))
		assert.is_false(button("Reset").shown)
	end)

	it("the theme steps, is saved and repaints what is already drawn", function()
		local db = loadDb()
		local borders = {}
		methods.SetBackdropBorderColor = function(self, r, g, b) borders[self] = { r, g, b } end
		ns.Options.toggle() -- first: nth() finds its buttons before the window's
		ns.UI.toggle()
		local frame = _G.SoulDexFrame
		local function shownTheme()
			return nth("<", 1).point[2].text
		end
		assert.equal("soulshard", db.settings.theme)
		assert.equal("Soul Shard", shownTheme())
		nth(">", 1).scripts.OnClick()
		assert.equal("fel", db.settings.theme)
		assert.equal("fel", ns.Themes.current)
		assert.equal("Fel", shownTheme())
		assert.same({ ns.UIFormat.hexRGB("4f8a2a") }, borders[frame])
		nth("<", 1).scripts.OnClick()
		nth("<", 1).scripts.OnClick()
		assert.equal("ember", db.settings.theme)
		assert.same({ ns.UIFormat.hexRGB("9a3022") }, borders[frame])
		assert.equal("Interface\\AddOns\\SoulDex\\art\\ember\\rank1.tga", ns.Ranks.of(0).emblem)
		methods.SetBackdropBorderColor = nil
	end)

	it("draws in the saved theme from the start, and the default for an unknown one", function()
		local db = { settings = ns.Settings.normalise({ theme = "shadow" }), window = {} }
		ns.db = db
		ns.dex = ns.Dex.new(db)
		for _, fn in ipairs(ns.onLoaded) do
			fn(db)
		end
		assert.equal("shadow", ns.Themes.current)
		assert.equal("c18cff", ns.UIFormat.COLORS.ACCENT)
		db.settings.theme = "gone"
		for _, fn in ipairs(ns.onLoaded) do
			fn(db)
		end
		assert.equal("soulshard", ns.Themes.current)
	end)

	it("the popup size steps, resizes the popups and shows a sample", function()
		local db = loadDb()
		LoadAddonFile("src/Toast.lua", ns)
		db.settings.popup = false -- the sample shows the size even with the popup off
		ns.Options.toggle()
		local before = #created
		local plus = nth("+", 2)
		plus.scripts.OnClick()
		assert.equal(1.1, db.settings.popupScale)
		assert.is_nil(db.window.scale) -- the window's size is its own
		local soul = created[before + 1] -- the sample built the popups
		assert.equal(1.1, soul.scale)
		assert.is_true(soul.shown)
		assert.is_truthy(soul.name.text:find("Hogger", 1, true))
		for _ = 1, 10 do
			plus.scripts.OnClick()
		end
		assert.equal(ns.Settings.SCALE_MAX, db.settings.popupScale)
		assert.equal(ns.Settings.SCALE_MAX, soul.scale)
		assert.is_true(plus.alpha < 1)
	end)

	it("an undragged window stays 60 above the middle at every size", function()
		loadDb()
		ns.UI.toggle()
		ns.UI.setScale(1.5)
		assert.same({ "CENTER", _G.UIParent, "CENTER", 0, 40 }, _G.SoulDexFrame.point)
	end)

	it("Reset puts both sizes back to 100% and shows only when one is changed", function()
		local db = loadDb()
		ns.Toast = { rescale = function() end, show = function() end }
		ns.Options.toggle()
		local reset = button("Reset")
		assert.is_false(reset.shown)
		nth("+", 1).scripts.OnClick()
		nth("-", 2).scripts.OnClick()
		assert.is_true(reset.shown)
		reset.scripts.OnClick()
		assert.equal(1, db.window.scale)
		assert.equal(1, db.settings.popupScale)
		assert.is_false(reset.shown)
	end)

	it("shows a sample popup without recording anything", function()
		local db = loadDb()
		local shown
		ns.Toast = { show = function(result, info) shown = { result, info } end }
		local souls = ns.dex:uniqueSouls()
		ns.Options.testPopup()
		assert.equal("Hogger", shown[2].name)
		assert.equal(souls + 1, shown[1].total)
		assert.equal(souls, ns.dex:uniqueSouls())
		assert.is_true(db.settings.sound) -- no ns.Capture here: the sound is skipped, no error
	end)

	it("registers a page with the game's Settings window when it has one", function()
		assert.is_false(ns.Options.register()) -- no Settings API in this client
		local registered
		_G.Settings = {
			RegisterCanvasLayoutCategory = function(page, name) return { page = page, name = name } end,
			RegisterAddOnCategory = function(category) registered = category end,
		}
		loadDb()
		assert.is_true(ns.Options.register())
		assert.equal("SoulDex", registered.name)
		-- both sets of switches follow one setting
		ns.Options.toggle()
		registered.page.scripts.OnShow()
		_G.Settings = { RegisterCanvasLayoutCategory = function() error("refused") end, RegisterAddOnCategory = error }
		assert.is_false(ns.Options.register())
		_G.Settings = nil
	end)

	it("the sample popup plays its sound, except as the Popup size row's preview", function()
		loadDb()
		local played = 0
		local savedPlay = _G.PlaySound
		_G.PlaySound = function() played = played + 1 end
		ns.Toast = { show = function() end, rescale = function() end }
		ns.Capture = { soundFor = function() return 1 end }
		ns.Options.testPopup()
		assert.equal(1, played)
		ns.Options.testPopup(true)
		assert.equal(1, played)
		ns.Options.toggle()
		button("Test popup").scripts.OnClick(button("Test popup"), "LeftButton")
		assert.equal(2, played) -- the button's own arguments don't make it quiet
		nth("+", 2).scripts.OnClick()
		assert.equal(2, played) -- the size preview is silent
		_G.PlaySound = savedPlay
	end)

	it("the floating panel and the game's Settings page show the same sizes after a step", function()
		_G.Settings = {
			RegisterCanvasLayoutCategory = function(page, name) return { page = page, name = name } end,
			RegisterAddOnCategory = function() end,
		}
		local db = loadDb() -- registers the page: the first set of controls
		ns.Toast = { show = function() end, rescale = function() end }
		ns.Options.toggle() -- the floating panel: the second set
		-- rows as built: the page's Window and Popup, then the panel's Window and Popup
		local function sizes()
			return { shownSize(1), shownSize(2), shownSize(3), shownSize(4) }
		end
		assert.same({ "100%", "100%", "100%", "100%" }, sizes())
		nth("+", 1).scripts.OnClick() -- the page's Window +
		assert.equal(1.1, db.window.scale)
		assert.same({ "110%", "100%", "110%", "100%" }, sizes())
		nth("-", 4).scripts.OnClick() -- the panel's Popup -
		assert.equal(0.9, db.settings.popupScale)
		assert.same({ "110%", "90%", "110%", "90%" }, sizes())
		-- "Reset" shows on both, and either one puts both surfaces back
		local resets = {}
		for _, f in ipairs(created) do
			if f.kind == "Button" and f.label and f.label.text == "Reset" then
				resets[#resets + 1] = f
			end
		end
		assert.equal(2, #resets)
		assert.is_true(resets[1].shown and resets[2].shown)
		resets[2].scripts.OnClick()
		assert.same({ "100%", "100%", "100%", "100%" }, sizes())
		assert.is_false(resets[1].shown or resets[2].shown)
		_G.Settings = nil
	end)

	it("sizes the popups and keeps them at the same place on screen", function()
		local db = loadDb()
		LoadAddonFile("src/Toast.lua", ns)
		local soul, rank = ns.Toast.offsets(1)
		assert.equal(-140, soul)
		assert.equal(-140 - 54 - 8, rank)
		soul, rank = ns.Toast.offsets(1.4)
		assert.equal(-100, soul) -- 100 units of a popup drawn at 140% are 140 on screen
		assert.equal(-100 - 54 - 8, rank)

		db.settings.popupScale = 1.4
		ns.Toast.rescale() -- nothing built yet: no error
		local before = #created
		ns.Toast.prepare()
		local a, b = created[before + 1], created[before + 2]
		assert.equal(1.4, a.scale)
		assert.equal(1.4, b.scale)
		assert.equal(-100, a.offset)
		db.settings.popupScale = 0.8
		ns.Toast.rescale()
		assert.equal(0.8, a.scale)
		assert.equal(-175, a.offset)
	end)

	-- The toolbar (spec 5.9) ------------------------------------------------------------

	-- The toolbar button whose label starts with `prefix` ("Sort:", "Show:").
	local function toolButton(prefix)
		return find("Button", function(f)
			local label = rawget(f, "label")
			return label ~= nil and type(label.text) == "string" and label.text:sub(1, #prefix) == prefix
		end)
	end

	local function friendDex()
		local friend = ns.Dex.new({})
		friend:recordMob({ name = "Wolf" }, { time = 5, zone = "Durotar", group = "Kalimdor" })
		return friend
	end

	it("is 380 x 300", function()
		loadDb()
		ns.UI.toggle()
		assert.equal(380, _G.SoulDexFrame.w)
		assert.equal(300, _G.SoulDexFrame.h)
	end)

	it("searches as the box is typed in; text that can't be read is no search", function()
		loadDb()
		ns.Capture = { plainString = function(v) return type(v) == "string" and v ~= "" end }
		ns.UI.toggle()
		local box = find("EditBox", function() return true end)
		box.GetText = function() return "ho" end
		box.scripts.OnTextChanged(box, true)
		assert.equal("ho", ns.UI.search())
		box.GetText = function() return 42 end
		box.scripts.OnTextChanged(box, true)
		assert.equal("", ns.UI.search())
	end)

	it("a search moves to Mobs from the Me tab; picking a tab ends it", function()
		loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Me")
		ns.UI.setSearch("ho")
		assert.equal("Mobs", ns.UI.currentTab())
		assert.equal("ho", ns.UI.search())
		ns.UI.selectTab("Players")
		assert.equal("", ns.UI.search())
	end)

	it("the Sort button steps and saves the choice per tab", function()
		local db = loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		local sort = toolButton("Sort:")
		assert.equal("Sort: A\226\128\147Z", sort.label.text)
		sort.scripts.OnClick(sort, "LeftButton")
		assert.equal("count", db.window.sort.Mobs)
		assert.equal("Sort: Most claimed", sort.label.text)
		sort.scripts.OnClick(sort, "RightButton") -- a right-click steps back
		assert.equal("name", db.window.sort.Mobs)
	end)

	it("a saved Newest sort reads A-Z while browsing a friend", function()
		local db = loadDb()
		db.window.sort = { Mobs = "recent" }
		ns.UI.showDex(friendDex(), "Morwen")
		ns.UI.selectTab("Mobs")
		assert.equal("Sort: A\226\128\147Z", toolButton("Sort:").label.text)
	end)

	it("the Show button steps, and resets when the window closes", function()
		loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		local show = toolButton("Show:")
		assert.equal("Show: All", show.label.text)
		show.scripts.OnClick(show, "LeftButton")
		assert.equal("Show: Rare and elite", show.label.text)
		-- closing and reopening your own dex: back to the first choice
		local frame = _G.SoulDexFrame
		frame:Hide()
		frame.scripts.OnHide(frame)
		ns.UI.toggle()
		assert.equal("Show: All", show.label.text)
	end)

	it("the Show choice resets when another friend's dex is shown", function()
		loadDb()
		ns.UI.showDex(friendDex(), "Morwen")
		ns.UI.selectTab("Mobs")
		local show = toolButton("Show:")
		assert.equal("Show: Their dex", show.label.text)
		show.scripts.OnClick(show, "LeftButton")
		assert.equal("Show: Differences", show.label.text)
		ns.UI.showDex(friendDex(), "Ann")
		assert.equal("Show: Their dex", show.label.text)
	end)

	it("widens the left list to the saved split; Reset window restores it", function()
		local db = loadDb()
		db.window.split = 180
		ns.UI.toggle() -- remembered tab: Players
		local left = find("ScrollFrame", function() return true end)
		assert.equal(180, left.w)
		ns.UI.resetWindow()
		assert.is_nil(db.window.split)
		assert.equal(124, left.w)
	end)

	it("drags the column split and saves it when let go", function()
		local db = loadDb()
		ns.UI.toggle()
		local frame = _G.SoulDexFrame
		frame.GetEffectiveScale = function() return 2 end
		local handle
		for _, f in ipairs(created) do
			if f.kind == "Button" and f.scripts.OnMouseDown then
				handle = f -- the last one: the grip comes first
			end
		end
		local x = 500
		_G.GetCursorPosition = function() return x, 300 end
		handle.scripts.OnMouseDown(handle)
		x = 540 -- 40 on screen at an effective scale of 2: 20 in the window
		handle.scripts.OnUpdate(handle)
		assert.equal(144, find("ScrollFrame", function() return true end).w)
		assert.is_nil(db.window.split)
		handle.scripts.OnMouseUp(handle)
		assert.equal(144, db.window.split)
		assert.is_nil(handle.scripts.OnUpdate)
	end)

	-- A shown list row whose text contains `text`.
	local function shownRow(text)
		return find("Button", function(f)
			local left = rawget(f, "left")
			return f.shown and left ~= nil and type(left.text) == "string" and left.text:find(text, 1, true) ~= nil
		end)
	end

	it("opens a search result's card and keeps it only while that search lasts", function()
		loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		local cards = 0
		local playerCard = ns.UIFormat.playerCard
		ns.UIFormat.playerCard = function(...)
			cards = cards + 1
			return playerCard(...)
		end
		ns.UI.setSearch("sta")
		local row = find("Button", function(f)
			return f.shown and type(f.value) == "table" and f.value.kind == "player"
		end)
		row.scripts.OnClick(row)
		assert.equal(1, cards)
		ns.UI.refresh()
		assert.equal(2, cards) -- redrawn, still open
		ns.UI.setSearch("")
		ns.UI.refresh()
		assert.equal(2, cards) -- the search ended and took the card with it
	end)

	it("starts the right list with the compare line while browsing, but not during a search", function()
		loadDb()
		ns.UI.showDex(friendDex(), "Morwen")
		ns.UI.setCompare(ns.dex)
		ns.UI.selectTab("Mobs")
		assert.is_truthy(shownRow("1 missing"))
		ns.UI.setSearch("wo")
		assert.is_nil(shownRow("1 missing"))
		assert.is_truthy(shownRow("Wolf"))
	end)

	it("says so when the Show choice leaves nothing", function()
		loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		local show = toolButton("Show:")
		show.scripts.OnClick(show, "LeftButton") -- Rare and elite: Hogger
		assert.is_nil(shownRow("Nothing here matches."))
		show.scripts.OnClick(show, "LeftButton") -- Mastered: nothing
		assert.is_truthy(shownRow("Nothing here matches."))
	end)

	it("draws the All selection on a dex that has become empty", function()
		local db = loadDb()
		db.window.tab = "Mobs"
		for _, fn in ipairs(ns.onLoaded) do
			fn(db)
		end
		ns.UI.toggle() -- a fresh window selects All zones
		assert.is_truthy(find("Button", function(f) return f.value == ns.Browse.ALL end))
		ns.dex = ns.Dex.new({})
		ns.UI.refresh()
		assert.equal("Mobs", ns.UI.currentTab())
	end)

	-- Review fixes (spec 5.9) -----------------------------------------------------------

	local function searchBoxOf()
		return find("EditBox", function() return true end) -- the window's: the first built
	end

	local function splitGrip()
		local handle
		for _, f in ipairs(created) do
			if f.kind == "Button" and f.scripts.OnMouseDown then
				handle = f -- the last one: the window's corner grip comes first
			end
		end
		return handle
	end

	-- Counts the calls of ns.UIFormat[name]; onCall(...) sees each one's arguments.
	local function counting(name, onCall)
		local calls = { n = 0 }
		local original = ns.UIFormat[name]
		ns.UIFormat[name] = function(...)
			calls.n = calls.n + 1
			if onCall then
				onCall(...)
			end
			return original(...)
		end
		return calls
	end

	local function mobsTab(db)
		db.window.tab = "Mobs"
		for _, fn in ipairs(ns.onLoaded) do
			fn(db)
		end
	end

	it("a fresh copy of the same friend's dex keeps the search and the Show choice", function()
		loadDb()
		ns.UI.showDex(friendDex(), "Morwen")
		ns.UI.selectTab("Mobs")
		ns.UI.setSearch("wo")
		ns.UI.showDex(friendDex(), "Morwen")
		assert.equal("wo", ns.UI.search())
		assert.is_truthy(shownRow("Wolf"))
		ns.UI.setSearch("")
		local show = toolButton("Show:")
		show.scripts.OnClick(show, "LeftButton")
		assert.equal("Show: Differences", show.label.text)
		ns.UI.showDex(friendDex(), "Morwen")
		assert.equal("Show: Differences", show.label.text)
		-- another friend's dex still starts afresh
		ns.UI.setSearch("wo")
		ns.UI.showDex(friendDex(), "Ann")
		assert.equal("", ns.UI.search())
		assert.equal("Show: Their dex", show.label.text)
	end)

	it("a fresh copy of the same friend's dex keeps an open card that is still valid", function()
		loadDb()
		local cards = counting("mobCard")
		ns.UI.showDex(friendDex(), "Morwen")
		ns.UI.selectTab("Mobs")
		ns.UI.openDetail("Wolf")
		assert.equal(1, cards.n)
		ns.UI.showDex(friendDex(), "Morwen")
		assert.equal(2, cards.n) -- drawn again from the new copy
		ns.UI.showDex(ns.Dex.new({}), "Morwen") -- Wolf is not in this one: the card closes
		ns.UI.refresh()
		assert.equal(2, cards.n)
	end)

	it("a card from the All row or a search result shows the soul's total over every zone", function()
		loadDb()
		for t = 2000, 2001 do
			ns.dex:recordMob({ name = "Hogger", classification = "elite" },
				{ time = t, zone = "Westfall", group = "Eastern Kingdoms" })
		end
		local shown
		counting("mobCard", function(d) shown = d end)
		ns.UI.toggle()
		ns.UI.selectTab("Mobs") -- All zones
		ns.UI.openDetail("Hogger")
		assert.equal(3, shown.count)
		assert.equal("Westfall +1", shown.place)
		shown = nil
		ns.UI.setSearch("hog")
		local row = find("Button", function(f)
			return f.shown and type(f.value) == "table" and f.value.kind == "mob"
		end)
		row.scripts.OnClick(row)
		assert.equal(3, shown.count)
		-- one zone selected: that zone's count
		ns.UI.setSearch("")
		local zone = find("Button", function(f) return f.shown and f.value == "Westfall" end)
		zone.scripts.OnClick(zone)
		ns.UI.openDetail("Hogger")
		assert.equal(2, shown.count)
	end)

	it("All zones counts the rows it lists: raid souls are not mobs there", function()
		loadDb() -- Hogger and the raid soul Lucifron
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		local all = find("Button", function(f) return f.shown and f.value == ns.Browse.ALL end)
		assert.equal("1", all.right.text)
	end)

	it("clicks elsewhere in the window take the keyboard from the search box", function()
		mobsTab(loadDb())
		ns.UI.toggle()
		local box = searchBoxOf()
		local cleared = 0
		box.ClearFocus = function() cleared = cleared + 1 end
		ns.UI.setSearch("ho")
		cleared = 0
		local row = find("Button", function(f)
			return f.shown and type(f.value) == "table" and f.value.kind == "mob"
		end)
		row.scripts.OnClick(row)
		assert.equal(1, cleared)
		ns.UI.setSearch("")
		cleared = 0
		local sort, show = toolButton("Sort:"), toolButton("Show:")
		sort.scripts.OnClick(sort, "LeftButton")
		assert.equal(1, cleared)
		show.scripts.OnClick(show, "LeftButton")
		assert.equal(2, cleared)
		local handle = splitGrip()
		_G.GetCursorPosition = function() return 500, 300 end
		_G.SoulDexFrame.GetEffectiveScale = function() return 1 end
		handle.scripts.OnMouseDown(handle)
		assert.equal(3, cleared)
		handle.scripts.OnMouseUp(handle)
	end)

	it("dragging the split moves the lists without redrawing them; letting go redraws once", function()
		local db = loadDb()
		ns.UI.toggle()
		local frame = _G.SoulDexFrame
		frame.GetEffectiveScale = function() return 1 end
		local handle = splitGrip()
		local draws = counting("keepScroll") -- every draw starts with it
		local x = 500
		_G.GetCursorPosition = function() return x, 300 end
		handle.scripts.OnMouseDown(handle)
		for step = 1, 5 do
			x = 500 + step * 4
			handle.scripts.OnUpdate(handle)
		end
		assert.equal(0, draws.n)
		assert.equal(144, find("ScrollFrame", function() return true end).w)
		assert.same({ "BOTTOMLEFT", 144 + 2 - 3, 0 }, handle.point) -- the grip follows
		handle.scripts.OnMouseUp(handle)
		assert.equal(1, draws.n)
		assert.equal(144, db.window.split)
		-- a drag that ends with the window closing saves, and draws no hidden window
		handle.scripts.OnMouseDown(handle)
		x = 524
		handle.scripts.OnUpdate(handle)
		frame:Hide()
		handle.scripts.OnHide(handle)
		assert.equal(1, draws.n)
		assert.equal(148, db.window.split)
	end)

	it("a search builds no zone rows it would only throw away", function()
		loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		local built = counting("mobRows")
		ns.UI.setSearch("ho")
		assert.equal(0, built.n)
		assert.is_truthy(shownRow("Hogger"))
		ns.UI.setSearch("")
		assert.equal(1, built.n)
	end)

	it("a dex of only unknown souls says nothing matches instead of a blank list", function()
		local db = loadDb()
		ns.dex = ns.Dex.new({})
		ns.dex:recordUnknown({ time = 5, zone = "Elwynn Forest", group = "Eastern Kingdoms" })
		mobsTab(db)
		ns.UI.toggle()
		assert.is_truthy(shownRow("Nothing here matches."))
	end)

	it("no compare line above an empty dex's note", function()
		loadDb()
		ns.UI.showDex(ns.Dex.new({}), "Morwen")
		ns.UI.setCompare(ns.dex)
		ns.UI.selectTab("Mobs")
		assert.is_truthy(shownRow("No souls claimed yet."))
		assert.is_nil(shownRow("only mine"))
		ns.UI.selectTab("Players")
		assert.is_truthy(shownRow("No player souls yet."))
		assert.is_nil(shownRow("only mine"))
	end)

	it("labels the Show button as kind show", function()
		loadDb()
		local kinds = {}
		counting("toolLabel", function(kind) kinds[kind] = true end)
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		assert.is_true(kinds.show)
		assert.is_nil(kinds.filter)
	end)

	it("stepping Show closes the card; stepping Sort keeps it", function()
		loadDb()
		local cards = counting("mobCard")
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		ns.UI.openDetail("Hogger")
		assert.equal(1, cards.n)
		local sort, show = toolButton("Sort:"), toolButton("Show:")
		sort.scripts.OnClick(sort, "LeftButton")
		assert.equal(2, cards.n) -- kept and drawn again
		show.scripts.OnClick(show, "LeftButton")
		ns.UI.refresh()
		assert.equal(2, cards.n) -- closed
	end)

	it("typing a search keeps the left list's scroll; a search that moves tab resets it", function()
		mobsTab(loadDb())
		for i = 1, 20 do
			local ctx = { time = 1000, zone = string.format("Zone %02d", i), group = "Kalimdor" }
			ns.dex:recordMob({ name = "Mob " .. i }, ctx)
		end
		ns.UI.toggle()
		local scrolls = {}
		for _, f in ipairs(created) do
			if f.kind == "ScrollFrame" then
				scrolls[#scrolls + 1] = f
			end
		end
		local left, right = scrolls[1], scrolls[2]
		left.scripts.OnMouseWheel(left, -3)
		local leftScroll = left.vscroll
		assert.is_true(leftScroll > 0)
		ns.UI.setSearch("mo")
		assert.equal(leftScroll, left.vscroll)
		assert.equal(0, right.vscroll)
		ns.UI.setSearch("mob")
		assert.equal(leftScroll, left.vscroll)
		ns.UI.selectTab("Me")
		ns.UI.setSearch("mo") -- moves to Mobs: both lists start at the top
		assert.equal("Mobs", ns.UI.currentTab())
		assert.equal(0, left.vscroll)
	end)

	it("a search result's card survives a new catch while the same search lasts", function()
		loadDb()
		ns.UI.toggle()
		ns.UI.selectTab("Mobs")
		local cards = counting("mobCard")
		ns.UI.setSearch("hog")
		local row = find("Button", function(f)
			return f.shown and type(f.value) == "table" and f.value.kind == "mob"
		end)
		row.scripts.OnClick(row)
		assert.equal(1, cards.n)
		ns.dex:recordMob({ name = "Hogger", classification = "elite" },
			{ time = 2000, zone = "Elwynn Forest", group = "Eastern Kingdoms" })
		ns.onCatch[1]({}, {}) -- a new catch redraws through draw's check: drawn again, not closed
		assert.equal(2, cards.n)
		assert.equal("hog", ns.UI.search())
	end)
end)
