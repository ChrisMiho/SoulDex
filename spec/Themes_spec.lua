describe("Themes", function()
	local Themes

	before_each(function()
		Themes = LoadAddonFile("src/Themes.lua").Themes
	end)

	it("lists the four themes in order, Soul Shard first", function()
		local ids = {}
		for i, theme in ipairs(Themes.LIST) do
			ids[i] = theme.id
		end
		assert.same({ "soulshard", "fel", "shadow", "ember" }, ids)
		assert.equal("soulshard", Themes.DEFAULT)
	end)

	it("defines every slot in every theme as lowercase hex", function()
		for _, theme in ipairs(Themes.LIST) do
			for _, slot in ipairs(Themes.SLOTS) do
				local hex = theme.colors[slot]
				assert.is_truthy(hex, theme.id .. " has no " .. slot)
				assert.is_truthy(hex:match("^[0-9a-f]+$") and #hex == 6, theme.id .. "." .. slot .. " = " .. hex)
			end
			local count = 0
			for _ in pairs(theme.colors) do
				count = count + 1
			end
			assert.equal(#Themes.SLOTS, count, theme.id .. " has a slot not in SLOTS")
		end
	end)

	it("keeps Soul Shard on the window's original colours", function()
		local c = Themes.palette("soulshard")
		assert.equal("14101c", c.BG)
		assert.equal("6b4fa0", c.BORDER)
		assert.equal("c9a8ff", c.TITLE)
		assert.equal("9dff3a", c.ACCENT)
		assert.equal("7dff6a", c.GOOD)
	end)

	it("falls back to the default theme for an unknown or junk id", function()
		assert.equal("soulshard", Themes.id("nope"))
		assert.equal("soulshard", Themes.id(5))
		assert.equal("soulshard", Themes.id(nil))
		assert.equal("soulshard", Themes.id({}))
		assert.equal("ember", Themes.id("ember"))
		assert.equal(Themes.palette("soulshard"), Themes.palette("nope"))
		assert.equal("Soul Shard", Themes.name("nope"))
		assert.equal("Ember", Themes.name("ember"))
	end)

	it("steps through the themes, wrapping round", function()
		assert.equal("fel", Themes.next("soulshard", 1))
		assert.equal("soulshard", Themes.next("ember", 1))
		assert.equal("ember", Themes.next("soulshard", -1))
		assert.equal("fel", Themes.next("junk", 1))
	end)

	it("keeps Soul Shard's emblems at the top of art and the others in their own folder", function()
		assert.equal("", Themes.emblemDir("soulshard"))
		assert.equal("", Themes.emblemDir("junk"))
		assert.equal("fel\\", Themes.emblemDir("fel"))
		assert.equal("ember\\", Themes.emblemDir("ember"))
	end)
end)
