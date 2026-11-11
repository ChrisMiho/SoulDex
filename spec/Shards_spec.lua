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
		local new, gained = ns.Shards.update(map, { "0:1", "0:2" }, true)
		assert.same({ "0:2" }, gained)
		assert.equals("Wolf", new["0:1"].name)
		assert.is_nil(new["0:2"])
	end)

	it("pending catch wins over a move", function()
		local map = { ["0:1"] = soul("Wolf") }
		local new, gained = ns.Shards.update(map, { "0:2" }, true)
		assert.same({ "0:2" }, gained)
		assert.is_nil(new["0:1"])
		assert.is_nil(new["0:2"])
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
		local map = { ["0:2"] = soul("Wolf") }
		-- "0:10" sorts after "0:9" numerically; the first (lowest) new slot is gained.
		local _, gained = ns.Shards.update(map, { "0:2", "0:10", "0:9" }, false)
		assert.same({ "0:9", "0:10" }, gained)
		local map2 = {}
		local _, g2 = ns.Shards.update(map2, { "0:10", "0:2" }, false)
		assert.same({ "0:2", "0:10" }, g2)
	end)
end)
