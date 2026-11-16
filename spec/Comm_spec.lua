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
		LoadAddonFile("src/Version.lua", ns)
		LoadAddonFile("src/Comm.lua", ns)
		Comm = ns.Comm
	end)

	it("leaves out entries the decoder would refuse, so the rest stays readable", function()
		local db = fakeDb()
		db.mobs[""] = { points = 1, places = {} }
		db.mobs.Pipe = { name = "|", points = 1, places = {} }
		db.mobs.Broken = false
		db.players[""] = { name = "Nobody", count = 1, points = 1 }
		db.players["Zed-Forever"] = { name = "", count = 1, points = 1 }
		db.raids[7] = { instanceID = 409, count = 1, points = 1 }
		db.raids.junk = { name = "Junk", instanceID = 409, count = 1, points = 1 }
		local back = Comm.decodeDex(Comm.encodeDex(db))
		assert.is_not_nil(back)
		assert.is_not_nil(back.mobs.Wolf)
		assert.is_not_nil(back.mobs.Hogger)
		assert.is_nil(back.mobs.Pipe)
		assert.is_not_nil(back.players["Bob-Forever"])
		assert.is_nil(back.players["Zed-Forever"])
		assert.is_not_nil(back.raids[12118])
		assert.is_nil(back.raids[7])
		assert.is_nil(back.raids[0])
	end)

	it("never writes a number the decoder would refuse", function()
		local db = fakeDb()
		db.mobs.Wolf.minLevel = -1
		db.mobs.Wolf.places["Westfall"].count = -3
		db.mobs.Hogger.points = 5e12
		db.players["Bob-Forever"].count = 0 / 0
		db.raids[12118].instanceID = -409
		local str = Comm.encodeDex(db)
		assert.is_nil(str:find("\t-", 1, true))
		local back = Comm.decodeDex(str)
		assert.is_not_nil(back)
		assert.is_nil(back.mobs.Wolf.minLevel)
		assert.equal(0, back.mobs.Wolf.places["Westfall"].count)
		assert.equal(999999999, back.mobs.Hogger.points)
		assert.equal(0, back.players["Bob-Forever"].count)
		assert.equal(0, back.raids[12118].instanceID)
		assert.equal("S\t1\t0\t0\t0\t0", Comm.encodeSummary({ score = -5, mobs = 0, players = 0, raids = 0 }))
	end)

	it("announces a coming dex with its size", function()
		assert.equal("W\t1\t48000", Comm.encodeComing(48000))
		assert.same({ "W", 48000 }, { Comm.decode("W\t1\t48000") })
		assert.same({ "W", 0 }, { Comm.decode("W\t1\t0") })
		assert.is_nil(Comm.encodeComing(-1))
		assert.is_nil(Comm.encodeComing(Comm.MAX_DEX_BYTES + 1))
		assert.is_nil(Comm.encodeComing("big"))
		for _, junk in ipairs({ "W", "W\t1", "W\t2\t10", "W\t1\t-1", "W\t1\t1.5", "W\t1\tx", "W\t1\t10\t1",
			"W\t1\t" .. (Comm.MAX_DEX_BYTES + 1), "Wx\t1\t10" }) do
			assert.is_nil(Comm.decode(junk), junk)
		end
	end)

	it("tells its version, but only a real one", function()
		assert.equal("V\t1\tv1.4.0", Comm.encodeVersion("v1.4.0"))
		assert.equal("V\t1\tv1.4.0-beta.1", Comm.encodeVersion("v1.4.0-beta.1"))
		assert.is_nil(Comm.encodeVersion("dev"))
		assert.is_nil(Comm.encodeVersion(nil))
		assert.same({ "V", "v1.4.0" }, { Comm.decode("V\t1\tv1.4.0") })
		assert.same({ "V", "1.5.2" }, { Comm.decode("V\t1\t1.5.2") })
		for _, junk in ipairs({ "V", "V\t1", "V\t2\tv1.4.0", "V\t1\tdev", "V\t1\t", "V\t1\tv1.4.0\tx",
			"V\t1\tv1.4.0|cffff0000", "V\t1\t" .. string.rep("9", 40) }) do
			assert.is_nil(Comm.decode(junk), junk)
		end
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
		assert.is_nil(Comm.decodeSummary("S\t1\t-500\t5\t5\t5"))
		assert.is_nil(Comm.decodeSummary("S\t1\t1234567890\t5\t5\t5"))
		assert.equal(999999999, Comm.decodeSummary("S\t1\t999999999\t5\t5\t5").score)
		assert.is_nil(Comm.decodeDex("D\t1\nX\t1\t2\tn\t-1\t1\t1"))
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

	it("sends each soul's full worth, and the copy is scored at face value", function()
		local db = { mobs = {}, places = {}, players = {}, raids = {} }
		db.mobs.Wolf = { name = "Wolf", classification = "normal", points = 1, places = { Z = { count = 25 } } }
		db.players["Bob-R"] = { name = "Bob", count = 3, points = 10, bonus = 2 }
		db.raids[12118] = { name = "Lucifron", instanceID = 409, count = 3, points = 25, known = true }
		local mine = ns.Dex.new(db)
		local d = Comm.decodeDex(Comm.encodeDex(db))
		assert.is_true(d.flat)
		assert.equal(3, d.mobs.Wolf.points)
		assert.equal(12, d.players["Bob-R"].points)
		assert.equal(75, d.raids[12118].points)
		assert.equal(mine:score(), ns.Dex.new(d):score())
	end)

	it("handles an empty dex", function()
		local d = Comm.decodeDex(Comm.encodeDex({}))
		assert.same({ mobs = {}, places = {}, players = {}, raids = {}, flat = true }, d)
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
