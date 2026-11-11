describe("Init", function()
	it("loads without the game", function()
		_G.C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
		_G.CreateFrame = function()
			return { RegisterEvent = function() end, SetScript = function() end }
		end
		_G.SlashCmdList = {}
		local ns = LoadAddonFile("src/Init.lua")
		assert.equal("dev", ns.version)
		assert.equal("function", type(ns.Print))
	end)
end)
