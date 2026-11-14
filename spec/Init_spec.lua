describe("Init", function()
	local STUBBED = {
		"C_AddOns", "CreateFrame", "SlashCmdList", "DEFAULT_CHAT_FRAME", "SLASH_SOULDEX1", "SLASH_SOULDEX2",
	}
	local saved, printed, events, onEvent

	before_each(function()
		saved = {}
		for _, name in ipairs(STUBBED) do
			saved[name] = _G[name]
		end
		printed, events, onEvent = {}, {}, nil
		_G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
		_G.CreateFrame = function()
			return {
				RegisterEvent = function(_, event) events[#events + 1] = event end,
				SetScript = function(_, _, fn) onEvent = fn end,
			}
		end
		_G.SlashCmdList = {}
		_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) printed[#printed + 1] = text end }
	end)

	after_each(function()
		for _, name in ipairs(STUBBED) do
			_G[name] = saved[name]
		end
	end)

	local function load()
		local ns = LoadAddonFile("src/Settings.lua", {})
		return LoadAddonFile("src/Init.lua", ns)
	end

	it("loads without the game", function()
		local ns = load()
		assert.equal("dev", ns.version)
		assert.equal("function", type(ns.Print))
		assert.equal("function", type(_G.SlashCmdList.SOULDEX))
		assert.equal("/souldex", _G.SLASH_SOULDEX1)
		assert.equal("/dex", _G.SLASH_SOULDEX2)
	end)

	describe("greeting", function()
		it("prints the version and the slash command once the player logs in", function()
			load()
			assert.truthy(table.concat(events, " "):find("PLAYER_LOGIN", 1, true))
			onEvent(nil, "PLAYER_LOGIN")
			assert.same({ "|cff9482c9Soul-Dex|r dev loaded. Type /souldex or /dex to open." }, printed)
		end)

		it("prefixes a packaged version with v", function()
			_G.C_AddOns = { GetAddOnMetadata = function() return "1.2.0" end }
			local ns = load()
			assert.equal("v1.2.0 loaded. Type /souldex or /dex to open.", ns.Greeting())
		end)

		it("keeps the packager's own v (no vv)", function()
			_G.C_AddOns = { GetAddOnMetadata = function() return "v1.1.0" end }
			local ns = load()
			assert.equal("v1.1.0 loaded. Type /souldex or /dex to open.", ns.Greeting())
		end)

		it("shows a built copy's version, not dev", function()
			_G.C_AddOns = { GetAddOnMetadata = function() return "v1.1.0" end }
			assert.equal("v1.1.0", load().version)
			_G.C_AddOns = { GetAddOnMetadata = function() return nil end }
			assert.equal("dev", load().version)
		end)

		it("never writes the packager's version token in Init.lua (the packager would replace it)", function()
			local file = assert(io.open("src/Init.lua", "r"))
			local source = file:read("*a")
			file:close()
			assert.is_nil(source:find("@project" .. "-version@", 1, true))
		end)

		it("prints nothing for ADDON_LOADED", function()
			load()
			onEvent(nil, "ADDON_LOADED", "SomeOtherAddon")
			assert.same({}, printed)
		end)
	end)

	describe("OnSlash", function()
		it("toggles the window and opens options", function()
			local ns = load()
			local calls = {}
			ns.UI = { toggle = function() calls[#calls + 1] = "toggle" end }
			ns.Options = { toggle = function() calls[#calls + 1] = "options" end }
			_G.SlashCmdList.SOULDEX("")
			_G.SlashCmdList.SOULDEX("options")
			assert.same({ "toggle", "options" }, calls)
		end)

		it("adds and removes friends through ns.Net when it exists", function()
			local ns = load()
			local calls = {}
			ns.Net = {
				addFriend = function(name) calls[#calls + 1] = "add " .. name end,
				removeFriend = function(name) calls[#calls + 1] = "remove " .. name end,
			}
			ns.OnSlash("add Bob")
			ns.OnSlash("remove Bob")
			assert.same({ "add Bob", "remove Bob" }, calls)
		end)

		it("says friends aren't available without ns.Net", function()
			local ns = load()
			ns.OnSlash("add Bob")
			assert.equal(1, #printed)
			assert.truthy(printed[1]:find("aren't available", 1, true))
		end)

		it("prints the command list for anything else", function()
			local ns = load()
			ns.OnSlash("what")
			local all = table.concat(printed, "\n")
			local commands = { "/souldex ", "/souldex options", "/souldex add <name>", "/souldex remove <name>", "/dex " }
			for _, cmd in ipairs(commands) do
				assert.truthy(all:find(cmd, 1, true), cmd)
			end
		end)
	end)
end)
