describe("ForeverData", function()
	it("puts the Forever raids first, TBD, with no instance id", function()
		local ns = LoadAddonFile("src/RaidData.lua")
		LoadAddonFile("src/ForeverData.lua", ns)
		local bd, hyjal = ns.RaidData[1], ns.RaidData[2]
		assert.same({ key = "BD", name = "The Barrow Deeps", bossCount = 8, tbd = true, mobs = {} }, bd)
		assert.same({ key = "Hyjal", name = "Hyjal Summit", bossCount = 13, tbd = true, mobs = {} }, hyjal)
		assert.equal("ZG", ns.RaidData[3].key)
		assert.equal(9, #ns.RaidData)
	end)

	it("loads without the generated data and has unique keys", function()
		local ns = LoadAddonFile("src/ForeverData.lua")
		assert.equal(2, #ns.RaidData)
		local all, seen = LoadAddonFile("src/ForeverData.lua", LoadAddonFile("src/RaidData.lua")).RaidData, {}
		for _, raid in ipairs(all) do
			assert.is_nil(seen[raid.key])
			seen[raid.key] = true
		end
	end)
end)
