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

	it("does not mutate the map passed in", function()
		local map = { a = { soul = soul("Wolf"), seen = 1 } }
		local new = ns.Shards.update(map, { "a", "b" }, false, 500)
		assert.equal(1, map.a.seen)
		assert.is_nil(map.b)
		assert.are_not.equal(map, new)
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
		local new, gained = ns.Shards.update({ a = { soul = soul("Wolf"), seen = 1 } }, { "a", "b" }, true, 500)
		assert.same({}, gained)
		assert.equal("Wolf", new.a.soul.name)
		assert.same({ soul = false, seen = 500 }, new.b)
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
		local new = ns.Shards.update(map, {}, true, now, true)
		assert.is_nil(new.old)
		assert.equal("Recent", new.recent.soul.name)
		-- an ordinary scan and a quiet (bank/cursor) scan keep them
		assert.is_not_nil(ns.Shards.update(map, {}, false, now).old)
		assert.is_not_nil(ns.Shards.update(map, {}, true, now).old)
		assert.is_not_nil(ns.Shards.update(map, {}, true, now, false).old)
	end)

	it("a malformed saved value counts as unknown", function()
		local new, gained = ns.Shards.update({ a = "junk", b = { seen = 1 } }, { "a", "b" }, false, 500)
		assert.same({ "a", "b" }, gained)
		assert.is_nil(new.a)
		assert.is_nil(new.b)
	end)

	it("assign stores a soul or false and does not mutate", function()
		local map = { a = { soul = soul("Wolf"), seen = 1 } }
		local out = ns.Shards.assign(map, "b", false, 500)
		assert.same({ soul = false, seen = 500 }, out.b)
		assert.equal("Wolf", out.a.soul.name)
		assert.is_nil(map.b)
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
end)
