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
		assert.equal(1, r.placeCount)
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
		assert.equal(2, r.placeCount)
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
		assert.equal(1, r.placeCount)
		assert.equal(1, dex:uniqueMobs())
		assert.equal("Eastern Kingdoms", db.places.Westfall.group)
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
		local r2 = dex:recordRaid(mob("Lucifron"), ctx("Molten Core"), 409, 12118)
		assert.is_false(r2.isNew)
		assert.equal(0, r2.points)
		assert.equal(2, db.raids[12118].count)
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
end)
