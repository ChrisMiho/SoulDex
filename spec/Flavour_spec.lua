describe("Flavour", function()
	local Flavour

	before_each(function()
		Flavour = LoadAddonFile("src/Flavour.lua").Flavour
	end)

	it("is deterministic", function()
		local a = Flavour.line("Young Wolf", "Beast", "Wolf", "Elwynn Forest")
		local b = Flavour.line("Young Wolf", "Beast", "Wolf", "Elwynn Forest")
		assert.equal(a, b)
	end)

	it("mentions the zone", function()
		local line = Flavour.line("Young Wolf", "Beast", "Wolf", "Elwynn Forest")
		assert.truthy(line:find("Elwynn Forest", 1, true))
	end)

	it("mentions the family when it uses one", function()
		local line = Flavour.line("Young Wolf", "Beast", "Wolf", "Elwynn Forest")
		assert.truthy(line:find("Wolf", 1, true))
	end)

	local function clean(line)
		assert.is_string(line)
		assert.is_true(#line > 0)
		assert.is_nil(line:find("nil", 1, true))
		assert.is_nil(line:find("{", 1, true))
		assert.is_nil(line:find("}", 1, true))
	end

	it("copes with a missing family and type", function()
		clean(Flavour.line("Young Wolf", nil, nil, "Elwynn Forest"))
		clean(Flavour.line("Young Wolf", "Beast", nil, "Elwynn Forest"))
		clean(Flavour.line("Young Wolf", nil, "Wolf", "Elwynn Forest"))
		clean(Flavour.line("Young Wolf", "Beast", "Wolf", nil))
		clean(Flavour.line("Mystery", "Weird New Type", nil, nil))
	end)

	it("has clean lines for every creature type", function()
		local types = { "Beast", "Humanoid", "Undead", "Demon", "Elemental", "Dragonkin", "Giant", "Mechanical",
			"Critter", "Not specified" }
		for _, t in ipairs(types) do
			for i = 1, 20 do
				clean(Flavour.line("Mob" .. i, t, "Fam", "Zone"))
				clean(Flavour.line("Mob" .. i, t, nil, nil))
			end
		end
	end)

	it("uses family lines for known families, and the type's lines otherwise", function()
		local families = { "Wolf", "Spider", "Boar", "Cat", "Bear", "Raptor", "Crocolisk", "Bat", "Owl", "Gorilla",
			"Hyena", "Scorpid", "Turtle", "Carrion Bird", "Tallstrider", "Crab" }
		local beastLines = {}
		for i = 1, 40 do
			beastLines[Flavour.line("Mob" .. i, "Beast", "Some Odd Family", "Zone")] = true
		end
		for _, family in ipairs(families) do
			for i = 1, 10 do
				local line = Flavour.line("Mob" .. i, "Beast", family, "Zone")
				clean(line)
				assert.is_nil(beastLines[line], family .. " used a generic Beast line: " .. line)
			end
		end
	end)

	it("varies between names of the same type", function()
		local seen, count = {}, 0
		for i = 1, 20 do
			local line = Flavour.line("Name" .. i, "Beast", "Wolf", "Elwynn Forest")
			if not seen[line] then
				seen[line] = true
				count = count + 1
			end
		end
		assert.is_true(count >= 2)
	end)
end)
