describe("Rarity", function()
	local Rarity

	before_each(function()
		Rarity = LoadAddonFile("src/Rarity.lua").Rarity
	end)

	it("colours elites, rares and bosses, not ordinary mobs", function()
		assert.equal("ffd25a", Rarity.color("elite"))
		assert.equal("c0c0c0", Rarity.color("rare"))
		assert.equal("c0c0c0", Rarity.color("rareelite"))
		assert.equal("ff9a5a", Rarity.color("worldboss"))
		assert.is_nil(Rarity.color("normal"))
		assert.is_nil(Rarity.color(nil))
	end)

	it("labels elites, rares and bosses, not ordinary mobs", function()
		assert.equal("Elite", Rarity.label("elite"))
		assert.equal("Rare Elite", Rarity.label("rareelite"))
		assert.equal("Rare", Rarity.label("rare"))
		assert.equal("Boss", Rarity.label("worldboss"))
		assert.is_nil(Rarity.label("minus"))
	end)

	it("turns a class colour into hex", function()
		local colors = { ROGUE = { r = 1, g = 0.96, b = 0.41 } }
		assert.equal("fff569", Rarity.classHex("ROGUE", colors))
		assert.is_nil(Rarity.classHex("MAGE", colors))
		assert.is_nil(Rarity.classHex("ROGUE", nil))
		assert.is_nil(Rarity.classHex(nil, colors))
	end)
end)
