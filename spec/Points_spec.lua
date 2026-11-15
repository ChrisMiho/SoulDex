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

	describe("repeat claims", function()
		it("counts stars at 10, 25, 50, 100, 250, 500, 750 and 1000, then one every 500", function()
			local want = { [0] = 0, [9] = 0, [10] = 1, [24] = 1, [25] = 2, [50] = 3, [100] = 4, [250] = 5, [499] = 5,
				[500] = 6, [749] = 6, [750] = 7, [999] = 7, [1000] = 8, [1499] = 8, [1500] = 9, [2000] = 10,
				[5200] = 16 }
			for count, stars in pairs(want) do
				assert.equal(stars, Points.stars(count), count)
			end
		end)

		it("knows where the current star began and the next comes", function()
			assert.same({ 0, 10 }, { Points.starSpan(0) })
			assert.same({ 10, 25 }, { Points.starSpan(12) })
			assert.same({ 500, 750 }, { Points.starSpan(749) })
			assert.same({ 750, 1000 }, { Points.starSpan(999) })
			assert.same({ 1000, 1500 }, { Points.starSpan(1000) })
			assert.same({ 2000, 2500 }, { Points.starSpan(2499) })
		end)

		it("adds up star points, doubled for elites", function()
			assert.equal(0, Points.starPoints(0, "normal"))
			assert.equal(1, Points.starPoints(1, "normal"))
			assert.equal(28, Points.starPoints(7, "normal"))
			assert.equal(38, Points.starPoints(8, "normal"))
			assert.equal(48, Points.starPoints(10, "normal"))
			assert.equal(76, Points.starPoints(8, "elite"))
		end)

		it("picks the rule by the kind of soul", function()
			assert.equal("mastery", Points.rule({ classification = "normal", points = 1 }))
			assert.equal("mastery", Points.rule({ classification = "elite", points = 5 }))
			assert.equal("mastery", Points.rule({ points = 1 }))
			assert.equal("daily", Points.rule({ classification = "rare", points = 10 }))
			assert.equal("daily", Points.rule({ classification = "rareelite", points = 10 }))
			assert.equal("boss", Points.rule({ classification = "worldboss", points = 25 }))
			assert.equal("boss", Points.rule({ classification = "elite", points = 25 })) -- a raid boss
			assert.equal("mastery", Points.rule({ classification = "elite", points = 65 }, true)) -- a friend's total
		end)

		it("counts claims per place or from one count", function()
			assert.equal(7, Points.count({ places = { A = { count = 3 }, B = { count = 4 } } }))
			assert.equal(5, Points.count({ count = 5, places = { A = { count = 1 } } }))
			assert.equal(0, Points.count({}))
		end)
	end)
end)
