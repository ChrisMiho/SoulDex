local function frameStub()
	local f = {}
	return setmetatable(f, {
		__index = function()
			return function() return f end
		end,
	})
end

describe("Capture glue", function()
	local saved = {}
	local names = { "CreateFrame", "UIParent", "hooksecurefunc", "GameTooltip", "GetSpellInfo", "C_Container", "date" }

	before_each(function()
		for _, k in ipairs(names) do
			saved[k] = _G[k]
		end
		_G.CreateFrame = frameStub
		_G.UIParent = frameStub()
		_G.hooksecurefunc = function() end
		_G.GameTooltip = {}
		_G.GetSpellInfo = function() end
	end)

	after_each(function()
		for _, k in ipairs(names) do
			_G[k] = saved[k]
		end
	end)

	local function load()
		local ns = {}
		local pure = { "Settings", "RaidData", "Raids", "Points", "Flavour", "Dex", "Milestones", "Catch", "Shards" }
		for _, f in ipairs(pure) do
			LoadAddonFile("src/" .. f .. ".lua", ns)
		end
		LoadAddonFile("src/Toast.lua", ns)
		LoadAddonFile("src/Capture.lua", ns)
		return ns
	end

	it("loads and defines ns.OnLoaded and the hook lists", function()
		local ns = load()
		assert.equal("function", type(ns.OnLoaded))
		assert.same({}, ns.onCatch)
		assert.same({}, ns.onLoaded)
	end)

	describe("npcIdFromGuid", function()
		it("reads field 6 of a creature GUID", function()
			local ns = load()
			assert.equal(11502, ns.Capture.npcIdFromGuid("Creature-0-1465-409-12345-11502-0000ABCDEF"))
		end)
		it("is nil for players and junk", function()
			local ns = load()
			assert.is_nil(ns.Capture.npcIdFromGuid("Player-4372-0123ABCD"))
			assert.is_nil(ns.Capture.npcIdFromGuid(nil))
		end)
	end)

	describe("continentOf / groupFor", function()
		local maps = {
			[1429] = { mapType = 3, parentMapID = 1415, name = "Elwynn Forest" },
			[1415] = { mapType = 2, parentMapID = 947, name = "Eastern Kingdoms" },
			[1414] = { mapType = 2, parentMapID = 947, name = "Kalimdor" },
			[5] = { mapType = 2, parentMapID = 0, name = "Outland" },
		}
		local function getInfo(id) return maps[id] end
		it("walks up to the continent", function()
			local ns = load()
			assert.equal("Eastern Kingdoms", ns.Capture.continentOf(1429, getInfo))
			assert.equal("Kalimdor", ns.Capture.continentOf(1414, getInfo))
			assert.equal("Outland", ns.Capture.continentOf(5, getInfo))
			assert.is_nil(ns.Capture.continentOf(999, getInfo))
		end)
		it("files dungeons together and falls back to Other", function()
			local ns = load()
			assert.equal("Dungeons", ns.Capture.groupFor("party", "Kalimdor"))
			assert.equal("Kalimdor", ns.Capture.groupFor("none", "Kalimdor"))
			assert.equal("Other", ns.Capture.groupFor("none", nil))
		end)
	end)

	it("splits Name-Realm", function()
		local ns = load()
		local name, realm = ns.Capture.splitName("Bob-Realm One", "Home")
		assert.equal("Bob", name)
		assert.equal("Realm One", realm)
		name, realm = ns.Capture.splitName("Bob", "Home")
		assert.equal("Bob", name)
		assert.equal("Home", realm)
	end)

	it("colours players by class and mobs by rarity", function()
		local ns = load()
		local classColors = { ROGUE = { r = 1, g = 0.96, b = 0.41 } }
		assert.equal("fff569", ns.Capture.colorFor({ class = "ROGUE" }, classColors))
		assert.equal("ffffff", ns.Capture.colorFor({ class = "NOPE" }, classColors))
		assert.equal("ffcc33", ns.Capture.colorFor({ classification = "elite" }))
		assert.equal("ffffff", ns.Capture.colorFor({ classification = "normal" }))
	end)

	describe("recordCatch", function()
		local function setup()
			local ns = load()
			return ns, ns.Dex.new({})
		end
		local ctx = { time = 100, myLevel = 20, zone = "Elwynn Forest", group = "Eastern Kingdoms" }

		it("records a player GUID as a player, even in a raid", function()
			local ns, dex = setup()
			local cand = { guid = "Player-1-AB", info = { name = "Bob", realm = "R" } }
			local r, kind = ns.Capture.recordCatch(dex, cand, ctx, "raid", 409)
			assert.equal("player", kind)
			assert.is_true(r.isNew)
		end)
		it("records a raid creature by NPC id", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-409-2-11502-3", info = { name = "Ragnaros" } }
			local r, kind = ns.Capture.recordCatch(dex, cand, ctx, "raid", 409)
			assert.equal("raid", kind)
			assert.is_true(r.isNew)
			assert.is_not_nil(dex.db.raids[11502])
			assert.is_nil(dex.db.mobs.Ragnaros)
		end)
		it("records everything else as a mob", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-0-2-299-3", info = { name = "Young Wolf", classification = "normal" } }
			local r, kind = ns.Capture.recordCatch(dex, cand, ctx, "none")
			assert.equal("mob", kind)
			assert.equal(1, r.placeCount)
		end)
		it("refuses a candidate without a name", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-0-2-299-3", info = {} }
			assert.is_nil(ns.Capture.recordCatch(dex, cand, ctx, "none"))
		end)
	end)

	describe("Toast text", function()
		it("builds subtitles", function()
			local ns = load()
			local mob = { kind = "mob", placeCount = 3, points = 5 }
			assert.equal("Elwynn Forest \194\183 #3 here \194\183 +5 pts", ns.Toast.subtitle(mob, "Elwynn Forest"))
			assert.equal("Elwynn Forest \194\183 +10 pts", ns.Toast.subtitle({ kind = "player", points = 10 }, "Elwynn Forest"))
			assert.equal("Molten Core \194\183 +25 pts", ns.Toast.subtitle({ kind = "raid", points = 25 }, "Molten Core"))
		end)
		it("marks rarity on mobs only", function()
			local ns = load()
			assert.equal("Hogger  (Elite)", ns.Toast.nameLine({ name = "Hogger", classification = "elite" }))
			assert.equal("Bob", ns.Toast.nameLine({ name = "Bob", classification = "elite", class = "ROGUE" }))
			assert.equal("Wolf", ns.Toast.nameLine({ name = "Wolf", classification = "normal" }))
			assert.equal("Boss", ns.Toast.rarityLabel("worldboss"))
		end)
	end)
end)
