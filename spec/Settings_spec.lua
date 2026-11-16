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

	describe("scale", function()
		it("reads percent and factor, as number or text", function()
			assert.equal(1.2, Settings.scale("120"))
			assert.equal(1.2, Settings.scale("120%"))
			assert.equal(1.2, Settings.scale("1.2"))
			assert.equal(0.8, Settings.scale(0.8))
		end)

		it("rounds to 5% and keeps within the limits", function()
			assert.equal(1.15, Settings.scale("1.13"))
			assert.equal(Settings.SCALE_MIN, Settings.scale("0.1"))
			assert.equal(Settings.SCALE_MAX, Settings.scale("500"))
		end)

		it("is nil for anything that is no number", function()
			for _, junk in ipairs({ "big", "", "-1", "0" }) do
				assert.is_nil(Settings.scale(junk), junk)
			end
			assert.is_nil(Settings.scale(nil))
			assert.is_nil(Settings.scale({}))
			assert.is_nil(Settings.scale(0 / 0))
		end)

		it("shows a scale in percent", function()
			assert.equal("100%", Settings.percent(1))
			assert.equal("115%", Settings.percent(1.15))
			assert.equal("60%", Settings.percent(0.6))
		end)

		it("defaults the greeting on and the boss-name experiment off", function()
			assert.is_true(Settings.normalise({}).greeting)
			assert.is_false(Settings.normalise({ greeting = false }).greeting)
			assert.is_false(Settings.normalise({}).lateAsk)
			assert.is_false(Settings.normalise({ lateAsk = 1 }).lateAsk) -- a number is no switch
		end)

		it("keeps a saved popup size and repairs a damaged one", function()
			assert.equal(1.3, Settings.normalise({ popupScale = 1.3 }).popupScale)
			assert.equal(1, Settings.normalise({ popupScale = "huge" }).popupScale)
			assert.equal(1, Settings.normalise({ popupScale = true }).popupScale)
			assert.equal(Settings.SCALE_MAX, Settings.normalise({ popupScale = 400 }).popupScale)
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
			assert.equal("help", (Settings.parseCommand("help")))
			assert.equal("help", (Settings.parseCommand("find")))
			assert.equal("help", (Settings.parseCommand("scale")))
			assert.equal("help", (Settings.parseCommand("reset now")))
		end)

		it("parses the one-word commands", function()
			for _, word in ipairs({ "version", "reset", "test" }) do
				assert.equal(word, (Settings.parseCommand(" " .. word:upper() .. " ")))
			end
		end)

		it("parses find and scale with what follows", function()
			local action, arg = Settings.parseCommand("find Defias  Pillager")
			assert.equal("find", action)
			assert.equal("Defias  Pillager", arg)
			action, arg = Settings.parseCommand("Scale 120")
			assert.equal("scale", action)
			assert.equal("120", arg)
		end)
	end)
end)
