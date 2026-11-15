describe("Milestones", function()
	local ns, db, dex

	local function ctx()
		return { time = 1000, myLevel = 20, zone = "Elwynn Forest", group = "Eastern Kingdoms" }
	end

	local function mob(name)
		return { name = name, level = 10, classification = "normal" }
	end

	local function addMobs(n)
		for i = 1, n do
			dex:recordMob(mob("Mob" .. i), ctx())
		end
	end

	local function addPlayers(n)
		for i = 1, n do
			dex:recordPlayer({ name = "P" .. i, realm = "R", level = 5 }, ctx())
		end
	end

	local function byId(items)
		local out = {}
		for _, item in ipairs(items) do
			out[item.id] = item
		end
		return out
	end

	before_each(function()
		ns = {
			RaidData = {
				{ key = "BD", name = "The Barrow Deeps", tbd = true, mobs = {} },
				{
					key = "MC",
					name = "Molten Core",
					instanceID = 409,
					mobs = { { id = 12118, name = "Lucifron", boss = true }, { id = 11671, name = "Core Hound" } },
				},
				{ key = "EMPTY", name = "Empty Raid", instanceID = 1, mobs = {} },
			},
		}
		LoadAddonFile("src/Raids.lua", ns)
		LoadAddonFile("src/Points.lua", ns)
		LoadAddonFile("src/Dex.lua", ns)
		LoadAddonFile("src/Milestones.lua", ns)
		db = {}
		dex = ns.Dex.new(db)
	end)

	it("earns nothing on an empty dex, even for a raid with no known mobs", function()
		assert.same({}, ns.Milestones.check(dex, 5))
		assert.is_nil(db.milestones.raid_EMPTY)
		assert.is_nil(db.milestones.raids_all)
	end)

	it("earns mobs_10 quietly, once", function()
		addMobs(10)
		local got = ns.Milestones.check(dex, 5)
		assert.equal(1, #got)
		assert.equal("mobs_10", got[1].id)
		assert.equal("10 unique mobs", got[1].text)
		assert.equal("First Harvest", got[1].title)
		assert.equal("First Harvest (10 unique mobs)", ns.Milestones.label(got[1]))
		assert.equal("Big one", ns.Milestones.label({ text = "Big one" }))
		assert.is_false(got[1].announce)
		assert.equal(5, db.milestones.mobs_10)
		assert.same({}, ns.Milestones.check(dex, 6))
		assert.equal(5, db.milestones.mobs_10)
	end)

	it("names every milestone", function()
		for _, item in ipairs(ns.Milestones.list(dex)) do
			assert.equal("string", type(item.title), item.id)
			assert.is_true(#item.title > 0, item.id)
			assert.is_truthy(({ Mobs = true, Players = true, Raids = true })[item.group], item.id)
		end
	end)

	it("returns several milestones crossed at once and announces from 100", function()
		addMobs(100)
		local got = byId(ns.Milestones.check(dex, 5))
		assert.is_truthy(got.mobs_50)
		assert.is_false(got.mobs_50.announce)
		assert.is_true(got.mobs_100.announce)
		assert.is_nil(got.mobs_250)
	end)

	it("announces players from 25", function()
		addPlayers(1)
		local got = ns.Milestones.check(dex, 5)
		assert.equal("players_1", got[1].id)
		assert.equal("First player soul", got[1].text)
		assert.equal("First Blood", got[1].title)
		assert.is_false(got[1].announce)
		addPlayers(25)
		got = byId(ns.Milestones.check(dex, 6))
		assert.equal("10 player souls", got.players_10.text)
		assert.is_false(got.players_10.announce)
		assert.is_true(got.players_25.announce)
	end)

	it("earns a raid but not raids_all", function()
		dex:recordRaid(mob("Lucifron"), ctx(), 409, 12118)
		dex:recordRaid(mob("Core Hound"), ctx(), 409, 11671)
		local got = byId(ns.Milestones.check(dex, 5))
		assert.equal("Molten Core Drained", got.raid_MC.title)
		assert.equal("every soul", got.raid_MC.text)
		assert.is_true(got.raid_MC.announce)
		assert.is_nil(got.raid_EMPTY)
		assert.is_nil(got.raids_all)
	end)

	it("leaves TBD raids out of the raid milestones", function()
		local ids = {}
		for _, item in ipairs(ns.Milestones.list(dex)) do
			ids[item.id] = item
		end
		assert.is_nil(ids.raid_BD)
		assert.equal(2, ids.raids_all.goal) -- Molten Core and Empty Raid; not the TBD one
	end)

	it("earns raids_all when every raid in the list is complete", function()
		ns.RaidData[3] = nil
		dex:recordRaid(mob("Lucifron"), ctx(), 409, 12118)
		dex:recordRaid(mob("Core Hound"), ctx(), 409, 11671)
		local got = byId(ns.Milestones.check(dex, 5))
		assert.equal("Raid Reaper", got.raids_all.title)
		assert.is_true(got.raids_all.announce)
	end)

	it("lists unearned items with progress and goal", function()
		addMobs(3)
		dex:recordRaid(mob("Lucifron"), ctx(), 409, 12118)
		local items = byId(ns.Milestones.list(dex))
		assert.is_nil(items.mobs_10.earned)
		assert.equal(4, items.mobs_10.progress)
		assert.equal(10, items.mobs_10.goal)
		assert.equal(1, items.raid_MC.progress)
		assert.equal(2, items.raid_MC.goal)
		assert.equal(0, items.raids_all.progress)
		assert.equal(2, items.raids_all.goal)
		addMobs(10)
		ns.Milestones.check(dex, 7)
		assert.equal(7, byId(ns.Milestones.list(dex)).mobs_10.earned)
	end)
end)
