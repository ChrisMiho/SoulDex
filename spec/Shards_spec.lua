describe("Shards", function()
	local ns
	local DAY = 86400

	local function soul(name)
		return { name = name, color = "ffffff", zone = "Elwynn Forest", time = 1000 }
	end

	before_each(function()
		ns = LoadAddonFile("src/Shards.lua", {})
	end)

	it("known shards keep their soul and are marked seen now", function()
		local map = { a = { soul = soul("Wolf"), seen = 1 }, b = { soul = false, seen = 1 } }
		local new, gained = ns.Shards.update(map, { "a", "b" }, false, 500)
		assert.equal("Wolf", new.a.soul.name)
		assert.is_false(new.b.soul)
		assert.equal(500, new.a.seen)
		assert.equal(500, new.b.seen)
		assert.same({}, gained)
	end)

	it("changes the map in place: a scan never copies it", function()
		local map = { a = { soul = soul("Wolf"), seen = 1 } }
		local entry = map.a
		local new = ns.Shards.update(map, { "a", "b" }, false, 500)
		assert.equal(map, new)
		assert.equal(entry, new.a)
		assert.equal(500, map.a.seen)
		assert.is_nil(map.b) -- gained: the caller assigns it
	end)

	it("a new GUID is reported as gained and left out of the map", function()
		local new, gained = ns.Shards.update({}, { "a" }, false, 500)
		assert.same({ "a" }, gained)
		assert.is_nil(new.a)
	end)

	it("several new GUIDs are all gained, in a stable order", function()
		local _, gained = ns.Shards.update({}, { "c", "a", "b" }, false, 500)
		assert.same({ "a", "b", "c" }, gained)
	end)

	it("a GUID listed twice is gained once", function()
		local _, gained = ns.Shards.update({}, { "a", "a" }, false, 500)
		assert.same({ "a" }, gained)
	end)

	it("a baseline stores new GUIDs as soulless and gains nothing", function()
		local new, gained, quietNew = ns.Shards.update({ a = { soul = soul("Wolf"), seen = 1 } }, { "a", "b" }, true, 500)
		assert.same({}, gained)
		assert.equal(1, quietNew) -- "b" was new; "a" was known
		assert.equal("Wolf", new.a.soul.name)
		assert.same({ soul = false, seen = 500 }, new.b)
		local _, _, none = ns.Shards.update({}, { "c" }, false, 500)
		assert.equal(0, none)
	end)

	it("absent shards are kept (bank, mailbox, cursor)", function()
		local map = { a = { soul = soul("Wolf"), seen = 1 } }
		local new = ns.Shards.update(map, {}, false, 500)
		assert.equal("Wolf", new.a.soul.name)
		assert.equal(1, new.a.seen)
	end)

	it("only a pruning (login) scan drops shards not seen for 30 days", function()
		local now = 100 * DAY
		local map = {
			old = { soul = soul("Old"), seen = now - 31 * DAY },
			recent = { soul = soul("Recent"), seen = now - 29 * DAY },
		}
		-- an ordinary scan and a quiet (bank/cursor) scan keep them
		assert.is_not_nil(ns.Shards.update(map, {}, false, now).old)
		assert.is_not_nil(ns.Shards.update(map, {}, true, now).old)
		assert.is_not_nil(ns.Shards.update(map, {}, true, now, false).old)
		local new = ns.Shards.update(map, {}, true, now, true)
		assert.is_nil(new.old)
		assert.equal("Recent", new.recent.soul.name)
	end)

	describe("the login clean-up", function()
		local now = 100 * DAY

		it("drops absent soulless shards after a day, never present or named ones", function()
			local map = {
				spent = { soul = false, seen = now - 2 * DAY },
				fresh = { soul = false, seen = now - 3600 },
				inBags = { soul = false, seen = now - 2 * DAY },
				banked = { soul = soul("Wolf"), seen = now - 2 * DAY },
			}
			local new = ns.Shards.update(map, { "inBags" }, true, now, true)
			assert.is_nil(new.spent)
			assert.is_not_nil(new.fresh)
			assert.is_not_nil(new.inBags)
			assert.equal("Wolf", new.banked.soul.name)
		end)

		it("keeps only the most recently seen absent shards past the cap", function()
			ns.Shards.MAX_ABSENT = 2
			local map = {
				a = { soul = soul("A"), seen = now - 5 * DAY },
				b = { soul = soul("B"), seen = now - 1 * DAY },
				c = { soul = soul("C"), seen = now - 3 * DAY },
				bag = { soul = soul("Bag"), seen = now - 20 * DAY },
			}
			local new = ns.Shards.update(map, { "bag" }, true, now, true)
			assert.is_nil(new.a)
			assert.is_not_nil(new.b)
			assert.is_not_nil(new.c)
			assert.is_not_nil(new.bag)
		end)

		it("never drops a shard still waiting for its name", function()
			ns.Shards.MAX_ABSENT = 0
			local map = { held = { soul = false, pending = { token = "t" }, seen = now - 5 * DAY } }
			assert.is_not_nil(ns.Shards.update(map, {}, true, now, true).held)
		end)

		it("is not run by ordinary scans", function()
			local map = { spent = { soul = false, seen = now - 2 * DAY } }
			assert.is_not_nil(ns.Shards.update(map, {}, false, now).spent)
		end)
	end)

	it("a malformed saved value counts as unknown", function()
		local new, gained = ns.Shards.update({ a = "junk", b = { seen = 1 } }, { "a", "b" }, false, 500)
		assert.same({ "a", "b" }, gained)
		assert.is_nil(new.a)
		assert.is_nil(new.b)
	end)

	it("assign stores a soul or false in the map itself", function()
		local map = { a = { soul = soul("Wolf"), seen = 1 } }
		local out = ns.Shards.assign(map, "b", false, 500)
		assert.equal(map, out)
		assert.same({ soul = false, seen = 500 }, out.b)
		assert.equal("Wolf", out.a.soul.name)
		assert.equal("Boar", ns.Shards.assign(map, "c", soul("Boar"), 500).c.soul.name)
	end)

	it("soulOf gives the soul of a named shard only", function()
		local map = { a = { soul = soul("Wolf"), seen = 1 }, b = { soul = false, seen = 1 }, c = "junk" }
		assert.equal("Wolf", ns.Shards.soulOf(map, "a").name)
		assert.is_nil(ns.Shards.soulOf(map, "b"))
		assert.is_nil(ns.Shards.soulOf(map, "c"))
		assert.is_nil(ns.Shards.soulOf(map, "zzz"))
		assert.is_nil(ns.Shards.soulOf(nil, "a"))
		assert.is_nil(ns.Shards.soulOf(map, nil))
	end)

	describe("pending entries", function()
		local ctx = { zone = "Deadmines" }

		it("update carries pending over for a present guid", function()
			local map = ns.Shards.assignPending({}, "a", "tok1", ctx, 10)
			local new = ns.Shards.update(map, { "a" }, false, 500)
			local p = ns.Shards.pendingOf(new, "a")
			assert.equal("tok1", p.token)
			assert.same(ctx, p.ctx)
			assert.equal(500, new.a.seen)
			assert.is_false(new.a.soul)
		end)

		it("update keeps pending for an absent guid", function()
			local map = ns.Shards.assignPending({}, "a", "tok1", ctx, 10)
			local new = ns.Shards.update(map, {}, false, 500)
			assert.equal("tok1", ns.Shards.pendingOf(new, "a").token)
		end)

		it("assignPending marks the shard in the map itself", function()
			local map = {}
			local new = ns.Shards.assignPending(map, "a", "tok1", ctx, 10)
			assert.equal(map, new)
			assert.equal(10, new.a.seen)
		end)

		it("findPending returns the guid for a token", function()
			local map = ns.Shards.assignPending({}, "a", "tok1", ctx, 10)
			map = ns.Shards.assignPending(map, "b", "tok2", ctx, 10)
			assert.equal("b", ns.Shards.findPending(map, "tok2"))
			assert.is_nil(ns.Shards.findPending(map, "nope"))
		end)

		it("assign clears pending and soulOf is nil while pending", function()
			local map = ns.Shards.assignPending({}, "a", "tok1", ctx, 10)
			assert.is_nil(ns.Shards.soulOf(map, "a"))
			map = ns.Shards.assign(map, "a", soul("Wolf"), 20)
			assert.is_nil(ns.Shards.pendingOf(map, "a"))
			assert.equal("Wolf", ns.Shards.soulOf(map, "a").name)
		end)

		it("allPending lists exactly the pending guids, sorted", function()
			local map = ns.Shards.assignPending({}, "b", "tok2", ctx, 10)
			map = ns.Shards.assignPending(map, "a", "tok1", ctx, 10)
			map = ns.Shards.assign(map, "c", soul("Wolf"), 10)
			map = ns.Shards.assign(map, "d", false, 10)
			local list = ns.Shards.allPending(map)
			assert.equal(2, #list)
			assert.equal("a", list[1].guid)
			assert.equal("tok1", list[1].pending.token)
			assert.equal("b", list[2].guid)
			assert.same({}, ns.Shards.allPending({}))
		end)

		it("drops a corrupt pending at the login clean-up, and counts its shard as new in a scan", function()
			local function damaged()
				return { a = { soul = false, pending = "bad", seen = 1 },
					b = { soul = false, pending = { token = 5 }, seen = 1 } }
			end
			local new = ns.Shards.update(damaged(), {}, true, 500, true)
			assert.is_nil(new.a)
			assert.is_nil(new.b)
			local _, gained = ns.Shards.update(damaged(), { "a" }, false, 500)
			assert.same({ "a" }, gained)
		end)
	end)
end)
