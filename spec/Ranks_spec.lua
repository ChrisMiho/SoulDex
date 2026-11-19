describe("Ranks", function()
	local Ranks

	before_each(function()
		Ranks = LoadAddonFile("src/Ranks.lua").Ranks
	end)

	it("starts at 0 and climbs", function()
		assert.equal(0, Ranks.LIST[1].min)
		for i = 2, #Ranks.LIST do
			assert.is_true(Ranks.LIST[i].min > Ranks.LIST[i - 1].min)
		end
	end)

	it("gives the rank a score holds, with the way to the next one", function()
		local r = Ranks.of(0)
		assert.equal(1, r.index)
		assert.equal("Initiate", r.name)
		assert.equal("Acolyte", r.nextName)
		assert.equal(50, r.toNext)
		assert.equal(0, r.progress)

		r = Ranks.of(49)
		assert.equal("Initiate", r.name)
		assert.equal(1, r.toNext)

		r = Ranks.of(50)
		assert.equal("Acolyte", r.name)
		assert.equal(2, r.index)

		r = Ranks.of(3750)
		assert.equal("Reaper", r.name)
		assert.equal("Soul Harvester", r.nextName)
		assert.equal(5000, r.nextMin)
		assert.equal(1250, r.toNext)
		assert.equal(0.5, r.progress)
		assert.equal(#Ranks.LIST, r.count)
	end)

	it("has no next rank at the top", function()
		local r = Ranks.of(999999)
		assert.equal(#Ranks.LIST, r.index)
		assert.equal("Lord of Souls", r.name)
		assert.is_nil(r.nextName)
		assert.is_nil(r.toNext)
		assert.equal(1, r.progress)
	end)

	it("treats a bad score as 0", function()
		assert.equal("Initiate", Ranks.of(nil).name)
		assert.equal("Initiate", Ranks.of(-5).name)
		assert.equal("Initiate", Ranks.of("many").name)
	end)

	it("reports a rank only when a threshold was crossed", function()
		assert.is_nil(Ranks.gained(0, 49))
		assert.is_nil(Ranks.gained(60, 60))
		assert.equal("Acolyte", Ranks.gained(49, 50).name)
		assert.equal("Soul Thief", Ranks.gained(20, 250).name) -- skipping one names the rank reached
		assert.is_nil(Ranks.gained(250, 20))
	end)

	it("names an emblem texture for each rank", function()
		assert.equal("Interface\\AddOns\\SoulDex\\art\\rank1.tga", Ranks.emblem(1))
		assert.equal("Interface\\AddOns\\SoulDex\\art\\rank8.tga", Ranks.emblem(8))
		assert.equal(Ranks.emblem(4), Ranks.of(1000).emblem)
		assert.equal(Ranks.emblem(8), Ranks.of(99999).emblem)
	end)

	it("takes a theme's own emblems, the theme in use by default", function()
		local ns = LoadAddonFile("src/Ranks.lua", LoadAddonFile("src/Themes.lua"))
		assert.equal("Interface\\AddOns\\SoulDex\\art\\rank2.tga", ns.Ranks.emblem(2))
		assert.equal("Interface\\AddOns\\SoulDex\\art\\ember\\rank2.tga", ns.Ranks.emblem(2, "ember"))
		assert.equal("Interface\\AddOns\\SoulDex\\art\\rank2.tga", ns.Ranks.emblem(2, "gone"))
		ns.Themes.current = "fel"
		assert.equal("Interface\\AddOns\\SoulDex\\art\\fel\\rank5.tga", ns.Ranks.emblem(5))
		assert.equal(ns.Ranks.emblem(5), ns.Ranks.of(2500).emblem)
	end)

	it("gives the nearest real emblem for a bad index", function()
		assert.equal(Ranks.emblem(1), Ranks.emblem(nil))
		assert.equal(Ranks.emblem(1), Ranks.emblem("3"))
		assert.equal(Ranks.emblem(1), Ranks.emblem(0))
		assert.equal(Ranks.emblem(1), Ranks.emblem(-2))
		assert.equal(Ranks.emblem(2), Ranks.emblem(2.9))
		assert.equal(Ranks.emblem(#Ranks.LIST), Ranks.emblem(#Ranks.LIST + 1))
		assert.equal(Ranks.emblem(1), Ranks.of(nil).emblem)
		assert.equal(Ranks.emblem(1), Ranks.of("lots").emblem)
	end)

	it("finds the art under whatever folder the addon was loaded from", function()
		local other = {}
		loadfile("src/Ranks.lua")("SoulDex-main", other)
		assert.equal("Interface\\AddOns\\SoulDex-main\\art\\rank3.tga", other.Ranks.emblem(3))
	end)
end)
