describe("Shards", function()
	local ns

	local function soul(name)
		return { name = name, color = "ffffff", zone = "Elwynn Forest", time = 1000 }
	end

	local function names(map)
		local out = {}
		for _, s in pairs(map) do
			out[#out + 1] = s.name
		end
		table.sort(out)
		return out
	end

	before_each(function()
		ns = LoadAddonFile("src/Shards.lua", {})
	end)

	it("no change keeps souls", function()
		local map = { ["0:1"] = soul("Wolf"), ["1:3"] = soul("Boar") }
		local new, gained = ns.Shards.update(map, { "0:1", "1:3" }, false)
		assert.equals("Wolf", new["0:1"].name)
		assert.equals("Boar", new["1:3"].name)
		assert.same({}, gained)
	end)

	it("does not mutate the map passed in", function()
		local map = { ["0:1"] = soul("Wolf") }
		local new = ns.Shards.update(map, { "0:2" }, false)
		assert.is_not_nil(map["0:1"])
		assert.is_nil(map["0:2"])
		assert.are_not.equal(map, new)
	end)

	it("one shard moves, its soul follows", function()
		local map = { ["0:1"] = soul("Wolf") }
		local new, gained = ns.Shards.update(map, { "0:2" }, false)
		assert.is_nil(new["0:1"])
		assert.equals("Wolf", new["0:2"].name)
		assert.same({}, gained)
	end)

	it("shard used is dropped", function()
		local map = { ["0:1"] = soul("Wolf"), ["0:2"] = soul("Boar") }
		local new, gained = ns.Shards.update(map, { "0:2" }, false)
		assert.is_nil(new["0:1"])
		assert.equals("Boar", new["0:2"].name)
		assert.same({}, gained)
	end)

	it("new shard is reported as gained", function()
		local map = { ["0:1"] = soul("Wolf") }
		local new, gained = ns.Shards.update(map, { "0:1", "0:2" }, false)
		assert.same({ "0:2" }, gained)
		assert.equals("Wolf", new["0:1"].name)
		assert.is_nil(new["0:2"])
	end)

	it("a soulless shard is not re-gained", function()
		local new, gained = ns.Shards.update({ ["0:1"] = false }, { "0:1" }, false)
		assert.same({}, gained)
		assert.is_false(new["0:1"])
	end)

	it("phantom guard: move while nothing new arrives gains nothing", function()
		local new, gained = ns.Shards.update({ ["0:1"] = soul("Wolf") }, { "0:2" }, false)
		assert.same({}, gained)
		assert.is_nil(new["0:1"])
		assert.equals("Wolf", new["0:2"].name)
	end)

	it("a soulless shard moving stays soulless", function()
		local new, gained = ns.Shards.update({ ["0:1"] = false }, { "0:2" }, false)
		assert.same({}, gained)
		assert.is_false(new["0:2"])
	end)

	it("baseline marks every slot false and gains nothing", function()
		local new, gained = ns.Shards.update({}, { "0:1", "0:2" }, true)
		assert.same({}, gained)
		assert.is_false(new["0:1"])
		assert.is_false(new["0:2"])
	end)

	it("baseline keeps existing souls", function()
		local new, gained = ns.Shards.update({ ["0:1"] = soul("Wolf") }, { "0:1", "0:2" }, true)
		assert.same({}, gained)
		assert.equals("Wolf", new["0:1"].name)
		assert.is_false(new["0:2"])
	end)

	it("two new shards, two gained", function()
		local _, gained = ns.Shards.update({}, { "0:3", "0:1" }, false)
		assert.same({ "0:1", "0:3" }, gained)
	end)

	it("more removed than added gains nothing", function()
		local map = { ["0:1"] = soul("Wolf"), ["0:2"] = soul("Boar") }
		local new, gained = ns.Shards.update(map, { "0:3" }, false)
		assert.same({}, gained)
		assert.equals("Wolf", new["0:3"].name)
		assert.is_nil(new["0:1"])
		assert.is_nil(new["0:2"])
	end)

	it("assign stores false and does not mutate", function()
		local map = { ["0:1"] = soul("Wolf") }
		local out = ns.Shards.assign(map, "0:2", false)
		assert.is_false(out["0:2"])
		assert.equals("Wolf", out["0:1"].name)
		assert.is_nil(map["0:2"])
		assert.equals("Boar", ns.Shards.assign(map, "0:3", soul("Boar"))["0:3"].name)
	end)

	it("unknown shard stays unnamed", function()
		local map = { ["0:1"] = soul("Wolf") }
		local new = ns.Shards.update(map, { "0:1", "0:2" }, false)
		assert.is_nil(new["0:2"])
		assert.equals("Wolf", new["0:1"].name)
	end)

	it("two moves at once keep both souls (order may swap)", function()
		local map = { ["0:1"] = soul("Wolf"), ["0:2"] = soul("Boar") }
		local new, gained = ns.Shards.update(map, { "1:1", "1:2" }, false)
		assert.same({ "Boar", "Wolf" }, names(new))
		assert.is_nil(new["0:1"])
		assert.is_nil(new["0:2"])
		assert.same({}, gained)
	end)

	it("sorts by bag then slot numerically", function()
		local _, first = ns.Shards.update({ ["0:2"] = soul("Wolf") }, { "0:2", "0:10", "0:9" }, false)
		assert.same({ "0:9", "0:10" }, first)
		local _, second = ns.Shards.update({}, { "0:10", "0:2" }, false)
		assert.same({ "0:2", "0:10" }, second)
	end)
end)
