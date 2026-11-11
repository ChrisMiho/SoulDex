describe("Comm", function()
	local ns, Comm

	local function fakeDb()
		return {
			mobs = {
				Wolf = {
					name = "Wolf", classification = "normal", creatureType = "Beast", family = "Wolf",
					minLevel = 3, maxLevel = 8, points = 1, first = 5, last = 9,
					places = { ["Elwynn Forest"] = { count = 4, x = 1, y = 2 }, ["Westfall"] = { count = 2 } },
				},
				Hogger = {
					name = "Hogger", classification = "rare", creatureType = "Humanoid",
					minLevel = 11, maxLevel = 11, points = 10,
					places = { ["Elwynn Forest"] = { count = 1 } },
				},
			},
			places = {
				["Elwynn Forest"] = { group = "Eastern Kingdoms" },
				["Westfall"] = { group = "Eastern Kingdoms" },
			},
			players = {
				["Bob-Forever"] = {
					name = "Bob", realm = "Forever", class = "MAGE", race = "Human", count = 2, points = 3, places = {},
				},
			},
			raids = {
				[12118] = { name = "Lucifron", instanceID = 409, count = 1, points = 10, known = true },
				[99999] = { name = "Mystery", instanceID = 409, count = 2, points = 1, known = false },
			},
		}
	end

	before_each(function()
		ns = { RaidData = {} }
		LoadAddonFile("src/Raids.lua", ns)
		LoadAddonFile("src/Points.lua", ns)
		LoadAddonFile("src/Dex.lua", ns)
		LoadAddonFile("src/Comm.lua", ns)
		Comm = ns.Comm
	end)

	it("has the prefix and version", function()
		assert.equal("SoulDex", Comm.PREFIX)
		assert.equal(1, Comm.VERSION)
	end)

	it("round-trips a summary", function()
		local s = { score = 120, mobs = 30, players = 4, raids = 2 }
		local str = Comm.encodeSummary(s)
		assert.equal("S\t1\t120\t30\t4\t2", str)
		assert.same(s, Comm.decodeSummary(str))
		local t, payload = Comm.decode(str)
		assert.equal("S", t)
		assert.same(s, payload)
	end)

	it("rejects unknown versions", function()
		assert.is_nil(Comm.decodeSummary("S\t2\t1\t1\t1\t1"))
		assert.is_nil(Comm.decode("S\t2\t1\t1\t1\t1"))
		assert.is_nil(Comm.decodeDex("D\t2\nX\t1\t2\tn\t1\t1\t1"))
		assert.is_nil(Comm.decode("Q\t2"))
	end)

	it("rejects malformed summaries", function()
		assert.is_nil(Comm.decodeSummary("S\t1\t5\t5"))
		assert.is_nil(Comm.decodeSummary("S\t1\ta\t5\t5\t5"))
		assert.is_nil(Comm.decodeSummary("S\t1\t1.5\t5\t5\t5"))
		assert.is_nil(Comm.decodeSummary(nil))
		assert.is_nil(Comm.decodeSummary(42))
	end)

	it("rejects garbage without raising", function()
		assert.is_nil(Comm.decode("hello"))
		assert.is_nil(Comm.decode(""))
		assert.is_nil(Comm.decode(nil))
		assert.is_nil(Comm.decodeDex("hello"))
		assert.is_nil(Comm.decodeDex(nil))
	end)

	it("encodes and decodes requests", function()
		for _, kind in ipairs({ "Q", "R" }) do
			local t, payload = Comm.decode(Comm.encodeRequest(kind))
			assert.equal(kind, t)
			assert.is_true(payload)
		end
		assert.is_nil(Comm.encodeRequest("Z"))
	end)

	it("round-trips a dex", function()
		local db = fakeDb()
		local str = Comm.encodeDex(db)
		assert.equal("D\t1", str:match("^[^\n]*"))
		local t, decoded = Comm.decode(str)
		assert.equal("D", t)
		assert.same(decoded, Comm.decodeDex(str))
		local a, b = ns.Dex.new(db), ns.Dex.new(decoded)
		assert.equal(4, a:uniqueMobs())
		assert.equal(a:uniqueMobs(), b:uniqueMobs())
		assert.equal(a:uniquePlayers(), b:uniquePlayers())
		assert.equal(a:score(), b:score())
	end)

	it("rebuilds the shapes the readers use", function()
		local d = Comm.decodeDex(Comm.encodeDex(fakeDb()))
		assert.equal(4, d.mobs.Wolf.places["Elwynn Forest"].count)
		assert.equal(2, d.mobs.Wolf.places["Westfall"].count)
		assert.equal(3, d.mobs.Wolf.minLevel)
		assert.equal(8, d.mobs.Wolf.maxLevel)
		assert.equal("Wolf", d.mobs.Wolf.family)
		assert.is_nil(d.mobs.Hogger.family)
		assert.equal("Eastern Kingdoms", d.places["Elwynn Forest"].group)
		assert.equal("MAGE", d.players["Bob-Forever"].class)
		assert.equal(2, d.players["Bob-Forever"].count)
		assert.is_true(d.raids[12118].known)
		assert.is_false(d.raids[99999].known)
		assert.equal(409, d.raids[12118].instanceID)
		assert.is_nil(d.mobs.Wolf.first)
	end)

	it("handles an empty dex", function()
		local d = Comm.decodeDex(Comm.encodeDex({}))
		assert.same({ mobs = {}, places = {}, players = {}, raids = {} }, d)
	end)

	it("cleans tabs, newlines and pipes from names", function()
		local db = fakeDb()
		db.mobs["Bad\tWolf"] =
			{ name = "Bad\tWo\nlf|x", classification = "normal", points = 1, places = { Z = { count = 1 } } }
		local d = Comm.decodeDex(Comm.encodeDex(db))
		assert.is_not_nil(d.mobs["BadWolfx"])
		assert.is_nil(d.mobs["Bad\tWolf"])
	end)

	it("rejects empty names in any record", function()
		assert.is_nil(Comm.decodeDex("D\t1\nX\t999\t409\t\t1\t1\t0"))
		assert.is_nil(Comm.decodeDex("D\t1\nP\tBob-R\t\tMAGE\tHuman\t1\t3"))
		assert.is_nil(Comm.decodeDex("D\t1\nM\t\tnormal\tBeast\tWolf\t1\t2\t1\tZ\tG\t1"))
		-- a name that is empty once cleaned counts as empty
		assert.is_nil(Comm.decodeDex("D\t1\nX\t999\t409\t|\t1\t1\t0"))
		local kind, db = Comm.decode("D\t1\nX\t998\t409\tZed\t1\t1\t0")
		assert.equal("D", kind)
		assert.equal("Zed", db.raids[998].name)
	end)

	it("cleans pipes from every decoded text field", function()
		local d = Comm.decodeDex(
			"D\t1\nM\tWo|cffff0000lf\tnor|mal\tBe|ast\tWo|lf\t1\t2\t1\tEl|wynn\tEast|ern\t3"
			.. "\nP\tBob|-R\tB|ob\tMA|GE\tHu|man\t1\t3"
			.. "\nX\t5\t409\tLuci|fron\t1\t1\t1")
		local m = d.mobs["Wocffff0000lf"]
		assert.equal("normal", m.classification)
		assert.equal("Beast", m.creatureType)
		assert.equal("Wolf", m.family)
		assert.equal(3, m.places["Elwynn"].count)
		assert.equal("Eastern", d.places["Elwynn"].group)
		assert.equal("Bob", d.players["Bob-R"].name)
		assert.equal("MAGE", d.players["Bob-R"].class)
		assert.equal("Human", d.players["Bob-R"].race)
		assert.equal("Lucifron", d.raids[5].name)
	end)

	it("rejects truncated payloads", function()
		local str = Comm.encodeDex(fakeDb())
		local cut = str:sub(1, math.floor(#str / 2))
		local ok, res = pcall(Comm.decodeDex, cut)
		assert.is_true(ok)
		assert.is_nil(res)
		assert.is_nil(Comm.decodeDex("D\t1\nM\tWolf\tnormal"))
		assert.is_nil(Comm.decodeDex("D\t1\nQ\tnonsense"))
		assert.is_nil(Comm.decodeDex("D\t1\nX\t1\t2\tn\tx\t1\t1"))
	end)
end)
