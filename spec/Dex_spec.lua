describe("Dex", function()
	local ns, db, dex

	local function ctx(zone, extra)
		local c = { time = 1000, myLevel = 20, zone = zone or "Elwynn Forest", group = "Eastern Kingdoms", x = 10, y = 20 }
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
			},
		}
		LoadAddonFile("src/Raids.lua", ns)
		LoadAddonFile("src/Points.lua", ns)
		LoadAddonFile("src/Dex.lua", ns)
		db = {}
		dex = ns.Dex.new(db)
	end)

	it("creates the missing subtables", function()
		for _, k in ipairs({ "mobs", "places", "players", "raids", "milestones" }) do
			assert.equal("table", type(db[k]))
		end
	end)

	it("records a new mob", function()
		local r = dex:recordMob(mob("Wolf"), ctx())
		assert.is_true(r.isNew)
		assert.equal(1, r.points)
		assert.equal(1, r.total)
		assert.equal("mob", r.kind)
		assert.equal(1, dex:uniqueMobs())
		assert.equal(1, dex:score())
		assert.equal("Eastern Kingdoms", db.places["Elwynn Forest"].group)
		assert.equal("Wolf", db.mobs.Wolf.family)
		assert.equal(1000, db.mobs.Wolf.first)
	end)

	it("scores nothing for a repeat catch", function()
		dex:recordMob(mob("Wolf"), ctx())
		local r = dex:recordMob(mob("Wolf"), ctx(nil, { time = 2000 }))
		assert.is_false(r.isNew)
		assert.equal(0, r.points)
		assert.equal(1, r.total) -- still one different soul
		local place = db.mobs.Wolf.places["Elwynn Forest"]
		assert.equal(2, place.count)
		assert.equal(1000, place.first)
		assert.equal(2000, place.last)
		assert.equal(1000, db.mobs.Wolf.first)
		assert.equal(1, dex:score())
	end)

	it("is quiet about a new place for a known mob", function()
		dex:recordMob(mob("Wolf"), ctx())
		local r = dex:recordMob(mob("Wolf"), ctx("Westfall"))
		assert.is_false(r.isNew)
		assert.equal(0, r.points)
		assert.equal(1, r.total)
		assert.equal(1, dex:uniqueMobs())
		assert.equal("Eastern Kingdoms", db.places.Westfall.group)
	end)

	it("total is the dex's unique soul count after the catch, across zones and kinds", function()
		dex:recordMob(mob("Wolf"), ctx())
		dex:recordMob(mob("Boar"), ctx())
		dex:recordMob(mob("Kobold"), ctx("Westfall"))
		assert.equal(4, dex:recordMob(mob("Murloc"), ctx()).total)
		assert.equal(4, dex:recordMob(mob("Wolf"), ctx("Westfall")).total)
		assert.equal(5, dex:recordPlayer({ name = "Bob", realm = "Realm" }, ctx()).total)
		assert.equal(6, dex:recordRaid(mob("Lucifron"), ctx("Molten Core"), 409, 12118).total)
		assert.equal(6, dex:uniqueSouls())
	end)

	it("replaces damaged subtables", function()
		local bad = { mobs = true, places = "x", players = 3, raids = {}, milestones = false }
		local d = ns.Dex.new(bad)
		assert.equal("table", type(bad.mobs))
		assert.equal("table", type(bad.places))
		assert.equal("table", type(bad.players))
		assert.equal("table", type(bad.milestones))
		assert.equal(0, d:uniqueMobs())
	end)

	it("widens the level range", function()
		dex:recordMob(mob("Wolf", { level = 10 }), ctx())
		dex:recordMob(mob("Wolf", { level = 12 }), ctx())
		assert.equal(10, db.mobs.Wolf.minLevel)
		assert.equal(12, db.mobs.Wolf.maxLevel)
		assert.equal(1, dex:uniqueMobs())
	end)

	it("scores elites as 5", function()
		local r = dex:recordMob(mob("Ogre", { classification = "elite" }), ctx())
		assert.equal(5, r.points)
		assert.equal(5, db.mobs.Ogre.points)
	end)

	it("records a player", function()
		local info = { name = "Bob", realm = "Realm", class = "MAGE", race = "Human", guild = "Guild", level = 30 }
		local r = dex:recordPlayer(info, ctx())
		assert.is_true(r.isNew)
		assert.equal(10, r.points)
		assert.equal("player", r.kind)
		assert.equal(1, dex:uniquePlayers())
		info.level = 31
		r = dex:recordPlayer(info, ctx(nil, { time = 3000 }))
		assert.is_false(r.isNew)
		assert.equal(0, r.points)
		local p = db.players["Bob-Realm"]
		assert.equal(2, p.count)
		assert.equal(30, p.firstLevel)
		assert.equal(31, p.lastLevel)
		assert.equal(3000, p.last)
		assert.equal(2, p.places["Elwynn Forest"].count)
		dex:recordPlayer(info, ctx("Westfall"))
		assert.equal(1, p.places.Westfall.count)
		assert.equal(1, dex:uniquePlayers())
		assert.equal(10, dex:score())
	end)

	it("keeps class, race, guild and level when a repeat catch lacks them", function()
		local full = { name = "Bob", realm = "Realm", class = "MAGE", race = "Human", guild = "Guild", level = 30 }
		dex:recordPlayer(full, ctx())
		dex:recordPlayer({ name = "Bob", realm = "Realm" }, ctx(nil, { time = 3000 }))
		local p = db.players["Bob-Realm"]
		assert.equal("MAGE", p.class)
		assert.equal("Human", p.race)
		assert.equal("Guild", p.guild)
		assert.equal(30, p.lastLevel)
		assert.equal(2, p.count)
		full.guild, full.level = "Other", 31
		dex:recordPlayer(full, ctx())
		assert.equal("Other", p.guild)
		assert.equal(31, p.lastLevel)
	end)

	it("uniqueMobs skips entries without a name", function()
		db.raids[1] = { instanceID = 409, count = 1, points = 1 }
		db.raids[2] = { name = "Zed", instanceID = 409, count = 1, points = 1 }
		local ok, n = pcall(dex.uniqueMobs, dex)
		assert.is_true(ok)
		assert.equal(1, n)
	end)

	it("records a raid mob", function()
		local r = dex:recordRaid(mob("Lucifron", { classification = "elite" }), ctx("Molten Core"), 409, 12118)
		assert.is_true(r.isNew)
		assert.equal(25, r.points)
		assert.equal("raid", r.kind)
		local caught, total = dex:raidProgress(409)
		assert.equal(1, caught)
		assert.equal(3, total)
		assert.is_true(db.raids[12118].known)
		assert.equal("elite", db.raids[12118].classification)
		assert.equal("Beast", db.raids[12118].creatureType)
		assert.equal(10, db.raids[12118].minLevel)
		local r2 = dex:recordRaid(mob("Lucifron", { level = 12 }), ctx("Molten Core"), 409, 12118)
		assert.is_false(r2.isNew)
		assert.equal(25, r2.points) -- a boss scores again on every claim
		assert.equal(50, dex:score())
		assert.equal(2, db.raids[12118].count)
		assert.equal(12, db.raids[12118].maxLevel)
	end)

	describe("claiming a soul again", function()
		local DAY = 86400
		local function at(t, zone)
			return ctx(zone, { time = t })
		end

		it("earns a mob mastery stars at 10, 25 and on, each worth points once", function()
			local last
			for i = 1, 10 do
				last = dex:recordMob(mob("Wolf"), at(1000 + i))
				if i > 1 and i < 10 then
					assert.equal(0, last.points)
					assert.is_nil(last.stars)
				end
			end
			assert.equal(1, last.stars)
			assert.equal(1, last.points)
			assert.equal(10, last.count)
			assert.equal(2, dex:score()) -- 1 for the first claim, 1 for the star
			for _ = 11, 25 do
				last = dex:recordMob(mob("Wolf"), at(2000, "Westfall")) -- claims in any zone count
			end
			assert.equal(2, last.stars)
			assert.equal(3, dex:score())
			local stars, count, from, to = dex:stars(db.mobs.Wolf)
			assert.same({ 2, 25, 25, 50 }, { stars, count, from, to })
			assert.equal(2, dex:masteryStars())
		end)

		it("doubles star points for an elite", function()
			for i = 1, 10 do
				dex:recordMob(mob("Hogger", { classification = "elite" }), at(1000 + i))
			end
			assert.equal(5 + 2, dex:score())
		end)

		it("credits claims made before the update: stars come from the saved counts", function()
			db.mobs.Boar = {
				name = "Boar", classification = "normal", points = 1,
				places = { A = { count = 600 }, B = { count = 450 } },
			}
			assert.equal(8, (dex:stars(db.mobs.Boar)))
			assert.equal(1 + 38, dex:score())
			db.raids[12118] = { name = "Lucifron", instanceID = 409, count = 4, points = 25 }
			assert.equal(39 + 100, dex:score())
			assert.is_nil(dex:stars(db.raids[12118]))
		end)

		it("pays a rare again once a day, and never stars it", function()
			local rare = mob("Mor'Ladim", { classification = "rare" })
			assert.equal(10, dex:recordMob(rare, at(DAY * 10 + 5)).points)
			assert.equal(0, dex:recordMob(rare, at(DAY * 10 + 500)).points) -- same day
			assert.equal(2, dex:recordMob(rare, at(DAY * 11 + 5)).points)
			assert.equal(0, dex:recordMob(rare, at(DAY * 11 + 90)).points)
			assert.equal(2, dex:recordMob(rare, at(DAY * 14)).points)
			assert.equal(14, dex:score())
			assert.is_nil(dex:stars(db.mobs["Mor'Ladim"]))
		end)

		it("pays a player again 3 points, once a day for each player", function()
			local bob = { name = "Bob", realm = "Forever", level = 30 }
			local cid = { name = "Cid", realm = "Forever", level = 30 }
			assert.equal(10, dex:recordPlayer(bob, at(DAY * 10)).points)
			assert.equal(0, dex:recordPlayer(bob, at(DAY * 10 + 60)).points)
			assert.equal(10, dex:recordPlayer(cid, at(DAY * 10 + 70)).points)
			assert.equal(3, dex:recordPlayer(bob, at(DAY * 11)).points)
			assert.equal(3, dex:recordPlayer(cid, at(DAY * 11 + 1)).points)
			for i = 1, 20 do
				assert.equal(0, dex:recordPlayer(bob, at(DAY * 11 + 100 + i)).points) -- farming one player pays nothing
			end
			assert.equal(26, dex:score())
			-- a clock that went backwards pays nothing
			assert.equal(0, dex:recordPlayer(bob, at(DAY * 9)).points)
		end)

		it("stars raid trash but not raid bosses", function()
			for i = 1, 10 do
				dex:recordRaid(mob("Core Hound", { classification = "elite" }), at(1000 + i, "Molten Core"), 409, 11671)
			end
			assert.equal(1, (dex:stars(db.raids[11671])))
			assert.equal(5 + 2, dex:score())
		end)

		it("takes a friend's dex at face value", function()
			local theirs = ns.Dex.new({
				flat = true,
				mobs = { Wolf = { name = "Wolf", classification = "normal", points = 31, places = { A = { count = 1000 } } } },
				raids = { [5] = { name = "X", instanceID = 409, count = 3, points = 75 } },
				players = { ["Bob-R"] = { name = "Bob", count = 9, points = 14 } },
			})
			assert.equal(31 + 75 + 14, theirs:score())
			assert.equal(8, (theirs:stars(theirs.db.mobs.Wolf))) -- a well-farmed mob is not mistaken for a boss
			assert.is_nil(theirs:stars(theirs.db.raids[5]))
		end)
	end)

	it("a new raid slot whose name is already a mob gives no total (no repeated Soul #N)", function()
		dex:recordMob(mob("Lucifron"), ctx())
		local r = dex:recordRaid(mob("Lucifron", { classification = "elite" }), ctx("Molten Core"), 409, 12118)
		assert.is_true(r.isNew)
		assert.is_nil(r.total)
		assert.equal(1, dex:uniqueSouls())
		local fresh = dex:recordRaid(mob("Gehennas", { classification = "elite" }), ctx("Molten Core"), 409, 12259)
		assert.equal(2, fresh.total)
	end)

	it("fills raid details missing from an older saved entry on the next catch", function()
		db.raids[12118] = { name = "Lucifron", instanceID = 409, count = 1, points = 25, known = true }
		dex:recordRaid(mob("Lucifron", { classification = "worldboss", creatureType = "Demon", family = nil }),
			ctx("Molten Core"), 409, 12118)
		assert.equal("worldboss", db.raids[12118].classification)
		assert.equal("Demon", db.raids[12118].creatureType)
		assert.equal(10, db.raids[12118].minLevel)
	end)

	it("records an unknown raid npc without counting it in progress", function()
		local r = dex:recordRaid(mob("Mystery", { classification = "elite" }), ctx("Molten Core"), 409, 99999)
		assert.is_true(r.isNew)
		assert.equal(5, r.points)
		assert.is_false(db.raids[99999].known)
		local caught, total = dex:raidProgress(409)
		assert.equal(0, caught)
		assert.equal(3, total)
	end)

	it("counts raid mobs as unique mobs once per name", function()
		dex:recordMob(mob("Core Hound"), ctx())
		dex:recordRaid(mob("Core Hound"), ctx("Molten Core"), 409, 11671)
		assert.equal(1, dex:uniqueMobs())
		dex:recordRaid(mob("Core Rager"), ctx("Molten Core"), 409, 11672)
		assert.equal(2, dex:uniqueMobs())
	end)

	it("counts completed raids", function()
		assert.equal(0, dex:raidsCompleted())
		dex:recordRaid(mob("Lucifron"), ctx("Molten Core"), 409, 12118)
		dex:recordRaid(mob("Core Hound"), ctx("Molten Core"), 409, 11671)
		assert.equal(0, dex:raidsCompleted())
		dex:recordRaid(mob("Core Rager"), ctx("Molten Core"), 409, 11672)
		assert.equal(1, dex:raidsCompleted())
	end)

	it("sums every collection into the score", function()
		dex:recordMob(mob("Wolf"), ctx())
		dex:recordMob(mob("Ogre", { classification = "elite" }), ctx())
		dex:recordPlayer({ name = "Bob", realm = "R", class = "MAGE", race = "Human", level = 5 }, ctx())
		dex:recordRaid(mob("Lucifron"), ctx("Molten Core"), 409, 12118)
		assert.equal(1 + 5 + 10 + 25, dex:score())
	end)

	describe("recordUnknown", function()
		it("creates db.unknown", function()
			assert.equal("table", type(db.unknown))
		end)

		it("counts unknown souls per zone with no points and no unique mob", function()
			local r = dex:recordUnknown(ctx("Westfall", { time = 1000 }))
			assert.same({ isNew = false, points = 0, kind = "unknown" }, r)
			dex:recordUnknown(ctx("Westfall", { time = 2000 }))
			dex:recordUnknown(ctx())
			assert.same({ count = 2, first = 1000, last = 2000, group = "Eastern Kingdoms" }, db.unknown.Westfall)
			assert.equal(1, db.unknown["Elwynn Forest"].count)
			assert.equal(0, dex:uniqueMobs())
			assert.equal(0, dex:uniquePlayers())
			assert.equal(0, dex:score())
			assert.same({}, db.mobs)
		end)

		it("notes the place like a mob catch does", function()
			dex:recordUnknown(ctx("Westfall"))
			assert.equal("Eastern Kingdoms", db.places.Westfall.group)
		end)

		it("keeps working on a dex that never had db.unknown", function()
			local old = { mobs = {}, places = {}, players = {}, raids = {}, milestones = {} }
			local d = ns.Dex.new(old)
			d:recordUnknown(ctx())
			assert.equal(1, old.unknown["Elwynn Forest"].count)
		end)
	end)

	it("keeps today's count and the best day so far", function()
		local DAY = 86400
		for i = 1, 3 do
			dex:recordMob(mob("Wolf" .. i), ctx(nil, { time = DAY * 5 + i }))
		end
		dex:recordPlayer({ name = "Bob", realm = "R", level = 9 }, ctx(nil, { time = DAY * 5 + 50 }))
		assert.same({ day = 5, count = 4, time = DAY * 5 + 1 }, db.today)
		assert.equal(4, db.best.count)
		dex:recordUnknown(ctx(nil, { time = DAY * 6 + 1 })) -- a quieter day doesn't replace the best
		assert.equal(1, db.today.count)
		assert.equal(6, db.today.day)
		assert.equal(4, db.best.count)
		assert.equal(5, db.best.day)
	end)
end)
