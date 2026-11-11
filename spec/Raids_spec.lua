describe("Raids", function()
	local ns, Raids

	before_each(function()
		ns = LoadAddonFile("src/RaidData.lua")
		LoadAddonFile("src/Raids.lua", ns)
		Raids = ns.Raids
	end)

	it("finds a raid by instance id", function()
		assert.equal("Molten Core", Raids.byInstance(409).name)
		assert.is_nil(Raids.byInstance(1))
	end)

	it("lists the raids in display order", function()
		local ids = {}
		for i, raid in ipairs(Raids.list()) do
			ids[i] = raid.instanceID
		end
		assert.same({ 309, 409, 249, 469, 509, 531, 533 }, ids)
	end)

	it("finds a known mob and flags bosses", function()
		local raid, mob = Raids.find(409, 12118)
		assert.equal("Molten Core", raid.name)
		assert.equal("Lucifron", mob.name)
		assert.is_true(mob.boss)
	end)

	it("knows the summoned bosses", function()
		local _, ragnaros = Raids.find(409, 11502)
		assert.is_true(ragnaros.boss)
		local _, nefarian = Raids.find(469, 11583)
		assert.is_true(nefarian.boss)
		local _, onyxia = Raids.find(249, 10184)
		assert.is_true(onyxia.boss)
	end)

	it("returns the raid but no mob for an unknown npc", function()
		local raid, mob = Raids.find(409, 1)
		assert.equal("Molten Core", raid.name)
		assert.is_nil(mob)
	end)

	it("returns nothing for an unknown instance", function()
		assert.is_nil(Raids.find(1, 1))
	end)

	it("has well-formed data with no duplicate ids", function()
		for _, raid in ipairs(Raids.list()) do
			assert.is_true(#raid.mobs > 0)
			local seen = {}
			for _, mob in ipairs(raid.mobs) do
				assert.equal("number", type(mob.id))
				assert.is_true(type(mob.name) == "string" and mob.name ~= "")
				assert.is_nil(seen[mob.id])
				seen[mob.id] = true
			end
		end
	end)
end)
