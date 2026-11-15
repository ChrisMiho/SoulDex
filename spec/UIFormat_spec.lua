describe("UIFormat", function()
	local F

	before_each(function()
		F = LoadAddonFile("src/UIFormat.lua", LoadAddonFile("src/View.lua", LoadAddonFile("src/Rarity.lua", {}))).UIFormat
	end)

	local function texts(lines)
		local out = {}
		for i, line in ipairs(lines) do
			if line.hr then
				out[i] = "--"
			elseif line.right then
				out[i] = line.text .. " | " .. line.right
			else
				out[i] = line.text
			end
		end
		return out
	end

	local function stamp(y, m, d)
		return os.time({ year = y, month = m, day = d, hour = 12 })
	end

	describe("helpers", function()
		it("formats coordinates to one decimal, nil when missing", function()
			assert.equal("26.4, 89.1", F.coordsText(26.43, 89.08))
			assert.equal("5.0, 0.0", F.coordsText(5, 0))
			assert.is_nil(F.coordsText(nil, 3))
			assert.is_nil(F.coordsText(3, nil))
		end)

		it("formats dates without a leading zero, nil when missing", function()
			assert.equal("3 Nov 26", F.dateText(stamp(2026, 11, 3), os.date))
			assert.equal("19 Dec 25", F.dateText(stamp(2025, 12, 19), os.date))
			assert.is_nil(F.dateText(nil, os.date))
		end)

		it("joins only the parts that exist", function()
			assert.equal("a · c", F.join({ "a", nil, "c" }, " · ", 3))
			assert.equal("b", F.join({ nil, "b", "" }, " ", 3))
			assert.is_nil(F.join({ nil, nil }, " ", 2))
		end)

		it("turns hex into 0..1 colours", function()
			local r, g, b = F.hexRGB("ff8000")
			assert.equal(1, r)
			assert.is_true(math.abs(g - 128 / 255) < 1e-9)
			assert.equal(0, b)
		end)

		it("makes class hex from RAID_CLASS_COLORS-shaped tables", function()
			local colors = { ROGUE = { r = 1, g = 0.96, b = 0.41 } }
			assert.equal("fff569", F.classHex("ROGUE", colors))
			assert.is_nil(F.classHex("MAGE", colors))
			assert.is_nil(F.classHex("ROGUE", nil))
		end)

		it("decides which lists keep their scroll for each redraw", function()
			assert.same({ true, false }, { F.keepScroll("select") })
			assert.same({ true, true }, { F.keepScroll("refresh") })
			assert.same({ false, false }, { F.keepScroll("tab") })
			assert.same({ false, false }, { F.keepScroll("open") })
			assert.same({ false, false }, { F.keepScroll(nil) })
		end)

		it("keeps a valid selection, else picks the first", function()
			local rows = { { header = "X" }, { place = "A" }, { place = "B" } }
			assert.equal("B", F.pick(rows, "place", "B"))
			assert.equal("A", F.pick(rows, "place", "Gone"))
			assert.equal("A", F.pick(rows, "place", nil))
			assert.is_nil(F.pick({}, "place", "A"))
		end)
	end)

	describe("list rows", function()
		it("draws places with headers and the selection", function()
			local rows = F.placeRows({
				{ header = "Eastern Kingdoms" },
				{ place = "Elwynn Forest", count = 2 },
				{ place = "Westfall", count = 1 },
			}, "Westfall")
			assert.same({ "EASTERN KINGDOMS", "Elwynn Forest | 2", "Westfall | 1" }, texts(rows))
			assert.is_true(rows[1].header)
			assert.is_nil(rows[1].value)
			assert.is_false(rows[2].selected)
			assert.is_true(rows[3].selected)
			assert.equal("Westfall", rows[3].value)
		end)

		it("marks elites, rares and bosses, and highlights", function()
			local rows = F.mobRows({
				{ name = "Hogger", count = 2, classification = "elite" },
				{ name = "Mother Fang", count = 1, classification = "rare" },
				{ name = "Kazzak", count = 1, classification = "worldboss" },
				{ name = "Wolf", count = 14, classification = "normal", highlight = true },
			})
			assert.equal("Hogger " .. F.MARKS.STAR, rows[1].text)
			assert.equal("ffd25a", rows[1].color)
			assert.equal("\195\1512", rows[1].right)
			assert.equal("Mother Fang", rows[2].text)
			assert.equal("c0c0c0", rows[2].color)
			assert.equal("Kazzak " .. F.MARKS.SKULL, rows[3].text)
			assert.equal("ff9a5a", rows[3].color)
			assert.equal("7dff6a", rows[4].color)
			assert.equal("Wolf", rows[4].value)
		end)

		it("draws the Unknown soul row muted and not clickable", function()
			local rows = F.mobRows({ { name = "Unknown soul", count = 3, unknown = true } })
			assert.same({ text = "Unknown soul", color = F.COLORS.MUTED, right = "\195\1513" }, rows[1])
			assert.is_nil(rows[1].value)
		end)

		it("names classes in their colours", function()
			local rows = F.classRows({ { class = "ROGUE", count = 6 }, { class = "UNKNOWN", count = 1 } }, "ROGUE",
				{ ROGUE = { r = 1, g = 0.96, b = 0.41 } }, { ROGUE = "Rogue" })
			assert.same({ "Rogue | 6", "Unknown | 1" }, texts(rows))
			assert.equal("fff569", rows[1].color)
			assert.is_true(rows[1].selected)
			assert.equal("UNKNOWN", rows[2].value)
		end)

		it("lists players by key", function()
			local rows = F.playerRows({ { key = "Stab-Realm", name = "Stab", count = 5 } })
			assert.same({ "Stab | \195\1515" }, texts(rows))
			assert.equal("Stab-Realm", rows[1].value)
		end)

		it("shows raid progress or a check when done", function()
			local rows = F.raidRows({
				{ key = "ZG", instanceID = 309, name = "ZG", caught = 3, total = 3, done = true },
				{ key = "MC", instanceID = 409, name = "MC", caught = 1, total = 3, done = false },
			}, "MC")
			assert.equal("MC", rows[2].value)
			assert.equal(F.MARKS.CHECK, rows[1].right)
			assert.equal("7dff6a", rows[1].rightColor)
			assert.equal("1/3", rows[2].right)
			assert.is_true(rows[2].selected)
			assert.is_nil(rows[1].bar) -- done: the tick says it
			assert.equal(1 / 3, rows[2].bar)
		end)

		it("marks a TBD raid and counts what was claimed there", function()
			local rows = F.raidRows({
				{ key = "BD", name = "The Barrow Deeps", caught = 0, total = 0, done = false, tbd = true },
				{ key = "Hyjal", instanceID = 3002, name = "Hyjal Summit", caught = 4, total = 0, done = false, tbd = true },
			}, "BD")
			assert.equal("TBD", rows[1].right)
			assert.equal("4 / ?", rows[2].right)
			assert.is_nil(rows[1].bar)
			assert.is_nil(rows[2].bar)
			assert.equal("BD", rows[1].value)
			assert.is_true(rows[1].selected)
			assert.is_false(rows[2].selected)
		end)

		it("writes the TBD note", function()
			assert.equal("Roster still sealed: 8 bosses wait inside. Every soul you claim here is kept.",
				F.tbdNote({ bossCount = 8 }).text)
			assert.equal("Roster still sealed. Every soul you claim here is kept.", F.tbdNote({}).text)
		end)

		it("hides uncaught raid mobs, keeps boss skulls, and only caught rows click", function()
			local rows = F.raidMobRows({
				{ npcID = 1, name = "Lucifron", boss = true, count = 3, caught = true },
				{ npcID = 2, boss = false, caught = false },
				{ npcID = 3, boss = true, caught = false },
			})
			assert.equal("Lucifron " .. F.MARKS.SKULL, rows[1].text)
			assert.equal(1, rows[1].value)
			assert.equal("? ? ?", rows[2].text)
			assert.equal("4d4360", rows[2].color)
			assert.is_nil(rows[2].value)
			assert.equal("? ? ? " .. F.MARKS.SKULL_DIM, rows[3].text)
			assert.is_nil(rows[3].value)
		end)

		it("shows earned milestones with a date and the rest with progress", function()
			local rows = F.milestoneRows({
				{ id = "a", text = "10 unique souls", earned = stamp(2026, 11, 3), progress = 12, goal = 10 },
				{ id = "b", text = "50 unique souls", progress = 12, goal = 50 },
				{ id = "c", text = "Completed X", progress = 0, goal = 0 },
			}, os.date)
			assert.same({ "10 unique souls | 3 Nov 26", "50 unique souls | 12/50", "Completed X | 0/0" }, texts(rows))
			assert.equal("ffffff", rows[1].color)
			assert.equal("6e6385", rows[2].color)
			assert.is_nil(rows[1].bar)
			assert.equal(12 / 50, rows[2].bar)
			assert.is_nil(rows[3].bar)
		end)

		it("names a milestone in fel green when it has a title", function()
			local rows = F.milestoneRows({
				{
					id = "a", title = "First Harvest", text = "10 unique mobs",
					earned = stamp(2026, 11, 3), progress = 12, goal = 10,
				},
				{ id = "b", title = "Soul Collector", text = "50 unique mobs", progress = 60, goal = 50 },
			}, os.date)
			assert.equal("|cff9dff3aFirst Harvest|r \194\183 10 unique mobs", rows[1].text)
			assert.equal("9a8fb0", rows[1].color)
			assert.equal("Soul Collector \194\183 50 unique mobs", rows[2].text)
			assert.equal("50/50", rows[2].right)
			assert.equal(1, rows[2].bar)
		end)

		it("puts mastery stars in front of a row's count", function()
			assert.equal("3" .. F.MARKS.FEL_STAR .. " \195\151212", F.masteryCount(3, 212))
			assert.equal("\195\1514", F.masteryCount(nil, 4))
			assert.equal("\195\1514", F.masteryCount(0, 4))
			local rows = F.mobRows({ { name = "Wolf", count = 30, stars = 2 }, { name = "Boar", count = 1 } })
			assert.equal("2" .. F.MARKS.FEL_STAR .. " \195\15130", rows[1].right)
			assert.equal("\195\1511", rows[2].right)
			assert.are_not.equal(F.MARKS.STAR, F.MARKS.FEL_STAR) -- not the elite mark
		end)
	end)

	describe("trophy card", function()
		local function cells(card)
			local out = {}
			for i, c in ipairs(card.cells) do
				out[i] = c.label .. " | " .. c.value
			end
			return out
		end

		it("builds a full mob card", function()
			local card = F.mobCard({
				name = "Hogger", classification = "elite", levelText = "Lv 11", typeText = "Humanoid \194\183 Gnoll",
				creatureType = "Humanoid", flavour = "Loud.", count = 12, first = stamp(2026, 11, 3), myLevel = 12,
				x = 26.4, y = 89.1, last = stamp(2026, 11, 9), points = 7,
				mastery = { stars = 1, count = 12, from = 10, to = 25 },
			}, os.date)
			assert.equal("Hogger", card.title)
			assert.equal("ffd25a", card.color)
			assert.equal("Elite \194\183 Lv 11 Humanoid \194\183 Gnoll", card.sub)
			assert.equal("7 pts", card.badge)
			assert.equal("Loud.", card.quote)
			assert.equal("Interface\\Icons\\Ability_Rogue_Disguise", card.icon)
			assert.same({
				"Claimed | \195\15112", "First | 3 Nov 26 \194\183 Lv 12", "Where | 26.4, 89.1", "Last | 9 Nov 26",
			}, cells(card))
			assert.same({ lit = 1, total = 8, text = "12 / 25 to next star", bar = 2 / 15 }, card.stars)
			assert.equal(F.MARKS.FEL_STAR, F.starText(card.stars):sub(1, #F.MARKS.FEL_STAR))
		end)

		it("never shows nil for a friend's bare mob, and leaves out what it lacks", function()
			local card = F.mobCard({ name = "Wolf", typeText = "", flavour = "" }, os.date)
			local d = F.DASH
			assert.same({ "Claimed | " .. d, "First | " .. d, "Where | " .. d, "Last | " .. d }, cells(card))
			assert.equal("ffffff", card.color)
			assert.is_nil(card.sub)
			assert.is_nil(card.badge)
			assert.is_nil(card.quote)
			assert.is_nil(card.stars)
			assert.is_nil(card.icon) -- no creature type: the window supplies the rank emblem
			assert.is_nil(F.typeIcon(nil))
			assert.is_nil(F.typeIcon("Aberration"))
			assert.is_nil(F.SHARD_ICON)
		end)

		it("falls back to the place when there are no coordinates (raids), and has no stars for a boss", function()
			local card = F.mobCard({ name = "Lucifron", place = "Molten Core", count = 3, points = 75 }, os.date)
			assert.equal("Where | Molten Core", cells(card)[3])
			assert.is_nil(card.stars)
		end)

		it("shows stars past the row of eight as +N", function()
			local card = F.mobCard({ name = "Boar", mastery = { stars = 11, count = 2600, from = 2500, to = 3000 } })
			assert.equal(8, card.stars.lit)
			assert.equal(3, card.stars.extra)
			assert.truthy(F.starText(card.stars):find(" +3", 1, true))
		end)

		it("builds a player card with its places below", function()
			local card = F.playerCard({
				name = "Stab", class = "ROGUE", levelRace = "Lv 38 Orc", guild = "Knives", count = 5,
				first = stamp(2026, 11, 2), firstLevel = 36, last = stamp(2026, 11, 7), lastLevel = 38, points = 13,
				places = { { zone = "Stranglethorn", x = 1, y = 2, count = 4 }, { zone = "Duskwood", count = 1 } },
			}, os.date, { ROGUE = { r = 1, g = 0.96, b = 0.41 } }, { ROGUE = "Rogue" })
			assert.equal("fff569", card.color)
			assert.equal("Lv 38 Orc Rogue", card.sub)
			assert.equal("13 pts", card.badge)
			assert.equal(F.PLAYER_ICON, card.icon)
			assert.same({
				"Sharded | \195\1515", "Guild | <Knives>", "First | 2 Nov 26 \194\183 Lv 36", "Last | 7 Nov 26 \194\183 Lv 38",
			}, cells(card))
			assert.equal("Stranglethorn", card.lines[1].text)
			assert.equal("1.0, 2.0  \195\1514", card.lines[1].right)
			assert.equal("\195\1511", card.lines[2].right)
			local bare = F.playerCard({ name = "Cid", levelRace = "", places = {} }, os.date, nil, nil)
			assert.is_nil(bare.sub)
			assert.equal("Guild | " .. F.DASH, cells(bare)[2])
		end)
	end)

	describe("milestone groups", function()
		local items = {
			{ id = "a", group = "Mobs", title = "First Harvest", text = "10 mobs", earned = 100, progress = 12, goal = 10 },
			{ id = "b", group = "Mobs", title = "Soul Collector", text = "50 mobs", earned = 900, progress = 60, goal = 50 },
			{ id = "c", group = "Mobs", title = "A Hundred Voices", text = "100 mobs", progress = 60, goal = 100 },
			{ id = "d", group = "Players", title = "First Blood", text = "First player soul", progress = 0, goal = 1 },
		}

		it("puts what is left to earn on top and folds the earned ones away", function()
			local rows = F.milestoneGroups(items, { "Mobs", "Players", "Raids" }, {}, os.date)
			assert.equal("MOBS", rows[1].text)
			assert.equal("2 of 3", rows[1].right)
			assert.truthy(rows[2].text:find("A Hundred Voices", 1, true))
			assert.equal(0.6, rows[2].bar)
			assert.truthy(rows[3].text:find("2 earned", 1, true))
			assert.equal("group:Mobs", rows[3].value)
			assert.equal("show", rows[3].right)
			assert.equal("PLAYERS", rows[4].text)
			assert.equal("0 of 1", rows[4].right)
			assert.equal(5, #rows) -- no Raids header: nothing in that group
		end)

		it("opens a group's earned milestones, newest first", function()
			local rows = F.milestoneGroups(items, { "Mobs", "Players" }, { Mobs = true }, os.date)
			assert.equal("hide", rows[3].right)
			assert.truthy(rows[4].text:find("Soul Collector", 1, true))
			assert.truthy(rows[5].text:find("First Harvest", 1, true))
			assert.equal("PLAYERS", rows[6].text)
		end)
	end)

	describe("records", function()
		it("words each record", function()
			local now = 86400 * 100 + 50
			local lines = F.recordLines({
				{ label = "Most claimed", text = "Wolf \195\15114" },
				{ label = "Nemesis", name = "Stab", count = 5, class = "ROGUE" },
				{ label = "Rarest trophy", name = "Ragnaros", classification = "worldboss" },
				{ label = "Latest", name = "Boar", time = now - 10 },
				{ label = "Latest", name = "Boar", time = now - 86400 },
				{ label = "Best day", souls = 41, time = stamp(2026, 11, 9) },
				{ label = "Best day" },
			}, now, os.date, { ROGUE = { r = 1, g = 0.96, b = 0.41 } })
			assert.equal("Wolf \195\15114", lines[1].right)
			assert.equal("Stab \195\1515", lines[2].right)
			assert.equal("fff569", lines[2].rightColor)
			assert.equal("ff9a5a", lines[3].rightColor)
			assert.equal("Boar \194\183 today", lines[4].right)
			assert.equal("Boar \194\183 yesterday", lines[5].right)
			assert.equal("41 souls \194\183 9 Nov 26", lines[6].right)
			assert.equal(F.DASH, lines[7].right)
		end)
	end)
end)
