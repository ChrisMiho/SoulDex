describe("Points", function()
	local Points

	before_each(function()
		Points = LoadAddonFile("src/Points.lua").Points
	end)

	it("scores normal, minus and unknown mobs as 1", function()
		assert.equal(1, Points.forMob("normal"))
		assert.equal(1, Points.forMob("minus"))
		assert.equal(1, Points.forMob(nil))
	end)

	it("scores elites as 5", function()
		assert.equal(5, Points.forMob("elite"))
	end)

	it("scores rares and rare elites as 10", function()
		assert.equal(10, Points.forMob("rare"))
		assert.equal(10, Points.forMob("rareelite"))
	end)

	it("scores world bosses as 25", function()
		assert.equal(25, Points.forMob("worldboss"))
	end)

	it("scores raid bosses as 25 whatever their classification", function()
		assert.equal(25, Points.forMob("elite", true))
	end)

	it("scores players as 10", function()
		assert.equal(10, Points.PLAYER)
	end)
end)
