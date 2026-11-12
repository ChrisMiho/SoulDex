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
end)
