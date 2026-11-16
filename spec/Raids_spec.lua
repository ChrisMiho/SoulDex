describe("Raids", function()
	local ns, Raids

	before_each(function()
		ns = LoadAddonFile("src/RaidData.lua")
		LoadAddonFile("src/Raids.lua", ns)
		Raids = ns.Raids
	end)

	it("finds a raid by instance id", function()
		assert.equal("Molten Core", Raids.byInstance(409).name)
		assert.is_nil(Raids.byInstance(1))
	end)

	it("lists the raids in display order", function()
		local ids = {}
		for i, raid in ipairs(Raids.list()) do
			ids[i] = raid.instanceID
		end
		assert.same({ 309, 409, 249, 469, 509, 531, 533 }, ids)
	end)

	it("finds a known mob and flags bosses", function()
		local raid, mob = Raids.find(409, 12118)
		assert.equal("Molten Core", raid.name)
		assert.equal("Lucifron", mob.name)
		assert.is_true(mob.boss)
	end)

	it("knows the summoned bosses", function()
		local _, ragnaros = Raids.find(409, 11502)
		assert.is_true(ragnaros.boss)
		local _, nefarian = Raids.find(469, 11583)
		assert.is_true(nefarian.boss)
		local _, onyxia = Raids.find(249, 10184)
		assert.is_true(onyxia.boss)
	end)

	it("returns the raid but no mob for an unknown npc", function()
		local raid, mob = Raids.find(409, 1)
		assert.equal("Molten Core", raid.name)
		assert.is_nil(mob)
	end)

	it("returns nothing for an unknown instance", function()
		assert.is_nil(Raids.find(1, 1))
	end)

	it("has well-formed data with no duplicate ids", function()
		for _, raid in ipairs(Raids.list()) do
			assert.is_true(#raid.mobs > 0)
			local seen = {}
			for _, mob in ipairs(raid.mobs) do
				assert.equal("number", type(mob.id))
				assert.is_true(type(mob.name) == "string" and mob.name ~= "")
				assert.is_nil(seen[mob.id])
				seen[mob.id] = true
			end
		end
	end)
end)

describe("Raids boss roster", function()
	local roster = {
		ZG = { "High Priestess Jeklik", "High Priest Venoxis", "High Priestess Mar'li", "High Priest Thekal",
			"High Priestess Arlokk", "Hakkar", "Bloodlord Mandokir", "Jin'do the Hexxer", "Gahz'ranka", "Gri'lek",
			"Hazza'rah", "Renataki", "Wushoolay" },
		MC = { "Lucifron", "Magmadar", "Gehennas", "Garr", "Shazzrah", "Baron Geddon", "Golemagg the Incinerator",
			"Sulfuron Harbinger", "Majordomo Executus", "Ragnaros" },
		Onyxia = { "Onyxia" },
		BWL = { "Razorgore the Untamed", "Vaelastrasz the Corrupt", "Broodlord Lashlayer", "Firemaw", "Ebonroc",
			"Flamegor", "Chromaggus", "Nefarian" },
		AQ20 = { "Kurinnaxx", "General Rajaxx", "Moam", "Buru the Gorger", "Ayamiss the Hunter",
			"Ossirian the Unscarred" },
		AQ40 = { "The Prophet Skeram", "Vem", "Princess Yauj", "Lord Kri", "Battleguard Sartura",
			"Fankriss the Unyielding", "Viscidus", "Princess Huhuran", "Emperor Vek'lor", "Emperor Vek'nilash",
			"Ouro", "C'Thun" },
		Naxx = { "Anub'Rekhan", "Grand Widow Faerlina", "Maexxna", "Noth the Plaguebringer", "Heigan the Unclean",
			"Loatheb", "Instructor Razuvious", "Gothik the Harvester", "Thane Korth'azz", "Lady Blaumeux",
			"Highlord Mograine", "Sir Zeliek", "Patchwerk", "Grobbulus", "Gluth", "Thaddius", "Sapphiron",
			"Kel'Thuzad" },
	}

	it("lists every vanilla raid boss as a boss in its raid", function()
		local ns = LoadAddonFile("src/RaidData.lua")
		local byKey = {}
		for _, raid in ipairs(ns.RaidData) do
			local bosses = {}
			for _, mob in ipairs(raid.mobs) do
				if mob.boss then
					bosses[mob.name] = true
				end
			end
			byKey[raid.key] = bosses
		end
		for key, names in pairs(roster) do
			for _, name in ipairs(names) do
				assert.is_true(byKey[key][name] == true, name .. " missing from " .. key)
			end
		end
	end)
end)

describe("Raids with TBD raids", function()
	local Raids

	before_each(function()
		local ns = {
			RaidData = {
				{ key = "BD", name = "The Barrow Deeps", tbd = true, mobs = {} },
				{ key = "MC", name = "Molten Core", instanceID = 409, mobs = { { id = 1, name = "A" } } },
			},
		}
		LoadAddonFile("src/Raids.lua", ns)
		Raids = ns.Raids
	end)

	it("never matches a raid without an id by a nil id", function()
		assert.is_nil(Raids.byInstance(nil))
		assert.is_nil(Raids.find(nil, 1))
	end)
	it("finds a raid by key", function()
		assert.equal("Molten Core", Raids.byKey("MC").name)
		assert.is_nil(Raids.byKey("nope"))
	end)
	it("finds an id-less raid by name, loosely", function()
		assert.equal("BD", Raids.byName("The Barrow Deeps").key)
		assert.equal("BD", Raids.byName("  barrow deeps ").key)
		assert.is_nil(Raids.byName("Molten Core")) -- has an id already
		assert.is_nil(Raids.byName("Barrow"))
		assert.is_nil(Raids.byName(""))
		assert.is_nil(Raids.byName(nil))
		assert.is_nil(Raids.byName(42))
	end)
	it("learns an instance id once", function()
		assert.is_true(Raids.learn("BD", 3001))
		assert.equal("BD", Raids.byInstance(3001).key)
		assert.is_nil(Raids.byName("The Barrow Deeps"))
		assert.is_true(Raids.learn("BD", 3001))
		assert.is_false(Raids.learn("BD", 3002))
		assert.equal(3001, Raids.byKey("BD").instanceID)
	end)
	it("refuses a bad or colliding id", function()
		assert.is_false(Raids.learn("BD", 409))
		assert.is_false(Raids.learn("BD", "3001"))
		assert.is_false(Raids.learn("BD", nil))
		assert.is_false(Raids.learn("nope", 3001))
		assert.is_nil(Raids.byKey("BD").instanceID)
		assert.equal("MC", Raids.byInstance(409).key)
	end)
	it("finds a listed creature's id by its exact name", function()
		local data = Raids.byInstance(409).mobs
		local first = data[1]
		assert.equal(first.id, Raids.idByName(409, first.name))
		assert.equal(first.id, Raids.idByName(409, "  " .. first.name:upper() .. " "))
		assert.is_nil(Raids.idByName(409, first.name .. "x"))
		assert.is_nil(Raids.idByName(9999, first.name))
		assert.is_nil(Raids.idByName(409, nil))
	end)
	it("gives no id for a name the raid lists twice", function()
		local mobs = Raids.byInstance(409).mobs
		mobs[#mobs + 1] = { id = 99999, name = mobs[1].name }
		assert.is_nil(Raids.idByName(409, mobs[1].name))
		mobs[#mobs] = nil
	end)
	it("lists only completable raids", function()
		local list = Raids.completable()
		assert.equal(1, #list)
		assert.equal("MC", list[1].key)
	end)
end)
