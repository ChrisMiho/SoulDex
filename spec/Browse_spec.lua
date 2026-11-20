describe("Browse", function()
	local ns, Browse, dex, friend, you

	local function ctx(zone, time)
		return { time = time or 1000, myLevel = 20, zone = zone, group = "Eastern Kingdoms", x = 10, y = 20 }
	end

	local function mob(name, extra)
		local m = { name = name, level = 10, classification = "normal", creatureType = "Beast", family = "Wolf" }
		for k, v in pairs(extra or {}) do
			m[k] = v
		end
		return m
	end

	local function player(name, class)
		return { name = name, realm = "Realm", level = 38, class = class, race = "Orc", guild = "Guildies" }
	end

	local function claim(d, name, zone, times, time, extra)
		for i = 1, times do
			d:recordMob(mob(name, extra), ctx(zone, (time or 1000) + i))
		end
	end

	local function names(rows)
		local out = {}
		for i, row in ipairs(rows) do
			out[i] = row.name
		end
		return out
	end

	before_each(function()
		ns = {
			RaidData = {
				{ key = "MC", name = "Molten Core", instanceID = 409, mobs = {
					{ id = 12118, name = "Lucifron", boss = true },
					{ id = 11671, name = "Core Hound" },
				} },
			},
		}
		LoadAddonFile("src/Raids.lua", ns)
		LoadAddonFile("src/Points.lua", ns)
		LoadAddonFile("src/Dex.lua", ns)
		LoadAddonFile("src/Flavour.lua", ns)
		LoadAddonFile("src/Milestones.lua", ns)
		LoadAddonFile("src/Friends.lua", ns)
		LoadAddonFile("src/View.lua", ns)
		LoadAddonFile("src/Browse.lua", ns)
		Browse = ns.Browse
		dex = ns.Dex.new({})
		friend = ns.Dex.new({})
		you = ns.Dex.new({})
	end)

	describe("sorts", function()
		it("lists the choices per tab", function()
			assert.same({ "name", "count", "recent", "rarity" }, Browse.sorts("Mobs", false))
			assert.same({ "name", "count", "rarity" }, Browse.sorts("Mobs", true))
			assert.equal("count", Browse.sorts("Players", false)[1])
			assert.same({}, Browse.sorts("Raids", false))
		end)
	end)

	describe("filters", function()
		it("lists the choices per tab", function()
			local own = Browse.filters("Mobs", false)
			assert.equal("all", own[1])
			assert.equal(4, #own)
			assert.same({}, Browse.filters("Players", false))
			assert.equal(5, #Browse.filters("Raids", true))
			assert.same({}, Browse.filters("Me", true))
		end)
	end)

	describe("valid", function()
		it("falls back to the first choice", function()
			assert.equal("name", Browse.valid(Browse.sorts("Mobs", true), "recent"))
			assert.equal("name", Browse.valid(Browse.sorts("Mobs", true), 42))
			assert.equal("count", Browse.valid(Browse.sorts("Mobs", true), "count"))
			assert.is_nil(Browse.valid({}, "x"))
		end)
	end)

	describe("step", function()
		it("wraps both ways", function()
			local list = Browse.sorts("Mobs", false)
			assert.equal("name", Browse.step(list, "rarity"))
			assert.equal("rarity", Browse.step(list, "name", true))
			assert.equal("count", Browse.step(list, "name"))
		end)

		it("steps from the first choice for a junk id", function()
			local list = Browse.sorts("Mobs", false)
			assert.equal("count", Browse.step(list, "junk"))
			assert.is_nil(Browse.step({}, "junk"))
		end)
	end)

	describe("label", function()
		it("names every choice", function()
			assert.equal("A\226\128\147Z", Browse.label("name"))
			assert.equal("Most claimed", Browse.label("count"))
			assert.equal("Newest", Browse.label("recent"))
			assert.equal("Rarest", Browse.label("rarity"))
			assert.equal("All", Browse.label("all", false))
			assert.equal("Their dex", Browse.label("all", true))
			assert.equal("Rare and elite", Browse.label("rare"))
			assert.equal("Mastered", Browse.label("mastered"))
			assert.equal("Not mastered", Browse.label("unmastered"))
			assert.equal("Differences", Browse.label("diff"))
			assert.equal("Missing", Browse.label("missing"))
			assert.equal("Only mine", Browse.label("mine"))
			assert.equal("Shared", Browse.label("shared"))
		end)
	end)

	describe("mobs", function()
		it("sums a mob over every place for the All row, without unknown souls", function()
			claim(dex, "Wolf", "Elwynn Forest", 2, 1000)
			claim(dex, "Wolf", "Westfall", 3, 2000)
			dex:recordUnknown(ctx("Elwynn Forest"))
			local rows = Browse.mobs(dex, Browse.ALL)
			assert.equal(1, #rows)
			assert.equal("Wolf", rows[1].name)
			assert.equal(5, rows[1].count)
			assert.equal(2003, rows[1].last)
			assert.is_nil(rows[1].side)
			assert.is_nil(rows[1].unknown)
		end)

		it("gives one place's rows with last, and the unknown row", function()
			claim(dex, "Wolf", "Elwynn Forest", 2, 1000)
			dex:recordUnknown(ctx("Elwynn Forest"))
			local rows = Browse.mobs(dex, "Elwynn Forest")
			assert.equal(2, #rows)
			assert.equal(2, rows[1].count)
			assert.equal(1002, rows[1].last)
			assert.equal("normal", rows[1].classification)
			assert.is_nil(rows[1].side)
			assert.is_true(rows[2].unknown)
		end)

		it("carries mastery stars", function()
			claim(dex, "Wolf", "Elwynn Forest", ns.Points.STAR_STEPS[1])
			claim(dex, "Boar", "Elwynn Forest", 1)
			local rows = Browse.mobs(dex, Browse.ALL)
			table.sort(rows, function(a, b)
				return a.name < b.name
			end)
			assert.is_nil(rows[1].stars)
			assert.is_true(rows[2].stars >= 1)
		end)

		it("marks sides against the viewer's dex", function()
			claim(friend, "Wolf", "Elwynn Forest", 2)
			claim(friend, "Hogger", "Elwynn Forest", 1)
			claim(you, "Wolf", "Westfall", 1)
			claim(you, "Boar", "Elwynn Forest", 4, 1000, { classification = "elite" })
			local rows = Browse.mobs(friend, "Elwynn Forest", you)
			local by = {}
			for _, row in ipairs(rows) do
				by[row.name] = row
			end
			assert.equal("shared", by.Wolf.side)
			assert.equal("missing", by.Hogger.side)
			assert.equal("mine", by.Boar.side)
			assert.equal(4, by.Boar.count)
			assert.equal("elite", by.Boar.classification)
			assert.is_nil(by.Boar.stars)
			assert.equal(3, #rows)
		end)

		it("leaves out a shared mob the friend has not met at that place", function()
			claim(friend, "Wolf", "Elwynn Forest", 2)
			claim(you, "Wolf", "Westfall", 1)
			assert.same({}, Browse.mobs(friend, "Westfall", you))
		end)

		it("adds the viewer's own mobs from anywhere to the All row", function()
			claim(friend, "Wolf", "Elwynn Forest", 1)
			claim(you, "Boar", "Westfall", 2)
			local rows = Browse.mobs(friend, Browse.ALL, you)
			assert.equal(2, #rows)
			local mine
			for _, row in ipairs(rows) do
				if row.side == "mine" then
					mine = row
				end
			end
			assert.equal("Boar", mine.name)
			assert.equal(2, mine.count)
		end)
	end)

	describe("players", function()
		it("filters by class, or gives everyone for All", function()
			dex:recordPlayer(player("Anna", "MAGE"), ctx("Elwynn Forest"))
			dex:recordPlayer(player("Bob", "WARRIOR"), ctx("Elwynn Forest"))
			assert.equal(2, #Browse.players(dex, Browse.ALL))
			local rows = Browse.players(dex, "MAGE")
			assert.equal(1, #rows)
			assert.equal("Anna", rows[1].name)
			assert.equal("Anna-Realm", rows[1].key)
			assert.equal("MAGE", rows[1].class)
			assert.equal(1, rows[1].count)
			assert.is_nil(rows[1].side)
		end)

		it("marks sides by key", function()
			friend:recordPlayer(player("Anna", "MAGE"), ctx("Elwynn Forest"))
			friend:recordPlayer(player("Bob", "WARRIOR"), ctx("Elwynn Forest"))
			you:recordPlayer(player("Anna", "MAGE"), ctx("Westfall"))
			you:recordPlayer(player("Cy", "MAGE"), ctx("Westfall"))
			local by = {}
			for _, row in ipairs(Browse.players(friend, Browse.ALL, you)) do
				by[row.key] = row.side
			end
			assert.same({ ["Anna-Realm"] = "shared", ["Bob-Realm"] = "missing", ["Cy-Realm"] = "mine" }, by)
			assert.equal(2, #Browse.players(friend, "MAGE", you))
		end)
	end)

	describe("apply", function()
		local function row(name, extra)
			local r = { name = name, count = 1, classification = "normal" }
			for k, v in pairs(extra or {}) do
				r[k] = v
			end
			return r
		end

		it("keeps rare and elite rows only under rare", function()
			local rows = {
				row("A", { classification = "elite" }), row("B", { classification = "rare" }),
				row("C", { classification = "rareelite" }), row("D", { classification = "worldboss" }),
				row("E"), row("F", { classification = "trivial" }),
			}
			assert.same({ "A", "B", "C", "D" }, names(Browse.apply(rows, "rare", "name")))
		end)

		it("splits mastered and not mastered on stars", function()
			local rows = { row("A", { stars = 2 }), row("B"), row("C", { stars = 1 }) }
			assert.same({ "A", "C" }, names(Browse.apply(rows, "mastered", "name")))
			assert.same({ "B" }, names(Browse.apply(rows, "unmastered", "name")))
		end)

		it("filters by side", function()
			local rows = {
				row("A", { side = "missing" }), row("B", { side = "mine" }), row("C", { side = "shared" }),
			}
			assert.same({ "A", "B" }, names(Browse.apply(rows, "diff", "name")))
			assert.same({ "A" }, names(Browse.apply(rows, "missing", "name")))
			assert.same({ "B" }, names(Browse.apply(rows, "mine", "name")))
			assert.same({ "C" }, names(Browse.apply(rows, "shared", "name")))
		end)

		it("all is the dex on screen: a soul only the viewer has is left out, a raid's roster row is not", function()
			local rows = {
				row("A", { side = "missing" }), row("B", { side = "mine" }), row("C", { side = "shared" }),
				row("D", { side = "mine", known = true }), row("E", { side = "mine", known = false }),
				row("F"),
			}
			assert.same({ "A", "C", "D", "F" }, names(Browse.apply(rows, "all", "name")))
		end)

		it("drops rows without a side under the compare filters", function()
			local rows = { row("A"), row("B") }
			for _, filter in ipairs({ "diff", "missing", "mine", "shared" }) do
				assert.same({}, Browse.apply(rows, filter, "name"))
			end
		end)

		it("keeps the unknown row last under All and nowhere else", function()
			local rows = {
				row("Unknown soul", { unknown = true, count = 99 }),
				row("B", { count = 1, last = 5 }), row("A", { count = 2 }),
			}
			for _, sort in ipairs({ "name", "count", "recent", "rarity" }) do
				local out = Browse.apply(rows, "all", sort)
				assert.equal(3, #out)
				assert.is_true(out[3].unknown)
			end
			assert.same({}, Browse.apply(rows, "rare", "name"))
			assert.same({}, Browse.apply(rows, "diff", "name"))
			assert.same({}, Browse.apply(rows, "mastered", "name"))
			assert.same({ "A", "B" }, names(Browse.apply(rows, "unmastered", "name")))
		end)

		it("sorts by count descending, ties by name", function()
			local rows = { row("B", { count = 3 }), row("A", { count = 3 }), row("C", { count = 9 }) }
			assert.same({ "C", "A", "B" }, names(Browse.apply(rows, "all", "count")))
		end)

		it("sorts by name ascending, ties by key", function()
			local rows = { row("B", { key = "b2" }), row("A"), row("B", { key = "b1" }) }
			local out = Browse.apply(rows, "all", "name")
			assert.same({ "A", "B", "B" }, names(out))
			assert.equal("b1", out[2].key)
		end)

		it("sorts newest first with undated rows last", function()
			local rows = { row("A"), row("B", { last = 10 }), row("C", { last = 20 }), row("D", { last = 10 }) }
			assert.same({ "C", "B", "D", "A" }, names(Browse.apply(rows, "all", "recent")))
		end)

		it("sorts rarest first", function()
			local rows = {
				row("N"), row("E", { classification = "elite" }), row("R", { classification = "rare" }),
				row("W", { classification = "worldboss" }), row("X", { classification = "rareelite" }),
			}
			assert.same({ "W", "R", "X", "E", "N" }, names(Browse.apply(rows, "all", "rarity")))
		end)

		it("keeps the given order with no sort and leaves the input alone", function()
			local rows = { row("C"), row("A"), row("B") }
			local out = Browse.apply(rows, "all", nil)
			assert.same({ "C", "A", "B" }, names(out))
			assert.not_equal(rows, out)
			Browse.apply(rows, "all", "name")
			assert.same({ "C", "A", "B" }, names(rows))
		end)
	end)

	describe("counts", function()
		it("counts mobs by name", function()
			claim(friend, "Wolf", "Elwynn Forest", 1)
			claim(friend, "Hogger", "Elwynn Forest", 1)
			claim(you, "Wolf", "Westfall", 1)
			claim(you, "Boar", "Westfall", 1)
			assert.same({ missing = 1, mine = 1, shared = 1 }, Browse.counts(friend, you, "Mobs"))
		end)

		it("counts players by key", function()
			friend:recordPlayer(player("Anna", "MAGE"), ctx("Elwynn Forest"))
			friend:recordPlayer(player("Bob", "MAGE"), ctx("Elwynn Forest"))
			you:recordPlayer(player("Anna", "MAGE"), ctx("Elwynn Forest"))
			assert.same({ missing = 1, mine = 0, shared = 1 }, Browse.counts(friend, you, "Players"))
		end)

		it("counts raid creatures by NPC ID", function()
			friend:recordRaid(mob("Lucifron"), ctx("Molten Core"), 409, 12118)
			friend:recordRaid(mob("Core Hound"), ctx("Molten Core"), 409, 11671)
			you:recordRaid(mob("Core Hound"), ctx("Molten Core"), 409, 11671)
			assert.same({ missing = 1, mine = 0, shared = 1 }, Browse.counts(friend, you, "Raids"))
		end)

		it("counts nothing for other tabs", function()
			assert.same({ missing = 0, mine = 0, shared = 0 }, Browse.counts(friend, you, "Me"))
		end)
	end)

	describe("size", function()
		it("counts the mobs with a place and every player; raid souls are not mobs here", function()
			claim(dex, "Wolf", "Elwynn Forest", 2)
			claim(dex, "Kobold", "Westfall", 1)
			dex:recordRaid({ name = "Lucifron", classification = "elite" }, ctx("Molten Core"), 409, 12118)
			dex:recordPlayer(player("Stab", "ROGUE"), ctx("Elwynn Forest"))
			dex.db.mobs.Ghost = { name = "Ghost", places = {} } -- no place: not listed
			assert.equal(2, Browse.size(dex, "Mobs"))
			assert.equal(#Browse.mobs(dex, Browse.ALL), Browse.size(dex, "Mobs"))
			assert.equal(1, Browse.size(dex, "Players"))
			assert.equal(0, Browse.size(dex, "Raids"))
			assert.equal(0, Browse.size(ns.Dex.new({}), "Mobs"))
		end)
	end)
end)
