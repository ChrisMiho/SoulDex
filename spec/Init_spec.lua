describe("Init", function()
	local STUBBED = { "C_AddOns", "CreateFrame", "SlashCmdList", "DEFAULT_CHAT_FRAME", "SLASH_SOULDEX1" }
	local saved, printed

	before_each(function()
		saved = {}
		for _, name in ipairs(STUBBED) do
			saved[name] = _G[name]
		end
		printed = {}
		_G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
		_G.CreateFrame = function()
			return { RegisterEvent = function() end, SetScript = function() end }
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
			for _, cmd in ipairs({ "/souldex ", "/souldex options", "/souldex add <name>", "/souldex remove <name>" }) do
				assert.truthy(all:find(cmd, 1, true), cmd)
			end
		end)
	end)
end)
