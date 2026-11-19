describe("Friends", function()
	local ns, Friends

	before_each(function()
		ns = {}
		LoadAddonFile("src/Friends.lua", ns)
		Friends = ns.Friends
	end)

	local function sum(score, mobs, players, raids)
		return { score = score, mobs = mobs or 0, players = players or 0, raids = raids or 0 }
	end

	it("keeps two-part names (WoW: Forever)", function()
		assert.equal("Forgot Shards", Friends.normalise("Forgot Shards"))
		assert.equal("Forgot Shards", Friends.normalise("forgot shards"))
		assert.equal("Forgot Shards", Friends.normalise("FORGOT SHARDS-Realm"))
		assert.equal("Forgot Shards", Friends.fullName("Forgot", "Shards"))
		assert.equal("Bob", Friends.fullName("Bob", nil))
		assert.equal("Bob", Friends.fullName("Bob", ""))
		assert.is_nil(Friends.fullName(nil, "Shards"))
	end)

	it("tidies saved keys: re-spells old ones and drops yourself", function()
		local store = {
			["Forgot shards"] = { added = false, seen = 5 },
			["Bob jones"] = { added = true, seen = 1 },
			["Bob Jones"] = { added = false, seen = 9, summary = { score = 3 } },
			["Ann"] = { added = true },
		}
		Friends.tidy(store, "Forgot Shards")
		assert.is_nil(store["Forgot shards"])
		assert.is_nil(store["Forgot Shards"])
		assert.is_nil(store["Bob jones"])
		assert.is_true(store["Bob Jones"].added)
		assert.equal(9, store["Bob Jones"].seen)
		assert.equal(3, store["Bob Jones"].summary.score)
		assert.is_true(store["Ann"].added)
	end)

	it("tidy forgets people you never added and haven't seen for 30 days", function()
		local day = 86400
		local now = 100 * day
		local store = {
			Old = { added = false, seen = now - 31 * day, summary = { score = 1 } },
			Edge = { added = false, seen = now - 30 * day },
			Recent = { added = false, seen = now - 5 * day },
			Pal = { added = true, seen = now - 300 * day },
			Waiting = { added = true },
			Blank = { added = false },
			["old jones"] = { added = false, seen = now - 40 * day },
		}
		Friends.tidy(store, "Fel", now)
		assert.is_nil(store.Old)
		assert.is_nil(store["Old Jones"])
		assert.is_not_nil(store.Edge)
		assert.is_not_nil(store.Recent)
		assert.is_not_nil(store.Pal)
		assert.is_not_nil(store.Waiting)
		assert.is_not_nil(store.Blank) -- no last-seen time: left alone
		-- without a clock nothing expires
		local same = { Old = { added = false, seen = 1 } }
		Friends.tidy(same, "Fel")
		assert.is_not_nil(same.Old)
	end)

	it("normalises names", function()
		assert.equal("Stabbyface", Friends.normalise("stabbyface"))
		assert.equal("Stabbyface", Friends.normalise("Stabbyface-Forever"))
		assert.equal("Stabbyface", Friends.normalise("STABBYFACE"))
		assert.is_nil(Friends.normalise(""))
		assert.is_nil(Friends.normalise("-Realm"))
		assert.is_nil(Friends.normalise(nil))
	end)

	it("matches names whose first letter is non-ASCII", function()
		assert.equal(Friends.normalise("\195\139lric"), Friends.normalise("\195\171lric"))
		assert.equal(Friends.normalise("\195\171lric-Forever"), Friends.normalise("\195\139LRIC"))
		assert.equal("\195\139lric", Friends.normalise("\195\171lric"))
		-- the multiplication sign is not a letter and is left alone
		assert.equal("\195\151x", Friends.normalise("\195\151X"))
		local store = {}
		Friends.add(store, "\195\171lric")
		Friends.merge(store, "\195\139lric-Forever", { score = 4 }, 10, false)
		assert.equal(4, store[Friends.normalise("\195\171lric")].summary.score)
	end)

	it("add then merge keeps added", function()
		local store = {}
		Friends.add(store, "bob")
		assert.is_true(store.Bob.added)
		Friends.merge(store, "Bob-Forever", sum(5), 100, false)
		assert.is_true(store.Bob.added)
		assert.equal(100, store.Bob.seen)
		assert.equal(5, store.Bob.summary.score)
	end)

	it("merge adds group or guild members as not added", function()
		local store = {}
		Friends.merge(store, "amy-Forever", sum(3), 50, true)
		assert.is_false(store.Amy.added)
		assert.equal(50, store.Amy.seen)
	end)

	it("merge ignores strangers not in the store", function()
		local store = {}
		Friends.merge(store, "zed", sum(3), 50, false)
		assert.is_nil(store.Zed)
	end)

	it("merge updates a person already in the store", function()
		local store = {}
		Friends.add(store, "zed")
		Friends.merge(store, "zed", sum(3), 50, false)
		assert.equal(3, store.Zed.summary.score)
	end)

	it("remove deletes everyone except an added person who is online (only un-added)", function()
		local store = {}
		Friends.add(store, "bob")
		Friends.merge(store, "bob", sum(1), 100, false)
		Friends.remove(store, "bob", 1000)
		assert.is_nil(store.Bob)

		Friends.add(store, "amy")
		Friends.merge(store, "amy", sum(1), 1000, true)
		Friends.remove(store, "amy", 1100)
		assert.is_not_nil(store.Amy)
		assert.is_false(store.Amy.added)

		Friends.merge(store, "cat", sum(1), 1000, true)
		Friends.remove(store, "cat", 1100)
		assert.is_nil(store.Cat) -- never added: gone even while online
	end)

	it("purge drops people not added and not kept", function()
		local store = {}
		Friends.add(store, "ann")
		Friends.merge(store, "bob", sum(1), 100, true)
		Friends.merge(store, "cat", sum(1), 100, true)
		assert.equal(1, Friends.purge(store, { Cat = true }))
		assert.is_not_nil(store.Ann)
		assert.is_nil(store.Bob)
		assert.is_not_nil(store.Cat)
	end)

	it("the leaderboard sorts when your name is unreadable", function()
		local store = {}
		Friends.merge(store, "bob", sum(0), 900, true)
		local ok, rows = pcall(Friends.leaderboard, store, { name = nil, summary = sum(0) }, 1000)
		assert.is_true(ok)
		assert.equal(2, #rows)
	end)

	it("orders the leaderboard and flags me", function()
		local store = {}
		Friends.merge(store, "bob", sum(50, 5, 1, 0), 900, true)
		Friends.merge(store, "amy", sum(50, 4, 1, 0), 100, true)
		Friends.add(store, "cat")
		local rows = Friends.leaderboard(store, { name = "Me", summary = sum(80, 9, 2, 1) }, 1000)
		assert.equal(4, #rows)
		assert.equal("Me", rows[1].name)
		assert.is_true(rows[1].isMe)
		assert.is_true(rows[1].online)
		assert.equal(80, rows[1].score)
		assert.equal(9, rows[1].mobs)
		assert.equal(1, rows[1].raids)
		assert.equal("Amy", rows[2].name)
		assert.is_false(rows[2].online)
		assert.equal("Bob", rows[3].name)
		assert.is_true(rows[3].online)
		assert.is_false(rows[3].isMe)
		assert.equal("Cat", rows[4].name)
		assert.equal(0, rows[4].score)
		assert.is_true(rows[4].added)
	end)

	it("keeps a copy of a person's dex with the time it arrived", function()
		local store = {}
		Friends.add(store, "bob")
		assert.is_true(Friends.keepDex(store, "bob", "D\t1", 500))
		assert.equal("D\t1", store.Bob.dex)
		assert.equal(500, store.Bob.dexAt)
		local text, at = Friends.savedDex(store, "Bob")
		assert.equal("D\t1", text)
		assert.equal(500, at)
		-- a newer copy replaces it
		Friends.keepDex(store, "Bob", "D\t1\nX", 600)
		assert.equal(600, store.Bob.dexAt)
		-- nobody to keep it with, or nothing to keep
		assert.is_false(Friends.keepDex(store, "Zed", "D\t1", 700))
		assert.is_nil(store.Zed)
		assert.is_false(Friends.keepDex(store, "Bob", nil, 700))
		assert.equal(600, store.Bob.dexAt)
		assert.is_nil(Friends.savedDex(store, "Zed"))
		-- forgetting it
		Friends.dropDex(store, "Bob")
		assert.is_nil(store.Bob.dex)
		assert.is_nil(store.Bob.dexAt)
		assert.is_nil(Friends.savedDex(store, "Bob"))
	end)

	it("tidy keeps the newer saved dex when two spellings merge", function()
		local store = {
			["Bob jones"] = { added = true, seen = 1, dex = "old", dexAt = 10 },
			["Bob Jones"] = { added = false, seen = 9, dex = "new", dexAt = 20 },
			["Ann smith"] = { added = true, seen = 1, dex = "mine", dexAt = 30 },
			["Ann Smith"] = { added = false, seen = 9 },
		}
		Friends.tidy(store, "Fel")
		assert.equal("new", store["Bob Jones"].dex)
		assert.equal(20, store["Bob Jones"].dexAt)
		assert.equal("mine", store["Ann Smith"].dex)
		assert.equal(30, store["Ann Smith"].dexAt)
	end)

	it("tells who is online", function()
		assert.is_true(Friends.isOnline({ seen = 900 }, 1000))
		assert.is_false(Friends.isOnline({ seen = 100 }, 1000))
		assert.is_false(Friends.isOnline({}, 1000))
		assert.is_false(Friends.isOnline(nil, 1000))
	end)
end)
