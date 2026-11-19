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
				{ key = "BD", name = "The Barrow Deeps", tbd = true, mobs = {} },
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
		LoadAddonFile("src/Friends.lua", ns)
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

		it("lists a zone with only unknown souls, counting unique mobs (0)", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordUnknown(ctx("Elwynn Forest"))
			dex:recordUnknown(ctx("Westfall"))
			local seq = {}
			for _, r in ipairs(View.places(dex)) do
				seq[#seq + 1] = r.header or (r.place .. ":" .. r.count)
			end
			assert.same({ "Eastern Kingdoms", "Elwynn Forest:1", "Westfall:0" }, seq)
		end)

		it("copes with a dex table that has no unknown list", function()
			dex.db.unknown = nil
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			assert.equal(2, #View.places(dex))
		end)
	end)

	describe("places new", function()
		it("counts the mobs of a place that the other dex lacks", function()
			dex:recordMob(mob("Hogger"), ctx("Elwynn Forest"))
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			friend:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			local function elwynn(rows)
				for _, row in ipairs(rows) do
					if row.place == "Elwynn Forest" then
						return row
					end
				end
			end
			assert.equal(1, elwynn(View.places(dex, friend)).new)
			assert.equal(0, elwynn(View.places(dex)).new)
		end)
	end)

	describe("mastery", function()
		it("puts stars on rows and the way to the next star in the details", function()
			for _ = 1, 12 do
				dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			end
			dex:recordMob(mob("Boar"), ctx("Elwynn Forest"))
			local rows = View.mobsAt(dex, "Elwynn Forest")
			assert.is_nil(rows[1].stars) -- Boar: none yet
			assert.equal(1, rows[2].stars)
			local d = View.mobDetail(dex, "Wolf", "Elwynn Forest")
			assert.same({ stars = 1, count = 12, from = 10, to = 25 }, d.mastery)
			assert.equal(2, d.points) -- first claim and one star
			assert.equal("2", (function()
				for _, line in ipairs(View.me(dex, nil, nil, 0)) do
					if line.label == "Mastery stars" then
						return tostring(tonumber(line.value) + 1)
					end
				end
			end)())
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

		it("ends with one Unknown soul row for the zone", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordUnknown(ctx("Elwynn Forest"))
			dex:recordUnknown(ctx("Elwynn Forest"))
			dex:recordUnknown(ctx("Westfall"))
			local rows = View.mobsAt(dex, "Elwynn Forest", friend)
			assert.equal(2, #rows)
			assert.equal("Wolf", rows[1].name)
			assert.same({ name = "Unknown soul", count = 2, unknown = true }, rows[2])
			assert.same({ { name = "Unknown soul", count = 1, unknown = true } }, View.mobsAt(dex, "Westfall"))
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
				{ class = "MAGE", count = 2, new = 0 },
				{ class = "ROGUE", count = 2, new = 0 },
				{ class = "WARRIOR", count = 1, new = 0 },
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

		it("counts the players of a class that the other dex lacks", function()
			friend:recordPlayer(player("Ann", "ROGUE"), ctx("Elwynn Forest"))
			local function newOf(rows, class)
				for _, row in ipairs(rows) do
					if row.class == class then
						return row.new
					end
				end
			end
			assert.equal(1, newOf(View.classes(dex, friend), "ROGUE"))
			assert.equal(2, newOf(View.classes(dex, friend), "MAGE"))
			assert.equal(0, newOf(View.classes(dex), "ROGUE"))
		end)

		it("gives player detail", function()
			local d = View.playerDetail(dex, "Bob-Realm")
			assert.equal("Lv 38 Orc", d.levelRace)
			assert.equal("ROGUE", d.class)
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
			assert.equal(3, #rows)
			assert.same({ key = "MC", instanceID = 409, name = "Molten Core", caught = 1, total = 3, done = false,
				tbd = false }, rows[2])
			dex:recordRaid(mob("Zed"), ctx("Zul'Gurub", "Dungeons"), 309, 1)
			assert.is_true(View.raids(dex)[3].done)
		end)

		it("lists a TBD raid first, uncounted", function()
			local rows = View.raids(dex)
			assert.same({ key = "BD", name = "The Barrow Deeps", caught = 0, total = 0, done = false, tbd = true },
				rows[1])
		end)

		it("counts what was claimed in a TBD raid once its id is known", function()
			dex:raidFor(3001, "The Barrow Deeps")
			dex:recordRaid(mob("Barrow Thing"), ctx("The Barrow Deeps", "Raids"), 3001, 555)
			local row = View.raids(dex)[1]
			assert.equal(3001, row.instanceID)
			assert.equal(1, row.caught)
			assert.is_false(row.done)
			local mobs = View.raidMobs(dex, 3001, nil)
			assert.equal(1, #mobs)
			assert.equal("Barrow Thing", mobs[1].name)
		end)

		it("keeps TBD raids out of the header and Me totals", function()
			dex:raidFor(3001, "The Barrow Deeps")
			dex:recordRaid(mob("Barrow Thing"), ctx("The Barrow Deeps", "Raids"), 3001, 555)
			local _, right = View.header(dex, "Raids")
			assert.truthy(right:find("^0/4"))
			local card = View.meCard(dex, nil, nil, 0)
			assert.equal("Raids", card.tiles[3].label)
			assert.equal("0 / 2", card.tiles[3].value)
		end)

		it("returns no rows for a raid with no id yet", function()
			assert.same({}, View.raidMobs(dex, nil, nil))
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

		it("marks each raid row missing, shared, mine or neither", function()
			dex:recordRaid(mob("Lucifron"), ctx("Molten Core", "Dungeons"), 409, 12118)
			dex:recordRaid(mob("Core Hound"), ctx("Molten Core", "Dungeons"), 409, 11671)
			friend:recordRaid(mob("Core Hound"), ctx("Molten Core", "Dungeons"), 409, 11671)
			friend:recordRaid(mob("Whatever"), ctx("Molten Core", "Dungeons"), 409, 11672)
			friend:recordRaid(mob("Whatever"), ctx("Molten Core", "Dungeons"), 409, 11672)
			dex:recordRaid(mob("Zed"), ctx("Zul'Gurub", "Dungeons"), 309, 1)
			local rows = View.raidMobs(dex, 409, friend)
			assert.equal("missing", rows[1].side)
			assert.is_true(rows[1].highlight)
			assert.equal("shared", rows[2].side)
			assert.is_false(rows[2].highlight)
			assert.equal("mine", rows[3].side)
			assert.is_false(rows[3].caught)
			assert.equal("Core Rager", rows[3].name)
			assert.equal(2, rows[3].count)
			assert.equal(3, #rows)
			local none = View.raidMobs(ns.Dex.new({}), 409, ns.Dex.new({}))
			assert.is_nil(none[1].side)
			assert.is_nil(View.raidMobs(dex, 409)[1].side)
		end)

		it("raidMobs unlisted mine: lists an unlisted soul only the other dex has", function()
			friend:recordRaid(mob("Mystery"), ctx("Molten Core", "Dungeons"), 409, 99999)
			friend:recordRaid(mob("Mystery"), ctx("Molten Core", "Dungeons"), 409, 99999)
			friend.db.raids[98765] = { instanceID = 409, count = 1, points = 1 } -- no name: skipped
			friend:recordRaid(mob("Elsewhere"), ctx("Zul'Gurub", "Dungeons"), 309, 99998)
			local rows = View.raidMobs(dex, 409, friend)
			assert.equal(4, #rows)
			assert.same({ npcID = 99999, name = "Mystery", boss = false, count = 2, caught = false, known = false,
				highlight = false, side = "mine" }, rows[4])
			assert.equal(3, #View.raidMobs(dex, 409))
		end)

		it("gives raid detail", function()
			dex:recordRaid(mob("Core Rager", { classification = "elite", creatureType = "Beast", family = "Core Hound" }),
				ctx("Molten Core", "Dungeons"), 409, 11672)
			local d = View.raidDetail(dex, 11672)
			assert.equal("Core Rager", d.name)
			assert.equal("elite", d.classification)
			assert.equal("Lv 10", d.levelText)
			assert.equal("Beast \194\183 Core Hound", d.typeText)
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

	describe("me", function()
		local DASH = "\226\128\148"
		local TIMES = "\195\151"

		local function values(lines)
			local out = {}
			for _, l in ipairs(lines) do
				out[l.label] = l.value
			end
			return out
		end

		local function labels(lines)
			local out = {}
			for _, l in ipairs(lines) do
				out[#out + 1] = l.label
			end
			return out
		end

		local function me(d)
			return {
				name = "Fel",
				summary = { score = d:score(), mobs = d:uniqueMobs(), players = d:uniquePlayers(), raids = d:raidsCompleted() },
			}
		end

		it("shows dashes for an empty dex and hides Unknown souls", function()
			local lines = View.me(dex, nil, nil, 100)
			assert.same({
				"Unique mobs", "Players", "Raids completed", "Mastery stars", "Souls taken",
				"Zones visited", "Most claimed", "Top zone", "Friends rank",
			}, labels(lines))
			local v = values(lines)
			assert.equal("0", v["Souls taken"])
			assert.equal("0", v["Zones visited"])
			assert.equal(DASH, v["Most claimed"])
			assert.equal(DASH, v["Top zone"])
			assert.equal(DASH, v["Friends rank"])
		end)

		it("totals souls, zones, the most-caught mob and the top zone", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordMob(mob("Wolf"), ctx("Westfall"))
			dex:recordMob(mob("Boar"), ctx("Westfall"))
			dex:recordPlayer(player("Ann", "ROGUE"), ctx("Westfall"))
			dex:recordRaid(mob("Core Hound"), ctx("Molten Core", "Dungeons"), 409, 11671)
			local v = values(View.me(dex, nil, nil, 100))
			assert.equal("6", v["Souls taken"])
			assert.equal("2", v["Zones visited"])
			assert.equal("Wolf " .. TIMES .. "3", v["Most claimed"])
			assert.equal("Westfall " .. TIMES .. "3", v["Top zone"])
			assert.equal("3", v["Unique mobs"])
			assert.equal("1", v.Players)
		end)

		it("breaks ties alphabetically", function()
			dex:recordMob(mob("Zebra"), ctx("Durotar", "Kalimdor"))
			dex:recordMob(mob("Aardvark"), ctx("Elwynn Forest"))
			local v = values(View.me(dex, nil, nil, 100))
			assert.equal("Aardvark " .. TIMES .. "1", v["Most claimed"])
			assert.equal("Durotar " .. TIMES .. "1", v["Top zone"])
		end)

		it("counts unknown souls and shows the line only above zero", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordUnknown(ctx("Westfall"))
			dex:recordUnknown(ctx("Westfall"))
			local v = values(View.me(dex, nil, nil, 100))
			assert.equal("3", v["Souls taken"])
			assert.equal("2", v["Zones visited"])
			assert.equal("2", v["Unknown souls"])
			assert.equal("Westfall " .. TIMES .. "2", v["Top zone"])
		end)

		it("handles an older dex without unknown souls or player places", function()
			local old = ns.Dex.new({
				mobs = { Wolf = { name = "Wolf", places = { Durotar = { count = 2 } } } },
				players = { ["Ann-R"] = { name = "Ann", count = 3 } },
			})
			old.db.unknown = nil
			local v = values(View.me(old, nil, nil, 0))
			assert.equal("5", v["Souls taken"])
			assert.equal("1", v["Zones visited"])
			assert.is_nil(v["Unknown souls"])
		end)

		it("shows no rank line for a browsed dex (no friends or me given)", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			local v = values(View.me(dex, false, nil, 0))
			assert.is_nil(v["Friends rank"])
			assert.equal("Souls taken", View.me(dex, false, nil, 0)[5].label)
		end)

		it("adds raid catches to Souls taken but not Zones visited", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			dex:recordRaid(mob("Core Hound"), ctx("Molten Core", "Dungeons"), 409, 11671)
			dex:recordRaid(mob("Core Hound"), ctx("Molten Core", "Dungeons"), 409, 11671)
			local v = values(View.me(dex, nil, nil, 0))
			assert.equal("3", v["Souls taken"])
			assert.equal("1", v["Zones visited"])
			assert.equal("Wolf " .. TIMES .. "1", v["Most claimed"])
		end)

		it("ranks you among the friends you have seen", function()
			dex:recordMob(mob("Wolf"), ctx("Elwynn Forest"))
			local store = {
				Ann = { seen = 90, summary = { score = 500 } },
				Bob = { seen = 90, summary = { score = 0 } },
			}
			assert.equal("#2 of 3", values(View.me(dex, store, me(dex), 100))["Friends rank"])
			-- added friends we have not heard from are not ranked
			store.Cid = { added = true }
			assert.equal("#2 of 3", values(View.me(dex, store, me(dex), 100))["Friends rank"])
			assert.equal(DASH, values(View.me(dex, { Cid = { added = true } }, me(dex), 100))["Friends rank"])
			assert.equal(DASH, values(View.me(dex, {}, me(dex), 100))["Friends rank"])
			assert.equal(DASH, values(View.me(dex, nil, me(dex), 100))["Friends rank"])
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
			assert.equal("SoulDex \194\183 Mobs", left)
			assert.equal("401 \194\183 " .. pts, right)
			assert.equal("1 \194\183 " .. pts, select(2, View.header(dex, "Players")))
			assert.equal("1/4 \194\183 " .. pts, select(2, View.header(dex, "Raids")))
			assert.truthy(select(2, View.header(dex, "Milestones")):find("^%d+/%d+ \194\183 "))
			assert.equal(pts, select(2, View.header(dex, "Friends")))
			assert.equal(pts, select(2, View.header(dex, "Me")))
		end)

		it("adds thousands separators", function()
			dex.db.mobs.Big = { name = "Big", points = 1840, places = {} }
			assert.equal("1,840 pts", select(2, View.header(dex, "Friends")))
		end)
	end)

	describe("meCard", function()
		it("gives six tiles and the records, from what the dex holds", function()
			local DAY = 86400
			for i = 1, 3 do
				dex:recordMob(mob("Wolf"), { time = DAY * 3 + i, myLevel = 9, zone = "Elwynn Forest", group = "Eastern Kingdoms" })
			end
			dex:recordMob(mob("Hogger", { classification = "elite" }),
				{ time = DAY * 4, myLevel = 9, zone = "Elwynn Forest", group = "Eastern Kingdoms" })
			for _ = 1, 2 do
				dex:recordPlayer({ name = "Stab", realm = "R", level = 30, class = "ROGUE" },
					{ time = DAY * 2, myLevel = 9, zone = "Westfall", group = "Eastern Kingdoms" })
			end
			dex:recordPlayer({ name = "Ann", realm = "R", level = 30, class = "MAGE" },
				{ time = DAY * 2, myLevel = 9, zone = "Westfall", group = "Eastern Kingdoms" })
			local card = View.meCard(dex, nil, nil, DAY * 4)
			local tiles = {}
			for i, t in ipairs(card.tiles) do
				tiles[i] = t.label .. "=" .. tostring(t.value)
			end
			assert.equal(6, #tiles)
			assert.equal("Unique mobs=2", tiles[1])
			assert.equal("Players=2", tiles[2])
			assert.equal("Souls taken=7", tiles[5])
			assert.equal("Among friends", card.tiles[6].label)
			local rec = {}
			for _, r in ipairs(card.records) do
				rec[r.label] = r
			end
			assert.equal("Stab", rec.Nemesis.name)
			assert.equal(2, rec.Nemesis.count)
			assert.equal("ROGUE", rec.Nemesis.class)
			assert.equal("Hogger", rec["Rarest trophy"].name)
			assert.equal("Hogger", rec.Latest.name)
			assert.equal(DAY * 4, rec.Latest.time)
			assert.equal(3, rec["Best day"].souls)
			assert.truthy(rec["Most claimed"].text:find("Wolf", 1, true))
			assert.truthy(rec["Hunting ground"].text:find("Elwynn Forest", 1, true))
		end)

		it("works on an empty dex and swaps the friends tile when browsing", function()
			local card = View.meCard(dex, false, nil, 0)
			assert.equal("Zones", card.tiles[6].label)
			for _, r in ipairs(card.records) do
				assert.is_nil(r.name, r.label)
			end
		end)
	end)

	describe("find", function()
		before_each(function()
			dex:recordMob(mob("Defias Pillager"), ctx("Westfall"))
			dex:recordMob(mob("Defias Pillager"), ctx("Westfall"))
			dex:recordMob(mob("Defias Pillager"), ctx("The Deadmines", "Dungeons"))
			dex:recordMob(mob("Young Wolf"), ctx("Elwynn Forest"))
			dex:recordPlayer(player("Wolfbane", "ROGUE"), ctx("Westfall"))
			dex:recordRaid(mob("Core Hound"), ctx("Molten Core", "Raids"), 409, 11671)
		end)

		it("matches any case anywhere in the name, names starting with the text first", function()
			local found = View.find(dex, "WOLF")
			assert.equal(2, #found)
			assert.equal("Wolfbane", found[1].name)
			assert.equal("player", found[1].kind)
			assert.equal("ROGUE", found[1].where)
			assert.equal("Young Wolf", found[2].name)
		end)

		it("ignores case for accented letters too (\195\166 finds \195\134)", function()
			dex:recordMob(mob("\195\134thelwulf"), ctx("Dun Morogh"))
			dex:recordMob(mob("Gr\195\171ymane"), ctx("Dun Morogh"))
			assert.equal("\195\134thelwulf", View.find(dex, "\195\166thel")[1].name)
			assert.equal("\195\134thelwulf", View.find(dex, "\195\134THEL")[1].name)
			assert.equal("Gr\195\171ymane", View.find(dex, "GR\195\139Y")[1].name)
		end)

		it("gives a mob's total and the zone it was claimed in most", function()
			local row = View.find(dex, "pillager")[1]
			assert.equal(3, row.count)
			assert.equal("Westfall +1", row.where)
		end)

		it("names a raid creature's raid", function()
			local row = View.find(dex, "core h")[1]
			assert.equal("raid", row.kind)
			assert.equal("Molten Core", row.where)
		end)

		it("treats the text as plain text and needs two letters", function()
			assert.same({}, View.find(dex, "w"))
			assert.same({}, View.find(dex, "%a+"))
			assert.same({}, View.find(dex, nil))
			assert.has_no.errors(function() View.find(dex, "[(") end)
		end)

		it("gives each row the value that identifies it", function()
			assert.equal("Young Wolf", View.find(dex, "young")[1].value)
			assert.equal("Wolfbane-Realm", View.find(dex, "wolfbane")[1].value)
			assert.equal(11671, View.find(dex, "core h")[1].value)
		end)

		it("finds plain text, never a pattern", function()
			dex:recordMob(mob("Thing (Elite)"), ctx("Elwynn Forest"))
			assert.is_table(View.find(dex, "%s[("))
			assert.is_table(View.find(dex, "a."))
			assert.is_table(View.find(dex, "a-"))
			assert.equal("Thing (Elite)", View.find(dex, "(el")[1].name)
		end)

		it("writes the chat lines", function()
			assert.same({
				"2 souls matching \"wolf\":",
				"  Wolfbane \195\1511 \194\183 Rogue",
				"  Young Wolf \195\1511 \194\183 Elwynn Forest",
			}, View.findLines(dex, " wolf ", { ROGUE = "Rogue" }))
			assert.same({ "No soul matching \"murloc\" in your dex." }, View.findLines(dex, "murloc"))
			assert.same({ "Give at least 2 letters to search for." }, View.findLines(dex, "x"))
		end)

		it("counts what it leaves out", function()
			for i = 1, 11 do
				dex:recordMob(mob("Kobold " .. i), ctx("Elwynn Forest"))
			end
			local lines = View.findLines(dex, "kobold")
			assert.equal(1 + View.FIND_LIMIT + 1, #lines)
			assert.equal("  ...and 3 more. Narrow it down.", lines[#lines])
		end)
	end)
end)
