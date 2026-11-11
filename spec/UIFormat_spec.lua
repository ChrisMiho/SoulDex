describe("UIFormat", function()
	local F

	before_each(function()
		F = LoadAddonFile("src/UIFormat.lua", {}).UIFormat
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
				{ instanceID = 309, name = "ZG", caught = 3, total = 3, done = true },
				{ instanceID = 409, name = "MC", caught = 1, total = 3, done = false },
			}, 409)
			assert.equal(F.MARKS.CHECK, rows[1].right)
			assert.equal("7dff6a", rows[1].rightColor)
			assert.equal("1/3", rows[2].right)
			assert.is_true(rows[2].selected)
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
		end)
	end)

	describe("detail lines", function()
		it("draws a full mob detail in spec order", function()
			local lines = F.mobDetailLines({
				name = "Hogger",
				classification = "elite",
				levelText = "Lv 11",
				typeText = "Humanoid \194\183 Gnoll",
				flavour = "Loud.",
				place = "Elwynn Forest",
				count = 2,
				first = stamp(2026, 11, 3),
				last = stamp(2026, 11, 9),
				myLevel = 12,
				x = 26.4,
				y = 89.1,
				points = 25,
			}, os.date)
			assert.same({
				"Hogger | Elite",
				"Lv 11 Humanoid \194\183 Gnoll",
				"\"Loud.\"",
				"--",
				"Caught | \195\1512",
				"First | 3 Nov 26 \194\183 you Lv 12",
				"Where | 26.4, 89.1",
				"Last | 9 Nov 26",
				"--",
				"25 pts",
			}, texts(lines))
			assert.is_true(lines[1].big)
			assert.is_true(lines[3].wrap)
		end)

		it("never shows nil for a friend's bare mob", function()
			local lines = F.mobDetailLines({ name = "Wolf", typeText = "" }, os.date)
			local d = F.DASH
			assert.same({
				"Wolf",
				"--",
				"Caught | " .. d,
				"First | " .. d,
				"Where | " .. d,
				"Last | " .. d,
			}, texts(lines))
		end)

		it("falls back to the place when there are no coordinates (raids)", function()
			local lines = F.mobDetailLines({ name = "Lucifron", place = "Molten Core", count = 1, typeText = "" }, os.date)
			assert.equal("Where | Molten Core", texts(lines)[5])
		end)

		it("draws a full player detail", function()
			local lines = F.playerDetailLines({
				name = "Stabbyface",
				class = "ROGUE",
				levelRaceClass = "Lv 38 Orc Rogue",
				guild = "Blood Fang",
				count = 5,
				first = stamp(2026, 11, 2),
				firstLevel = 34,
				last = stamp(2026, 11, 9),
				lastLevel = 38,
				points = 15,
				places = {
					{ zone = "Hillsbrad", x = 52.1, y = 47.3, count = 3 },
					{ zone = "Arathi", count = 2 },
				},
			}, os.date, { ROGUE = { r = 1, g = 0.96, b = 0.41 } })
			assert.same({
				"Stabbyface",
				"Lv 38 Orc Rogue",
				"<Blood Fang>",
				"--",
				"Sharded | \195\1515",
				"First | 2 Nov 26 \194\183 Lv 34",
				"Last | 9 Nov 26 \194\183 Lv 38",
				"--",
				"Hillsbrad | 52.1, 47.3  \195\1513",
				"Arathi | \195\1512",
				"--",
				"15 pts",
			}, texts(lines))
			assert.equal("fff569", lines[1].color)
		end)

		it("never shows nil for a friend's bare player", function()
			local lines = F.playerDetailLines({ name = "Stab", levelRaceClass = "", places = {} }, os.date, nil)
			local d = F.DASH
			assert.same({ "Stab", "--", "Sharded | " .. d, "First | " .. d, "Last | " .. d }, texts(lines))
			assert.equal("ffffff", lines[1].color)
		end)
	end)
end)
