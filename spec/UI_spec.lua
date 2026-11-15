-- Smoke test: the window code loads and runs against minimal frame stubs.
-- Every frame method is a no-op unless listed below.
describe("UI", function()
	local STUBBED = {
		"CreateFrame", "UIParent", "UISpecialFrames", "GameFontNormal", "GameFontHighlightSmall",
		"RAID_CLASS_COLORS", "SoulDexFrame", "SoulDexOptionsFrame", "date", "UnitName", "time", "LibStub",
		"StaticPopupDialogs", "StaticPopup_Show",
	}
	local saved, created, ns

	local Stub = {}
	local methods = {
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
		IsShown = function(self) return self.shown end,
		SetScript = function(self, name, fn) self.scripts[name] = fn end,
		SetText = function(self, text) self.text = text end,
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
			"Settings", "Raids", "Points", "Rarity", "Ranks", "Flavour", "Dex", "Milestones", "View",
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
		assert.equal(1, #ns.onLoaded)
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

	it("shows '« My dex' while browsing; it and closing the window go back to yours", function()
		loadDb()
		local friend = ns.Dex.new({})
		ns.UI.showDex(friend, "Pal")
		local button = find("Button", function(f)
			local label = rawget(f, "label")
			return label and label.text == "\194\171 My dex"
		end)
		assert.is_true(button.shown)
		button.scripts.OnClick(button)
		assert.is_false(ns.UI.isBrowsing())
		assert.is_false(button.shown)

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

		local box = find("EditBox", function() return true end)
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
		local before = shownCrosses()
		row.scripts.OnEnter(row) -- Ann is added: hovering shows her ×
		local remove
		for f in pairs(shownCrosses()) do
			if not before[f] then
				assert.is_nil(remove)
				remove = f
			end
		end
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
end)
