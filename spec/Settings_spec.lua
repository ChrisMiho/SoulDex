describe("Settings", function()
	local Settings

	before_each(function()
		Settings = LoadAddonFile("src/Settings.lua").Settings
	end)

	describe("normalise", function()
		it("fills an empty table with the defaults", function()
			assert.same(Settings.DEFAULTS, Settings.normalise({}))
		end)

		it("keeps booleans and coerces non-booleans to the default", function()
			local t = Settings.normalise({ popup = false, sound = "x" })
			assert.is_false(t.popup)
			assert.is_true(t.sound)
			assert.is_true(t.announce)
		end)

		it("does not alias DEFAULTS", function()
			local t = Settings.normalise({})
			t.popup = false
			assert.is_true(Settings.DEFAULTS.popup)
		end)
	end)

	describe("parseCommand", function()
		it("toggles on empty input", function()
			assert.equal("toggle", (Settings.parseCommand("")))
			assert.equal("toggle", (Settings.parseCommand(nil)))
		end)

		it("trims and lowercases options", function()
			assert.equal("options", (Settings.parseCommand("  Options ")))
		end)

		it("parses add and remove with an argument", function()
			local action, arg = Settings.parseCommand("add Stabbyface")
			assert.equal("add", action)
			assert.equal("Stabbyface", arg)
			action, arg = Settings.parseCommand("remove x")
			assert.equal("remove", action)
			assert.equal("x", arg)
		end)

		it("falls back to help", function()
			assert.equal("help", (Settings.parseCommand("add")))
			assert.equal("help", (Settings.parseCommand("banana")))
		end)
	end)
end)
