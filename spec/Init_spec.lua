describe("Init", function()
	local STUBBED = {
		"C_AddOns", "CreateFrame", "SlashCmdList", "DEFAULT_CHAT_FRAME", "SLASH_SOULDEX1", "SLASH_SOULDEX2",
		"BINDING_HEADER_SOULDEX", "BINDING_NAME_SOULDEX_TOGGLE", "SoulDex_Toggle", "GameTooltip",
		"SoulDex_OnAddonCompartmentClick", "SoulDex_OnAddonCompartmentEnter", "SoulDex_OnAddonCompartmentLeave",
		"LOCALIZED_CLASS_NAMES_MALE",
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
			assert.same({ "|cff9482c9SoulDex|r dev loaded. Type /souldex or /dex to open." }, printed)
		end)

		it("prefixes a packaged version with v", function()
			_G.C_AddOns = { GetAddOnMetadata = function() return "1.2.0" end }
			local ns = load()
			assert.equal("v1.2.0 loaded. Type /souldex or /dex to open.", ns.Greeting())
		end)

		it("names the rank once the dex is loaded", function()
			local ns = load()
			LoadAddonFile("src/Ranks.lua", ns)
			ns.dex = { score = function() return 612 end }
			assert.equal("dev loaded. |cff9dff3aSoul Thief|r, 612 pts. Type /souldex or /dex to open.", ns.Greeting())
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

		it("stays quiet when the login message is switched off", function()
			local ns = load()
			ns.db = { settings = { greeting = false } }
			onEvent(nil, "PLAYER_LOGIN")
			assert.same({}, printed)
			ns.db.settings.greeting = true
			onEvent(nil, "PLAYER_LOGIN")
			assert.equal(1, #printed)
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

	describe("new commands", function()
		local ns, calls

		before_each(function()
			ns = load()
			calls = {}
			ns.db = {}
			ns.UI = {
				toggle = function() calls[#calls + 1] = "toggle" end,
				resetWindow = function() calls[#calls + 1] = "reset" end,
				setScale = function(value)
					calls[#calls + 1] = "scale " .. value
					return ns.Settings.scale(value)
				end,
			}
			ns.Options = {
				toggle = function() calls[#calls + 1] = "options" end,
				testPopup = function() calls[#calls + 1] = "test" end,
			}
		end)

		it("prints the version", function()
			ns.OnSlash("version")
			assert.same({ "|cff9482c9SoulDex|r version dev." }, printed)
		end)

		it("resets and scales the window", function()
			ns.OnSlash("reset")
			ns.OnSlash("scale 120")
			assert.same({ "reset", "scale 120" }, calls)
			assert.truthy(printed[2]:find("Window scale: 120%.", 1, true))
		end)

		it("explains a scale that is no number, and changes nothing", function()
			ns.OnSlash("scale huge")
			assert.same({}, calls)
			assert.truthy(printed[1]:find("60 to 160", 1, true))
		end)

		it("shows the sample popup", function()
			ns.OnSlash("test")
			assert.same({ "test" }, calls)
		end)

		it("prints what find gives", function()
			ns.dex = {}
			ns.View = { findLines = function(_, text) return { "one " .. text, "two" } end }
			ns.OnSlash("find wolf")
			assert.same({ "|cff9482c9SoulDex|r one wolf", "|cff9482c9SoulDex|r two" }, printed)
		end)

		it("says so when find comes before the dex is loaded", function()
			ns.OnSlash("find wolf")
			assert.truthy(printed[1]:find("still loading", 1, true))
		end)

		it("lists every command in the help", function()
			ns.OnSlash("help")
			local all = table.concat(printed, "\n")
			for _, word in ipairs({ "find <text>", "scale", "reset", "test", "version" }) do
				assert.truthy(all:find("/souldex " .. word, 1, true), word)
			end
		end)

		it("the key binding and the addon button open the window; a right-click the options", function()
			assert.equal("SoulDex", _G.BINDING_HEADER_SOULDEX)
			assert.equal("string", type(_G.BINDING_NAME_SOULDEX_TOGGLE))
			_G.SoulDex_Toggle()
			_G.SoulDex_OnAddonCompartmentClick("SoulDex", "LeftButton")
			_G.SoulDex_OnAddonCompartmentClick("SoulDex", "RightButton")
			assert.same({ "toggle", "toggle", "options" }, calls)
		end)

		it("the addon button's tooltip names the rank once the dex is loaded", function()
			assert.same({ "Click to open. Right-click for options." }, ns.CompartmentLines())
			LoadAddonFile("src/Ranks.lua", ns)
			ns.dex = { score = function() return 612 end }
			assert.equal("Soul Thief \194\183 612 pts", ns.CompartmentLines()[1])
			local lines = {}
			_G.GameTooltip = {
				SetOwner = function() end,
				SetText = function(_, text) lines[#lines + 1] = text end,
				AddLine = function(_, text) lines[#lines + 1] = text end,
				Show = function() end,
				Hide = function() lines.hidden = true end,
			}
			_G.SoulDex_OnAddonCompartmentEnter("SoulDex", {})
			assert.equal("SoulDex dev", lines[1])
			assert.equal(3, #lines)
			_G.SoulDex_OnAddonCompartmentLeave()
			assert.is_true(lines.hidden)
			assert.has_no.errors(function() _G.SoulDex_OnAddonCompartmentEnter("SoulDex", nil) end)
		end)
	end)
end)
