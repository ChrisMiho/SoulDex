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

	it("normalises names", function()
		assert.equal("Stabbyface", Friends.normalise("stabbyface"))
		assert.equal("Stabbyface", Friends.normalise("Stabbyface-Forever"))
		assert.equal("Stabbyface", Friends.normalise("STABBYFACE"))
		assert.is_nil(Friends.normalise(""))
		assert.is_nil(Friends.normalise("-Realm"))
		assert.is_nil(Friends.normalise(nil))
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

	it("remove deletes only added people who are not currently seen", function()
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
		Friends.remove(store, "cat", 5000)
		assert.is_not_nil(store.Cat)
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
