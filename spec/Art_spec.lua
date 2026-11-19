describe("Art", function()
	local ns = LoadAddonFile("src/Ranks.lua", LoadAddonFile("src/Themes.lua"))

	-- Every theme's emblem files: art/rank<N>.tga for Soul Shard, art/<theme>/rank<N>.tga else.
	local function paths()
		local out = {}
		for _, theme in ipairs(ns.Themes.LIST) do
			for index in ipairs(ns.Ranks.LIST) do
				out[#out + 1] = "art/" .. ns.Themes.emblemDir(theme.id):gsub("\\", "/") .. "rank" .. index .. ".tga"
			end
		end
		return out
	end

	local function bytes(path)
		local file = io.open(path, "rb")
		if not file then
			return nil
		end
		local data = file:read("*a")
		file:close()
		return data
	end

	it("has a 64x64 32-bit uncompressed TGA for every rank in every theme", function()
		for _, path in ipairs(paths()) do
			local data = bytes(path)
			assert.is_truthy(data, path .. " is missing")
			assert.equal(0, data:byte(1), path .. ": no id field")
			assert.equal(2, data:byte(3), path .. ": uncompressed true colour")
			assert.equal(64, data:byte(13) + data:byte(14) * 256, path .. ": width")
			assert.equal(64, data:byte(15) + data:byte(16) * 256, path .. ": height")
			assert.equal(32, data:byte(17), path .. ": bits per pixel")
			assert.is_true(#data >= 18 + 64 * 64 * 4, path .. ": pixel data")
		end
	end)

	it("has a transparent corner and something drawn", function()
		for _, path in ipairs(paths()) do
			local data = bytes(path)
			assert.equal(0, data:byte(18 + 4), path .. ": first pixel's alpha")
			local drawn = false
			for pixel = 0, 64 * 64 - 1 do
				if data:byte(18 + pixel * 4 + 4) > 0 then
					drawn = true
					break
				end
			end
			assert.is_true(drawn, path .. " is empty")
		end
	end)

	it("names the game's Soul Shard icon nowhere in the addon", function()
		for line in io.lines("SoulDex.toc") do
			local path = line:match("^(src\\.+%.lua)%s*$")
			if path then
				path = path:gsub("\\", "/")
				assert.is_nil(bytes(path):find("Gem_Amethyst", 1, true), path)
			end
		end
	end)

	it("has no art for ranks that don't exist", function()
		assert.is_nil(bytes("art/rank" .. (#ns.Ranks.LIST + 1) .. ".tga"))
	end)
end)
