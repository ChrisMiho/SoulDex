describe("Whisper", function()
	local W

	before_each(function()
		W = LoadAddonFile("src/Whisper.lua", {}).Whisper
	end)

	it("has the constants", function()
		assert.equal("SDX1", W.MARKER)
		assert.equal(60, W.TIMEOUT)
		assert.equal(600, W.CEILING)
		assert.equal(64, W.MAX_NAME)
	end)

	it("builds the message", function()
		assert.equal("SDX1:a1:%t", W.message("a1"))
	end)

	describe("parse", function()
		it("reads a token and a name", function()
			local token, name = W.parse("SDX1:a1:Scarlet Chaplain")
			assert.equal("a1", token)
			assert.equal("Scarlet Chaplain", name)
		end)

		it("keeps the token but no name when unexpanded", function()
			local token, name = W.parse("SDX1:a1:%t")
			assert.equal("a1", token)
			assert.is_nil(name)
		end)

		it("rejects invalid names but keeps the token", function()
			local bad = {
				"SDX1:a1:",
				"SDX1:a1:Bad|cffname",
				"SDX1:a1:a:b",
				"SDX1:a1:line\nbreak",
				"SDX1:a1:" .. string.rep("x", 65),
			}
			for _, text in ipairs(bad) do
				local token, name = W.parse(text)
				assert.equal("a1", token, text)
				assert.is_nil(name, text)
			end
		end)

		it("drops a raid marker from the name", function()
			-- What the game sends back for a marked target: "{rt8}Mana Phantom" (probe, City
			-- of Dalaran); localised clients may spell the marker as a word.
			for _, text in ipairs({
				"SDX1:a1:{rt8}Mana Phantom",
				"SDX1:a1:{rt7} Mana Phantom",
				"SDX1:a1:{skull}Mana Phantom",
				"SDX1:a1:Mana Phantom{rt1}",
				"SDX1:a1:{RT2}{rt3}Mana Phantom",
			}) do
				local token, name = W.parse(text)
				assert.equal("a1", token, text)
				assert.equal("Mana Phantom", name, text)
			end
		end)

		it("gives no name for a marker alone or a stray brace", function()
			for _, text in ipairs({ "SDX1:a1:{rt8}", "SDX1:a1:{rt8} ", "SDX1:a1:Mana {Phantom", "SDX1:a1:Mana}" }) do
				local token, name = W.parse(text)
				assert.equal("a1", token, text)
				assert.is_nil(name, text)
			end
		end)

		it("accepts a 64 character name", function()
			local long = string.rep("x", 64)
			local _, name = W.parse("SDX1:a1:" .. long)
			assert.equal(long, name)
		end)

		it("returns nil, nil for anything else", function()
			for _, v in ipairs({ "hello", "SDX1:", "SDX1::name", "SDX1:a1", 42, true }) do
				local token, name = W.parse(v)
				assert.is_nil(token)
				assert.is_nil(name)
			end
			local token, name = W.parse(nil)
			assert.is_nil(token)
			assert.is_nil(name)
		end)
	end)

	describe("isMarker", function()
		it("recognises the marker at the start only", function()
			assert.is_true(W.isMarker("SDX1:x:y"))
			assert.is_false(W.isMarker("sdx1:x"))
			assert.is_false(W.isMarker("hi SDX1:"))
			assert.is_false(W.isMarker(nil))
			assert.is_false(W.isMarker(7))
		end)
	end)

	describe("shouldAsk", function()
		local function base()
			return {
				nameHidden = true,
				hasTarget = true,
				mouseoverOther = false,
				focusOther = false,
				chatLocked = false,
				afk = false,
				dnd = false,
			}
		end

		it("asks only when every condition holds", function()
			assert.is_true(W.shouldAsk(base()))
		end)

		for _, field in ipairs({ "nameHidden", "hasTarget", "mouseoverOther", "focusOther", "chatLocked", "afk", "dnd" }) do
			it("does not ask when " .. field .. " is flipped", function()
				local s = base()
				s[field] = not s[field]
				assert.is_false(W.shouldAsk(s))
			end)

			it("does not ask when " .. field .. " is unreadable", function()
				local s = base()
				s[field] = nil
				assert.is_false(W.shouldAsk(s))
			end)
		end
	end)

	describe("holding an ask for later", function()
		local function locked()
			return {
				nameHidden = true, hasTarget = true, mouseoverOther = false, focusOther = false,
				chatLocked = true, afk = nil, dnd = nil, -- AFK and DND are unreadable in an encounter
			}
		end

		it("holds only when the chat lock is the one thing in the way", function()
			assert.is_true(W.shouldDefer(locked()))
			for _, change in ipairs({
				{ "chatLocked", false }, { "chatLocked", nil }, { "nameHidden", false }, { "hasTarget", false },
				{ "mouseoverOther", true }, { "mouseoverOther", nil }, { "focusOther", true }, { "afk", true }, { "dnd", true },
			}) do
				local s = locked()
				s[change[1]] = change[2]
				assert.is_false(W.shouldDefer(s), change[1] .. "=" .. tostring(change[2]))
			end
		end)

		it("sends once chat unlocks, if the target never changed", function()
			local open = { hasTarget = true, chatLocked = false, afk = false, dnd = false }
			assert.equal("send", W.lateStep(4, 4, open))
			assert.equal("send", W.lateStep(4, 4, { hasTarget = true, chatLocked = false, afk = false, dnd = false,
				mouseoverOther = true })) -- the mouse matters at the cast only
		end)

		it("waits while chat is locked or the player's state can't be read", function()
			assert.equal("wait", W.lateStep(4, 4, { hasTarget = true, chatLocked = true, afk = false, dnd = false }))
			assert.equal("wait", W.lateStep(4, 4, { hasTarget = true, chatLocked = nil, afk = false, dnd = false }))
			assert.equal("wait", W.lateStep(4, 4, { hasTarget = true, chatLocked = false, afk = nil, dnd = false }))
			assert.equal("wait", W.lateStep(4, 4, { hasTarget = true, chatLocked = false, afk = false, dnd = true }))
		end)

		it("fails after any target change, or with no target", function()
			local open = { hasTarget = true, chatLocked = false, afk = false, dnd = false }
			assert.equal("fail", W.lateStep(4, 5, open))
			assert.equal("fail", W.lateStep(nil, 5, open))
			assert.equal("fail", W.lateStep(4, 4, { hasTarget = false, chatLocked = false, afk = false, dnd = false }))
			assert.equal("fail", W.lateStep(4, 5, { hasTarget = true, chatLocked = true })) -- even while locked
		end)
	end)

	describe("queue", function()
		local q

		before_each(function()
			q = W.newQueue()
		end)

		it("expires after the timeout of unrestricted time", function()
			local pend = { id = 1 }
			local token = q:add(pend, 0)
			assert.equal(token, pend.token)
			assert.same({}, q:tick(59, false))
			assert.equal(pend, q:get(token))
			local expired = q:tick(61, false)
			assert.equal(1, #expired)
			assert.equal(pend, expired[1])
			assert.is_nil(q:get(token))
			assert.equal(0, q:count())
		end)

		it("does not count restricted time", function()
			local token = q:add({}, 0)
			assert.same({}, q:tick(100, true))
			assert.same({}, q:tick(150, false))
			assert.is_not_nil(q:get(token))
			assert.equal(1, #q:tick(161, false))
			assert.is_nil(q:get(token))
		end)

		it("expires at the ceiling even when always restricted", function()
			local token = q:add({}, 0)
			for t = 10, 590, 10 do
				assert.same({}, q:tick(t, true))
			end
			assert.is_not_nil(q:get(token))
			assert.equal(1, #q:tick(600, true))
			assert.is_nil(q:get(token))
		end)

		it("gives unique tokens and removes one at a time", function()
			local a, b = {}, {}
			local ta, tb = q:add(a, 0), q:add(b, 0)
			assert.are_not.equal(ta, tb)
			assert.equal(2, q:count())
			assert.equal(a, q:remove(ta))
			assert.is_nil(q:remove(ta))
			assert.equal(b, q:get(tb))
			assert.equal(1, q:count())
		end)

		it("gives short hex tokens that parse back", function()
			for _, now in ipairs({ 0, 12.345, 98765.4321, 4000000.5 }) do
				local token = q:add({}, now)
				assert.truthy(token:match("^%x+$"), token)
				assert.truthy(#token <= 8, token)
				local reply = W.message(token):gsub("%%t", "Scarlet Monk")
				assert.equal(token, (W.parse(reply)))
			end
		end)

		it("a new session's tokens don't repeat the last session's (time is in them)", function()
			local old = q:add({}, 100.25)
			local fresh = W.newQueue() -- after a /reload the counter starts again
			assert.are_not.equal(old, fresh:add({}, 112.5))
		end)

		it("returns expired entries in send order", function()
			local a, b = {}, {}
			q:add(a, 0)
			q:add(b, 1)
			local expired = q:tick(100, false)
			assert.equal(a, expired[1])
			assert.equal(b, expired[2])
		end)
	end)

	describe("repairNames", function()
		local function place(count, first, last)
			return { count = count, first = first, last = last, myLevel = 30 }
		end

		it("renames a marked mob", function()
			local entry = { name = "{rt7}Saturated Remnant", points = 5, first = 10, last = 10,
				places = { Dalaran = place(1, 10, 10) } }
			local db = { mobs = { ["{rt7}Saturated Remnant"] = entry }, raids = {}, shardSouls = {} }
			assert.equal(1, W.repairNames(db))
			assert.is_nil(db.mobs["{rt7}Saturated Remnant"])
			assert.equal(entry, db.mobs["Saturated Remnant"])
			assert.equal("Saturated Remnant", entry.name)
		end)

		it("merges a marked mob into the clean one", function()
			local clean = { name = "Remnant", points = 2, first = 20, last = 30, minLevel = 29, maxLevel = 30,
				classification = "normal", bonus = 1, places = { Dalaran = place(2, 20, 30) } }
			local marked = { name = "{rt8}Remnant", points = 5, first = 5, last = 40, minLevel = 28, maxLevel = 31,
				classification = "elite", creatureType = "Elemental", bonus = 2,
				places = { Dalaran = place(1, 5, 5), Stormwind = place(3, 35, 40) } }
			local db = { mobs = { Remnant = clean, ["{rt8}Remnant"] = marked }, raids = {}, shardSouls = {} }
			W.repairNames(db)
			assert.is_nil(db.mobs["{rt8}Remnant"])
			local m = db.mobs.Remnant
			assert.equal(clean, m)
			assert.equal(5, m.points)
			assert.equal(5, m.first)
			assert.equal(40, m.last)
			assert.equal(28, m.minLevel)
			assert.equal(31, m.maxLevel)
			assert.equal(3, m.bonus)
			assert.equal("normal", m.classification) -- what was there stays
			assert.equal("Elemental", m.creatureType) -- a gap is filled
			assert.equal(3, m.places.Dalaran.count)
			assert.equal(5, m.places.Dalaran.first)
			assert.equal(30, m.places.Dalaran.last)
			assert.equal(3, m.places.Stormwind.count)
		end)

		it("cleans raid entries and shard souls", function()
			local db = {
				mobs = {},
				raids = { [123] = { name = "{rt1}Core Hound", count = 1 } },
				shardSouls = {
					a = { soul = { name = "{rt7}Saturated Remnant", zone = "Dalaran" }, seen = 1 },
					b = { soul = { name = "Mountain Lion" }, seen = 1 },
					c = { soul = false, seen = 1 },
				},
			}
			assert.equal(2, W.repairNames(db))
			assert.equal("Core Hound", db.raids[123].name)
			assert.equal("Saturated Remnant", db.shardSouls.a.soul.name)
			assert.equal("Mountain Lion", db.shardSouls.b.soul.name)
		end)

		it("leaves a name that would be empty, and damaged data", function()
			local db = { mobs = { ["{rt8}"] = { name = "{rt8}", places = {} }, bad = 7 }, raids = 3 }
			assert.equal(0, W.repairNames(db))
			assert.is_table(db.mobs["{rt8}"])
			assert.equal(0, W.repairNames({}))
		end)
	end)
end)
