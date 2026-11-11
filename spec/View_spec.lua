describe("View", function()
	local ns, dex, friend, View

	local function ctx(zone, group, extra)
		local c = { time = 1000, myLevel = 20, zone = zone, group = group or "Eastern Kingdoms", x = 10, y = 20 }
		for k, v in pairs(extra or {}) do
			c[k] = v
		end
		return c
	end

	local function mob(name, extra)
		local m = { name = name, level = 10, classification = "normal", creatureType = "Beast", family = "Wolf" }
		for k, v in pairs(extra or {}) do
			m[k] = v
		end
		return m
	end

	local function player(name, class, extra)
		local p = { name = name, realm = "Realm", level = 38, class = class, race = "Orc", guild = "Guildies" }
		for k, v in pairs(extra or {}) do
			p[k] = v
		end
		return p
	end

	before_each(function()
		ns = {
			RaidData = {
				{
					key = "MC",
					name = "Molten Core",
					instanceID = 409,
					mobs = {
						{ id = 12118, name = "Lucifron", boss = true },
						{ id = 11671, name = "Core Hound" },
						{ id = 11672, name = "Core Rager" },
					},
				},
				{ key = "ZG", name = "Zul'Gurub", instanceID = 309, mobs = { { id = 1, name = "Zed" } } },
			},
		}
		LoadAddonFile("src/Raids.lua", ns)
		LoadAddonFile("src/Points.lua", ns)
		LoadAddonFile("src/Dex.lua", ns)
		LoadAddonFile("src/Flavour.lua", ns)
		LoadAddonFile("src/Milestones.lua", ns)
		LoadAddonFile("src/View.lua", ns)
		View = ns.View
		dex = ns.Dex.new({})
		friend = ns.Dex.new({})
	end)

	describe("places", function()
		it("orders groups and omits empty ones", function()
			dex:recordMob(mob("A"), ctx("Zeta", "Dungeons"))
			dex:recordMob(mob("B"), ctx("Durotar", "Kalimdor"))
			dex:recordMob(mob("C"), ctx("Elwynn Forest"))
			dex:recordMob(mob("D"), ctx("Elwynn Forest"))
			dex:recordMob(mob("E"), ctx("Westfall"))
			dex:recordMob(mob("F"), ctx("Zzz", "Other"))
			local seq = {}
			for _, r in ipairs(View.places(dex)) do
				seq[#seq + 1] = r.header or (r.place .. ":" .. r.count)
			end
			assert.same({
				"Eastern Kingdoms", "Elwynn Forest:2", "Westfall:1",
				"Kalimdor", "Durotar:1",
				"Other", "Zzz:1",
				"Dungeons", "Zeta:1",
			}, seq)
		end)

		it("puts Raids just before Dungeons", function()
			dex:recordMob(mob("A"), ctx("Zeta", "Dungeons"))
			dex:recordMob(mob("B"), ctx("Ahn'Qiraj", "Raids"))
			dex:recordMob(mob("C"), ctx("Zzz", "Other"))
			local headers = {}
			for _, r in ipairs(View.places(dex)) do
				headers[#headers + 1] = r.header
			end
			assert.same({ "Other", "Raids", "Dungeons" }, headers)
		end)

		it("is empty for an empty dex", function()
			assert.same({}, View.places(dex))
		end)
	end)

	describe("mobsAt", function()
		it("lists A-Z with counts and highlights what other lacks", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordMob(mob("Boar", { classification = "elite" }), ctx("Elwynn Forest"))
			dex:recordMob(mob("Bear"), ctx("Westfall"))
			friend:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			local rows = View.mobsAt(dex, "Elwynn Forest", friend)
			assert.equal(2, #rows)
			assert.same({ name = "Boar", count = 1, classification = "elite", highlight = true }, rows[1])
			assert.same({ name = "Wolf", count = 2, classification = "normal", highlight = false }, rows[2])
			assert.is_false(View.mobsAt(dex, "Elwynn Forest")[1].highlight)
		end)
	end)

	describe("players", function()
		before_each(function()
			dex:recordPlayer(player("Ann", "ROGUE"), ctx("Elwynn Forest"))
			dex:recordPlayer(player("Bob", "ROGUE"), ctx("Elwynn Forest"))
			dex:recordPlayer(player("Bob", "ROGUE"), ctx("Westfall", nil, { time = 2000 }))
			dex:recordPlayer(player("Cy", "MAGE"), ctx("Elwynn Forest"))
			dex:recordPlayer(player("Di", "MAGE"), ctx("Elwynn Forest"))
			dex:recordPlayer(player("Ed", "WARRIOR"), ctx("Elwynn Forest"))
		end)

		it("sorts classes by count then name", function()
			assert.same({
				{ class = "MAGE", count = 2 },
				{ class = "ROGUE", count = 2 },
				{ class = "WARRIOR", count = 1 },
			}, View.classes(dex))
		end)

		it("lists players of a class by count and highlights", function()
			friend:recordPlayer(player("Ann", "ROGUE"), ctx("Elwynn Forest"))
			local rows = View.playersOf(dex, "ROGUE", friend)
			assert.equal("Bob", rows[1].name)
			assert.equal("Bob-Realm", rows[1].key)
			assert.equal(2, rows[1].count)
			assert.is_true(rows[1].highlight)
			assert.is_false(rows[2].highlight)
		end)

		it("gives player detail", function()
			local d = View.playerDetail(dex, "Bob-Realm")
			assert.equal("Lv 38 Orc Rogue", d.levelRaceClass)
			assert.equal("Guildies", d.guild)
			assert.equal(2, d.count)
			assert.equal(38, d.firstLevel)
			assert.equal(38, d.lastLevel)
			assert.equal(2, #d.places)
			assert.equal(1, d.places[1].count)
			assert.equal("Elwynn Forest", d.places[1].zone)
			assert.is_nil(View.playerDetail(dex, "Nobody-Realm"))
		end)
	end)

	describe("raids", function()
		it("reports progress in data order", function()
			dex:recordRaid(mob("Core Hound"), ctx("Molten Core", "Dungeons"), 409, 11671)
			local rows = View.raids(dex)
			assert.equal(2, #rows)
			assert.same({ instanceID = 409, name = "Molten Core", caught = 1, total = 3, done = false }, rows[1])
			dex:recordRaid(mob("Zed"), ctx("Zul'Gurub", "Dungeons"), 309, 1)
			assert.is_true(View.raids(dex)[2].done)
		end)

		it("tolerates an unknown raid mob without a name", function()
			dex.db.raids[777] = { instanceID = 409, count = 1, points = 1 }
			dex.db.raids[778] = { name = "Mystery", instanceID = 409, count = 1, points = 1 }
			local ok, rows = pcall(View.raidMobs, dex, 409, nil)
			assert.is_true(ok)
			assert.equal(5, #rows)
		end)

		it("lists raid mobs with blanks, bosses and unknown mobs last", function()
			dex:recordRaid(mob("Core Rager"), ctx("Molten Core", "Dungeons"), 409, 11672)
			dex:recordRaid(mob("Mystery"), ctx("Molten Core", "Dungeons"), 409, 99999)
			friend:recordRaid(mob("Core Rager"), ctx("Molten Core", "Dungeons"), 409, 11672)
			local rows = View.raidMobs(dex, 409, friend)
			assert.equal(4, #rows)
			assert.is_nil(rows[1].name)
			assert.is_true(rows[1].boss)
			assert.is_false(rows[1].caught)
			assert.is_false(rows[1].highlight)
			assert.is_nil(rows[2].name)
			assert.is_false(rows[2].boss)
			assert.equal("Core Rager", rows[3].name)
			assert.is_true(rows[3].caught)
			assert.equal(1, rows[3].count)
			assert.is_false(rows[3].highlight)
			assert.equal("Mystery", rows[4].name)
			assert.is_false(rows[4].known)
			assert.is_true(rows[4].highlight)
		end)

		it("gives raid detail", function()
			dex:recordRaid(mob("Core Rager"), ctx("Molten Core", "Dungeons"), 409, 11672)
			local d = View.raidDetail(dex, 11672)
			assert.equal("Core Rager", d.name)
			assert.equal(1, d.count)
			assert.equal(20, d.myLevel)
			assert.equal(1000, d.first)
			assert.truthy(d.flavour:find("Core Rager", 1, true))
			assert.is_nil(View.raidDetail(dex, 5))
		end)
	end)

	describe("mobDetail", function()
		it("shows a level range, type text and the chosen place's record", function()
			dex:recordMob(mob("Wolf", { level = 10 }), ctx("Elwynn Forest", nil, { time = 1000, x = 1, y = 2 }))
			dex:recordMob(mob("Wolf", { level = 12 }), ctx("Westfall", nil, { time = 2000, myLevel = 30, x = 5, y = 6 }))
			local d = View.mobDetail(dex, "Wolf", "Westfall")
			assert.equal("Lv 10\226\128\14712", d.levelText)
			assert.equal("Beast \194\183 Wolf", d.typeText)
			assert.equal("normal", d.classification)
			assert.equal(1, d.count)
			assert.equal(2000, d.first)
			assert.equal(30, d.myLevel)
			assert.equal(5, d.x)
			assert.equal(6, d.y)
			assert.equal(1, d.points)
			assert.truthy(d.flavour:find("Elwynn Forest", 1, true))
			assert.equal(1000, View.mobDetail(dex, "Wolf", "Elwynn Forest").first)
		end)

		it("returns nil for a missing name or place", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			assert.is_nil(View.mobDetail(dex, "Nope", "Elwynn Forest"))
			assert.is_nil(View.mobDetail(dex, "Wolf", "Westfall"))
		end)
	end)

	describe("header", function()
		it("builds each tab's right side", function()
			for i = 1, 400 do
				dex:recordMob(mob("M" .. i), ctx("Elwynn Forest"))
			end
			dex:recordPlayer(player("Ann", "ROGUE"), ctx("Elwynn Forest"))
			dex:recordRaid(mob("Core Hound"), ctx("Molten Core", "Dungeons"), 409, 11671)
			local pts = dex:score() .. " pts"
			local left, right = View.header(dex, "Mobs")
			assert.equal("Soul-Dex \194\183 Mobs", left)
			assert.equal("401 \194\183 " .. pts, right)
			assert.equal("1 \194\183 " .. pts, select(2, View.header(dex, "Players")))
			assert.equal("1/4 \194\183 " .. pts, select(2, View.header(dex, "Raids")))
			assert.truthy(select(2, View.header(dex, "Milestones")):find("^%d+/%d+ \194\183 "))
			assert.equal(pts, select(2, View.header(dex, "Friends")))
		end)

		it("adds thousands separators", function()
			dex.db.mobs.Big = { name = "Big", points = 1840, places = {} }
			assert.equal("1,840 pts", select(2, View.header(dex, "Friends")))
		end)
	end)
end)
