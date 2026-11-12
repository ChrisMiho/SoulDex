-- Capture glue and the shard tooltip, loaded with stubbed WoW globals.
-- Every stubbed global is restored after each test.

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
-- A secret that looks like an ordinary string, so a missing guard would compare or join it.
local STR_SECRET = "\0secret"

local STUBBED = {
	"CreateFrame", "UIParent", "hooksecurefunc", "GameTooltip", "C_Container", "date", "time", "GetTime",
	"C_Timer", "issecretvalue", "canaccesstable", "C_Spell", "C_Item", "ItemLocation", "TooltipDataProcessor",
	"Enum", "C_RestrictedActions", "GetCursorInfo", "UnitName", "UnitGUID", "UnitIsPlayer", "UnitLevel",
	"UnitClassification", "UnitCreatureType", "UnitCreatureFamily", "UnitClass", "UnitRace", "GetGuildInfo",
	"GetRealmName", "GetInstanceInfo", "C_Map", "GetRealZoneText", "GetZoneText", "IsInGuild",
	"SendChatMessage", "C_ChatInfo", "PlaySound", "SOUNDKIT", "geterrorhandler", "UNKNOWN", "UNKNOWNOBJECT",
	"NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "RAID_CLASS_COLORS",
}

describe("Capture glue", function()
	local saved
	local world -- the fake game state the stubs read
	local frames, timers, postCalls

	local function frameStub()
		local f = { events = {}, unitEvents = {} }
		function f:RegisterEvent(event)
			if world.refuse[event] then
				error("blocked")
			end
			self.events[event] = true
		end
		function f:RegisterUnitEvent(event, unit)
			if world.refuse[event] then
				error("blocked")
			end
			self.unitEvents[event] = unit
		end
		function f:SetScript(_, fn)
			self.onEvent = fn
		end
		frames[#frames + 1] = f
		return setmetatable(f, {
			__index = function()
				return function() return f end
			end,
		})
	end

	before_each(function()
		saved = {}
		for _, k in ipairs(STUBBED) do
			saved[k] = _G[k]
		end
		frames, timers, postCalls = {}, {}, {}
		world = {
			clock = 100,
			epoch = 1000000,
			refuse = {},
			bags = { [0] = {} },
			cursor = nil,
			target = nil, -- { name, realm, guid, level, classification, creatureType, family, player, class, race, guild }
			zone = "Elwynn Forest",
			instanceType = "none",
			instanceID = 0,
		}
		_G.CreateFrame = function() return frameStub() end
		_G.UIParent = {}
		_G.hooksecurefunc = function() end
		_G.GameTooltip = {}
		_G.date = function() return "10 Nov 2026" end
		_G.time = function() return world.epoch end
		_G.GetTime = function() return world.clock end
		_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
		_G.issecretvalue = function(v) return rawequal(v, SECRET) or v == STR_SECRET end
		_G.canaccesstable = function() return true end
		_G.C_Spell = {
			GetSpellName = function(id)
				return ({ [1120] = "Drain Soul", [17877] = "Shadowburn", [686] = "Shadow Bolt" })[id]
			end,
		}
		_G.ItemLocation = {
			CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
		}
		_G.C_Item = {
			GetItemGUID = function(loc)
				local item = world.bags[loc.bag] and world.bags[loc.bag][loc.slot]
				return item and item.guid
			end,
		}
		_G.C_Container = {
			GetContainerNumSlots = function(bag) return world.bags[bag] and 16 or 0 end,
			GetContainerItemID = function(bag, slot)
				local item = world.bags[bag] and world.bags[bag][slot]
				return item and item.id
			end,
		}
		_G.TooltipDataProcessor = {
			AddTooltipPostCall = function(kind, fn) postCalls[#postCalls + 1] = { kind = kind, fn = fn } end,
		}
		_G.Enum = { TooltipDataType = { Item = 0 } }
		_G.C_RestrictedActions = nil
		_G.GetCursorInfo = function() return world.cursor end
		local function t(field)
			return function(unit)
				return unit == "target" and world.target and world.target[field] or nil
			end
		end
		_G.UnitName = function(unit)
			if unit == "target" and world.target then
				return world.target.name, world.target.realm
			end
			if unit == "player" then
				return "Me"
			end
		end
		_G.UnitGUID = t("guid")
		_G.UnitIsPlayer = function(unit)
			if unit == "target" and world.target then
				return world.target.player == true
			end
			return false
		end
		_G.UnitLevel = function(unit)
			if unit == "player" then
				return 30
			end
			return world.target and world.target.level
		end
		_G.UnitClassification = t("classification")
		_G.UnitCreatureType = t("creatureType")
		_G.UnitCreatureFamily = t("family")
		_G.UnitClass = function(unit)
			local c = unit == "target" and world.target and world.target.class
			return c, c
		end
		_G.UnitRace = t("race")
		_G.GetGuildInfo = t("guild")
		_G.GetRealmName = function() return "Home" end
		_G.GetInstanceInfo = function()
			return "World", world.instanceType, 0, "", 0, 0, false, world.instanceID
		end
		_G.C_Map = {
			GetBestMapForUnit = function() return 1429 end,
			GetMapInfo = function(id)
				return ({
					[1429] = { mapType = 3, parentMapID = 1415, name = "Elwynn Forest" },
					[1415] = { mapType = 2, parentMapID = 947, name = "Eastern Kingdoms" },
				})[id]
			end,
			GetPlayerMapPosition = function()
				return { GetXY = function() return 0.25, 0.5 end }
			end,
		}
		_G.GetRealZoneText = function() return world.zone end
		_G.GetZoneText = function() return world.zone end
		_G.IsInGuild = function() return false end
		_G.SendChatMessage = function() end
		_G.C_ChatInfo = nil
		_G.PlaySound = function() end
		_G.SOUNDKIT = nil
		_G.geterrorhandler = function() return function(err) error(err, 0) end end
		_G.UNKNOWN = "Unknown"
		_G.UNKNOWNOBJECT = "Unknown"
		_G.NUM_BAG_SLOTS = 4
		_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil
		_G.RAID_CLASS_COLORS = nil
	end)

	after_each(function()
		for _, k in ipairs(STUBBED) do
			_G[k] = saved[k]
		end
	end)

	local function load()
		local ns = {}
		local pure = {
			"Settings", "RaidData", "Raids", "Points", "Flavour", "Dex", "Milestones", "Friends", "Catch", "Shards",
		}
		for _, f in ipairs(pure) do
			LoadAddonFile("src/" .. f .. ".lua", ns)
		end
		LoadAddonFile("src/Toast.lua", ns)
		LoadAddonFile("src/Capture.lua", ns)
		LoadAddonFile("src/Tooltip.lua", ns)
		return ns
	end

	local function fire(event, ...)
		for _, f in ipairs(frames) do
			if f.onEvent and (f.events[event] or f.unitEvents[event]) then
				f.onEvent(f, event, ...)
			end
		end
	end

	local function flush()
		while #timers > 0 do
			table.remove(timers, 1)()
		end
	end

	local function putShard(slot, guid)
		world.bags[0][slot] = { id = 6265, guid = guid }
	end

	-- Loads the addon, runs OnLoaded and the login baseline. Returns ns, db, printed lines.
	local function boot(db)
		local ns = load()
		local printed = {}
		ns.Print = function(text) printed[#printed + 1] = text end
		db = db or {}
		db.settings = db.settings or { popup = false, sound = false, announce = false }
		ns.OnLoaded(db)
		fire("PLAYER_ENTERING_WORLD")
		flush()
		return ns, db, printed
	end

	local HOGGER = {
		name = "Hogger", guid = "Creature-0-1-0-2-448-3", level = 11, classification = "elite",
		creatureType = "Humanoid", family = nil,
	}

	local function drain(castGUID, targetName)
		fire("UNIT_SPELLCAST_SENT", "player", targetName, castGUID, 1120)
		fire("UNIT_SPELLCAST_CHANNEL_START", "player", castGUID, 1120)
	end

	local function count(t)
		local n = 0
		for _ in pairs(t) do
			n = n + 1
		end
		return n
	end

	it("loads and defines ns.OnLoaded, the hook lists and the tooltip post-call", function()
		local ns = load()
		assert.equal("function", type(ns.OnLoaded))
		assert.same({}, ns.onCatch)
		assert.same({}, ns.onLoaded)
		assert.equal(1, #postCalls)
		assert.equal(0, postCalls[1].kind)
	end)

	describe("full catch", function()
		it("SENT -> CHANNEL_START -> new shard GUID records one mob and its soul", function()
			putShard(1, "OLD")
			world.target = HOGGER
			local ns, db = boot()
			assert.same({ soul = false, seen = world.epoch }, db.shardSouls.OLD)
			assert.is_nil(db.shardSlots)

			local caught = {}
			table.insert(ns.onCatch, function(result, entry) caught[#caught + 1] = { result, entry } end)

			drain("cast1", "Hogger")
			world.target = nil -- the corpse is gone; the details were read at SENT
			world.clock = 108
			fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
			putShard(2, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()

			local mob = db.mobs.Hogger
			assert.is_not_nil(mob)
			assert.equal(11, mob.minLevel)
			assert.equal("elite", mob.classification)
			assert.equal(1, mob.places["Elwynn Forest"].count)
			assert.equal(25, mob.places["Elwynn Forest"].x)
			assert.equal("Eastern Kingdoms", db.places["Elwynn Forest"].group)
			local soul = db.shardSouls.NEW.soul
			assert.equal("Hogger", soul.name)
			assert.equal("ffcc33", soul.color)
			assert.equal("Elwynn Forest", soul.zone)
			assert.is_false(db.shardSouls.OLD.soul)
			assert.equal(1, #caught)
			assert.equal("mob", caught[1][2].kind)
			assert.is_true(caught[1][1].isNew)
		end)

		it("a second new shard under the same capture stays soulless", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED")
			flush()
			world.clock = 101
			putShard(2, "B")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.equal(1, db.mobs.Hogger.places["Elwynn Forest"].count)
			assert.equal("Hogger", db.shardSouls.A.soul.name)
			assert.is_false(db.shardSouls.B.soul)
		end)

		it("two new shards in one scan: neither is named, and the capture is spent", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			putShard(1, "A")
			putShard(2, "B")
			fire("BAG_UPDATE_DELAYED")
			flush()
			world.clock = 101
			putShard(3, "C")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
			assert.is_false(db.shardSouls.A.soul)
			assert.is_false(db.shardSouls.B.soul)
			assert.is_false(db.shardSouls.C.soul)
		end)

		it("a new shard in a quiet scan spends the capture, so a later shard isn't named", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			world.cursor = "item"
			putShard(1, "KILL")
			fire("BAG_UPDATE_DELAYED")
			flush()
			world.cursor = nil
			world.clock = 102
			putShard(2, "TRADED")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.KILL.soul)
			assert.is_false(db.shardSouls.TRADED.soul)
			assert.same({}, db.mobs)
		end)

		it("new shards while the mail, trade or vendor window is open are soulless", function()
			world.target = HOGGER
			local _, db = boot()
			local slot = 0
			for _, pair in ipairs({ { "MAIL_SHOW", "MAIL_CLOSED" }, { "TRADE_SHOW", "TRADE_CLOSED" },
				{ "MERCHANT_SHOW", "MERCHANT_CLOSED" } }) do
				world.clock = world.clock + 30
				drain("cast" .. pair[1], "Hogger")
				fire(pair[1])
				slot = slot + 1
				putShard(slot, pair[1])
				fire("BAG_UPDATE_DELAYED")
				flush()
				fire(pair[2])
				flush()
				assert.is_false(db.shardSouls[pair[1]].soul)
			end
			assert.same({}, db.mobs)
		end)

		it("a shard is saved even when recording its catch errors", function()
			world.target = HOGGER
			local errors = {}
			local ns, db = boot()
			_G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
			ns.dex.recordMob = function() error("boom", 0) end
			drain("cast1", "Hogger")
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.NEW.soul)
			assert.same({ "boom" }, errors)
		end)

		it("a hidden name records an Unknown soul in the zone", function()
			world.target = { name = SECRET, guid = SECRET, level = SECRET }
			local _, db = boot()
			drain("cast1", SECRET)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
			assert.equal(1, db.unknown["Elwynn Forest"].count)
			local soul = db.shardSouls.NEW.soul
			assert.is_true(soul.unknown)
			assert.equal("Unknown soul", soul.name)
		end)

		it("a hidden player name goes to Unknown soul too", function()
			world.target = { name = "Unknown", player = true }
			local _, db = boot()
			drain("cast1", nil)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.players)
			assert.equal(1, db.unknown["Elwynn Forest"].count)
		end)

		it("a PvP kill records the player with class, race, guild and realm", function()
			-- On WoW: Forever UnitName's second value is the second half of the name
			-- ("Forgot", "Shards" for "Forgot Shards"), not a realm.
			world.target = {
				name = "Bob", realm = "Far", guid = "Player-1-AB", level = 30, player = true,
				class = "ROGUE", race = "Human", guild = "Stabby",
			}
			local _, db = boot()
			drain("cast1", "Bob Far")
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			local p = db.players["Bob Far-Home"]
			assert.is_not_nil(p)
			assert.equal("Bob Far", p.name)
			assert.equal("Home", p.realm)
			assert.equal("ROGUE", p.class)
			assert.equal("Human", p.race)
			assert.equal("Stabby", p.guild)
		end)

		it("a shard with no capture is soulless and records nothing", function()
			local _, db = boot()
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.NEW.soul)
			assert.same({}, db.mobs)
			assert.same({}, db.unknown)
		end)

		it("a shard more than 3 s after the channel stopped is soulless", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
			world.clock = 103.5
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.NEW.soul)
			assert.same({}, db.mobs)
		end)

		it("an unreadable channel start clears the capture", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", SECRET, SECRET)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.NEW.soul)
		end)

		it("a Drain Soul sent at a different unit than the target gives no name", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Some Mouseover Mob")
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
			assert.equal(1, db.unknown["Elwynn Forest"].count)
		end)

		it("reads the target at CHANNEL_START when SENT did not match", function()
			world.target = HOGGER
			local _, db = boot()
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast9", 8288) -- another rank
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_not_nil(db.mobs.Hogger)
		end)

		it("Shadowburn: a shard within 8 s of the cast is named", function()
			world.target = HOGGER
			local _, db = boot()
			fire("UNIT_SPELLCAST_SENT", "player", "Hogger", "sb1", 18867)
			fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb1", 18867)
			world.clock = 104
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_not_nil(db.mobs.Hogger)
		end)

		it("other spells open no capture", function()
			world.target = HOGGER
			local _, db = boot()
			fire("UNIT_SPELLCAST_SENT", "player", "Hogger", "sb1", 686)
			fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb1", 686)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
		end)

		it("new shards while something is on the cursor or the bank is open are soulless", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			world.cursor = "item"
			putShard(1, "CUR")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.CUR.soul)
			world.cursor = nil
			fire("BANKFRAME_OPENED")
			putShard(2, "BANK")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.BANK.soul)
			assert.same({}, db.mobs)
		end)

		it("files raid kills by NPC id under Raids", function()
			world.target = { name = "Ragnaros", guid = "Creature-0-1-409-2-11502-3", level = -1, classification = "worldboss" }
			world.instanceType, world.instanceID, world.zone = "raid", 409, "Molten Core"
			local _, db = boot()
			drain("cast1", "Ragnaros")
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_not_nil(db.raids[11502])
			assert.is_nil(db.mobs.Ragnaros)
		end)

		it("a mouseover SENT whose cast id differs from the channel's still blocks the target's name", function()
			world.target = HOGGER
			local _, db = boot()
			fire("UNIT_SPELLCAST_SENT", "player", "Some Mouseover Mob", "castA", 1120)
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", "castB", 1120)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
			assert.equal(1, db.unknown["Elwynn Forest"].count)
		end)

		it("a mouseover SENT blocks the target's name when the channel's cast id is nil or secret", function()
			world.target = HOGGER
			local _, db = boot()
			fire("UNIT_SPELLCAST_SENT", "player", "Some Mouseover Mob", "castA", 1120)
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 1120)
			putShard(1, "N1")
			fire("BAG_UPDATE_DELAYED")
			flush()
			world.clock = 130
			fire("UNIT_SPELLCAST_SENT", "player", "Some Mouseover Mob", "castC", 1120)
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", STR_SECRET, 1120)
			putShard(2, "N2")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
			assert.equal(2, db.unknown["Elwynn Forest"].count)
		end)

		it("an old SENT (over 1 s) is not used to cross-check; the target is read", function()
			world.target = HOGGER
			local _, db = boot()
			fire("UNIT_SPELLCAST_SENT", "player", "Some Mouseover Mob", "castA", 1120)
			world.clock = 102
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", "castB", 1120)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_not_nil(db.mobs.Hogger)
		end)

		it("a secret SENT target name gives an Unknown soul, even with a readable target", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", STR_SECRET)
			putShard(1, "N1")
			fire("BAG_UPDATE_DELAYED")
			flush()
			world.clock = 130
			fire("UNIT_SPELLCAST_SENT", "player", SECRET, "castA", 1120)
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", "castB", 1120)
			putShard(2, "N2")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
			assert.equal(2, db.unknown["Elwynn Forest"].count)
		end)

		it("a string secret in the target name gives an Unknown soul", function()
			world.target = { name = STR_SECRET, guid = "Creature-0-1-0-2-448-3" }
			local _, db = boot()
			drain("cast1", STR_SECRET)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({}, db.mobs)
			assert.equal(1, db.unknown["Elwynn Forest"].count)
		end)

		it("a string secret spell id on a channel start clears the capture", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast2", STR_SECRET)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.NEW.soul)
		end)

		it("a shard unreadable at the baseline is never named when it becomes readable", function()
			world.bags[0][1] = { id = 6265, guid = STR_SECRET }
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			world.bags[0][1].guid = "OLD" -- the same old shard, now readable
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_false(db.shardSouls.OLD.soul)
			assert.same({}, db.mobs)
			-- every slot readable twice in a row: catches work again
			world.clock = 101
			fire("BAG_UPDATE_DELAYED")
			flush()
			drain("cast2", "Hogger")
			putShard(2, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.equal("Hogger", db.shardSouls.NEW.soul.name)
		end)

		it("a bank-open scan does not forget long-unseen shards; only the login scan does", function()
			local _, db = boot({ shardSouls = { GONE = { soul = { name = "Wolf" }, seen = world.epoch } } })
			assert.is_not_nil(db.shardSouls.GONE)
			world.epoch = world.epoch + 31 * 86400
			fire("BANKFRAME_OPENED")
			fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "x", 686) -- queues a scan
			flush()
			assert.is_not_nil(db.shardSouls.GONE)
		end)

		it("a scan that errors inside the timer goes to the error handler", function()
			local errors = {}
			_G.geterrorhandler = function() return function(err) errors[#errors + 1] = err end end
			local ns = boot()
			ns.Shards.update = function() error("scan boom") end
			fire("BAG_UPDATE_DELAYED")
			assert.has_no.errors(flush)
			assert.equal(1, #errors)
			assert.truthy(tostring(errors[1]):find("scan boom", 1, true))
		end)

		it("announces through C_ChatInfo, and a failing announce can't skip the catch hooks", function()
			world.target = HOGGER
			local ns, db = boot({ settings = { popup = false, sound = false, announce = true } })
			_G.IsInGuild = function() return true end
			local sentChat, hooked = {}, 0
			_G.C_ChatInfo = { SendChatMessage = function(text, channel) sentChat[#sentChat + 1] = channel .. ":" .. text end }
			_G.SendChatMessage = function() error("deprecated") end
			ns.Milestones.check = function() return { { text = "Big one", announce = true } } end
			table.insert(ns.onCatch, function() hooked = hooked + 1 end)
			drain("cast1", "Hogger")
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.same({ "GUILD:Soul-Dex: Big one!" }, sentChat)
			assert.equal(1, hooked)
			-- no C_ChatInfo and a global that errors: the hooks still run, nothing escapes
			_G.C_ChatInfo = nil
			world.clock = 110
			drain("cast2", "Hogger")
			putShard(2, "B")
			fire("BAG_UPDATE_DELAYED")
			assert.has_no.errors(flush)
			assert.equal(2, hooked)
			assert.is_not_nil(db.shardSouls.B)
		end)

		it("the old slot map is discarded and a junk soul map replaced", function()
			local _, db = boot({ shardSlots = { ["0:1"] = { name = "Wolf" } }, shardSouls = "junk" })
			assert.is_nil(db.shardSlots)
			assert.equal("table", type(db.shardSouls))
		end)

		it("forgets nothing on a scan before the baseline has run", function()
			local ns = load()
			ns.Print = function() end
			local db = { settings = { popup = false, sound = false, announce = false } }
			ns.OnLoaded(db)
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED") -- before PLAYER_ENTERING_WORLD + 1 s: ignored
			assert.equal(0, #timers)
			assert.equal(0, count(db.shardSouls))
		end)
	end)

	describe("startup", function()
		it("registers the spell events for the player only and never the combat log", function()
			boot()
			local f = frames[1]
			assert.equal("player", f.unitEvents.UNIT_SPELLCAST_SENT)
			assert.equal("player", f.unitEvents.UNIT_SPELLCAST_CHANNEL_START)
			assert.is_true(f.events.BAG_UPDATE_DELAYED)
			assert.is_nil(f.events.COMBAT_LOG_EVENT_UNFILTERED)
		end)

		it("a refused event does not stop the others; one chat note", function()
			world.refuse.BANKFRAME_OPENED = true
			local _, _, printed = boot()
			assert.is_true(frames[1].events.BAG_UPDATE_DELAYED)
			assert.equal("player", frames[1].unitEvents.UNIT_SPELLCAST_SUCCEEDED)
			assert.equal(1, #printed)
			assert.truthy(printed[1]:find("BANKFRAME_OPENED", 1, true))
		end)

		it("OnLoaded still runs the on-load hooks when Capture.start errors", function()
			local ns = load()
			local printed, ran = {}, {}
			ns.Print = function(text) printed[#printed + 1] = text end
			_G.geterrorhandler = function() return function() end end
			ns.Capture.start = function() error("boom") end
			table.insert(ns.onLoaded, function(db) ran[#ran + 1] = db end)
			table.insert(ns.onLoaded, function() ran[#ran + 1] = "second" end)
			local db = {}
			ns.OnLoaded(db)
			assert.equal(2, #ran)
			assert.equal(db, ran[1])
			assert.is_not_nil(ns.dex)
			assert.truthy(printed[1]:find("could not start", 1, true))
		end)
	end)

	describe("secret guards", function()
		it("readUnit returns only readable fields", function()
			local ns = load()
			world.target = { name = "Wolf", guid = SECRET, level = SECRET, classification = "normal", family = SECRET }
			local info = ns.Capture.readUnit("target")
			assert.equal("Wolf", info.name)
			assert.is_nil(info.guid)
			assert.is_nil(info.level)
			assert.is_nil(info.family)
			assert.equal("normal", info.classification)
		end)

		it("readUnit treats a hidden, missing or UNKNOWN name as unknown", function()
			local ns = load()
			world.target = { name = SECRET, player = true }
			assert.same({ unknown = true, isPlayer = true }, ns.Capture.readUnit("target"))
			world.target = { name = "Unknown" }
			assert.is_true(ns.Capture.readUnit("target").unknown)
			world.target = nil
			assert.is_true(ns.Capture.readUnit("target").unknown)
		end)

		it("buildContext falls back when zone and map values are secret", function()
			local ns = load()
			world.zone = SECRET
			_G.C_Map.GetBestMapForUnit = function() return SECRET end
			_G.UnitLevel = function() return SECRET end
			local ctx = ns.Capture.buildContext()
			assert.equal("Unknown", ctx.zone)
			assert.equal("Other", ctx.group)
			assert.is_nil(ctx.myLevel)
			assert.is_nil(ctx.x)
		end)

		it("shardGuids skips secret item IDs and GUIDs", function()
			local ns = load()
			world.bags[0][1] = { id = 6265, guid = "A" }
			world.bags[0][2] = { id = SECRET, guid = "B" }
			world.bags[0][3] = { id = 6265, guid = SECRET }
			world.bags[0][4] = { id = 1234, guid = "D" }
			world.bags[4] = { [16] = { id = 6265, guid = "E" } }
			assert.same({ "A", "E" }, ns.Capture.shardGuids())
		end)
	end)

	describe("spellKind", function()
		it("knows every rank by id and others by name", function()
			local ns = load()
			local names = { drainsoul = "Drain Soul", shadowburn = "Shadowburn" }
			local function nameOf(id) return ({ [99] = "Drain Soul", [98] = "Shadowburn" })[id] end
			assert.equal("drainsoul", ns.Capture.spellKind(11675, nameOf, names))
			assert.equal("shadowburn", ns.Capture.spellKind(18871, nameOf, names))
			assert.equal("drainsoul", ns.Capture.spellKind(99, nameOf, names))
			assert.equal("shadowburn", ns.Capture.spellKind(98, nameOf, names))
			assert.is_nil(ns.Capture.spellKind(686, nameOf, names))
			assert.is_nil(ns.Capture.spellKind(99, nameOf, {}))
		end)
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
		it("records a player known only by the isPlayer flag", function()
			local ns, dex = setup()
			local cand = { info = { name = "Bob", realm = "R", isPlayer = true } }
			local _, kind = ns.Capture.recordCatch(dex, cand, ctx, "none")
			assert.equal("player", kind)
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
		it("records a catch in a raid-type instance we do not list as a mob under Raids", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-9999-2-777-3", info = { name = "Odd Beast", classification = "normal" } }
			local raidCtx = { time = 100, myLevel = 20, zone = "Odd Keep", group = "Raids" }
			local r, kind = ns.Capture.recordCatch(dex, cand, raidCtx, "raid", 9999)
			assert.equal("mob", kind)
			assert.is_true(r.isNew)
			assert.is_not_nil(dex.db.mobs["Odd Beast"])
			assert.same({}, dex.db.raids)
			assert.equal("Raids", dex.db.places["Odd Keep"].group)
		end)
		it("records everything else as a mob", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-0-2-299-3", info = { name = "Young Wolf", classification = "normal" } }
			local r, kind = ns.Capture.recordCatch(dex, cand, ctx, "none")
			assert.equal("mob", kind)
			assert.equal(1, r.placeCount)
		end)
		it("refuses a candidate without a name, or an unknown one", function()
			local ns, dex = setup()
			assert.is_nil(ns.Capture.recordCatch(dex, { info = {} }, ctx, "none"))
			assert.is_nil(ns.Capture.recordCatch(dex, { info = { name = "X", unknown = true } }, ctx, "none"))
		end)
	end)

	describe("Toast text", function()
		it("builds subtitles", function()
			local ns = load()
			local mob = { kind = "mob", placeCount = 3, points = 5 }
			local player = { kind = "player", points = 10 }
			local raid = { kind = "raid", points = 25 }
			assert.equal("Elwynn Forest \194\183 #3 here \194\183 |cff7dff6a+5 pts|r", ns.Toast.subtitle(mob, "Elwynn Forest"))
			assert.equal("Elwynn Forest \194\183 |cff7dff6a+10 pts|r", ns.Toast.subtitle(player, "Elwynn Forest"))
			assert.equal("Molten Core \194\183 |cff7dff6a+25 pts|r", ns.Toast.subtitle(raid, "Molten Core"))
		end)
		it("finds the shard icon without the removed GetItemIcon", function()
			local ns = load()
			local byId = { GetItemIconByID = function(id) return id == 6265 and 134075 or nil end }
			assert.equal(134075, ns.Toast.shardIcon(byId, nil))
			assert.equal(42, ns.Toast.shardIcon(nil, function() return 42 end))
			assert.equal(ns.Toast.SHARD_ICON_FILE, ns.Toast.shardIcon(nil, nil))
			local blocked = { GetItemIconByID = function() error("blocked") end }
			assert.equal(ns.Toast.SHARD_ICON_FILE, ns.Toast.shardIcon(blocked, nil))
		end)
		it("runs every catch hook even when one errors", function()
			local ns = load()
			local calls, errors = {}, {}
			local hooks = {
				function(a, b) calls[#calls + 1] = a .. b end,
				function() error("boom") end,
				function(a) calls[#calls + 1] = a end,
			}
			ns.Capture.runHooks(hooks, function(e) errors[#errors + 1] = e end, "x", "y")
			assert.same({ "xy", "x" }, calls)
			assert.equal(1, #errors)
			assert.is_truthy(errors[1]:find("boom"))
		end)
		it("marks rarity on mobs only", function()
			local ns = load()
			assert.equal("Hogger  (Elite)", ns.Toast.nameLine({ name = "Hogger", classification = "elite" }))
			assert.equal("Bob", ns.Toast.nameLine({ name = "Bob", classification = "elite", class = "ROGUE" }))
			assert.equal("Wolf", ns.Toast.nameLine({ name = "Wolf", classification = "normal" }))
			assert.equal("Boss", ns.Toast.rarityLabel("worldboss"))
		end)
	end)

	describe("Tooltip", function()
		local function tipStub(extra)
			local tip = { lines = {} }
			function tip:AddLine(text) self.lines[#self.lines + 1] = text end
			tip.Show = function() end
			tip.IsForbidden = function() return false end
			for k, v in pairs(extra or {}) do
				tip[k] = v
			end
			return tip
		end

		local function withSouls(ns)
			ns.db = {
				shardSouls = {
					A = { soul = { name = "Wolf", zone = "Z", time = 1 }, seen = 1 },
					B = { soul = false, seen = 1 },
					U = { soul = { name = "Unknown soul", unknown = true, zone = "Z", time = 1 }, seen = 1 },
				},
			}
		end

		it("builds the two lines", function()
			local ns = load()
			local soul = { name = "Hogger", color = "ffcc33", zone = "Elwynn Forest", time = 5 }
			local first, second = ns.Tooltip.lines(soul, function(fmt, t) return fmt .. t end)
			assert.equal("Soul of |cffffcc33Hogger|r", first)
			assert.equal("Elwynn Forest \194\183 %d %b %Y5", second)
		end)

		it("shows an unknown soul in grey", function()
			local ns = load()
			local first = ns.Tooltip.lines({ name = "Unknown soul", unknown = true, zone = "Z" })
			assert.equal("|cff9d9d9dUnknown soul|r", first)
		end)

		it("adds lines only for a named shard, found by the data GUID", function()
			local ns = load()
			withSouls(ns)
			local tip = tipStub()
			ns.Tooltip.onItem(tip, { id = 6265, guid = "A" })
			assert.equal(2, #tip.lines)
			assert.equal("Soul of |cffffffffWolf|r", tip.lines[1])
			tip = tipStub()
			ns.Tooltip.onItem(tip, { id = 6265, guid = "B" }) -- soulless
			ns.Tooltip.onItem(tip, { id = 6265, guid = "ZZZ" }) -- never seen
			ns.Tooltip.onItem(tip, { id = 1234, guid = "A" }) -- not a shard
			ns.Tooltip.onItem(tip, { id = SECRET, guid = "A" })
			ns.Tooltip.onItem(tip, SECRET)
			assert.equal(0, #tip.lines)
			ns.Tooltip.onItem(tip, { id = 6265, guid = "U" })
			assert.equal("|cff9d9d9dUnknown soul|r", tip.lines[1])
		end)

		it("finds the GUID from the bag slot when the data GUID is secret", function()
			local ns = load()
			withSouls(ns)
			world.bags[0][5] = { id = 6265, guid = "A" }
			local tip = tipStub({
				GetPrimaryTooltipInfo = function()
					return { getterName = "GetBagItem", getterArgs = { 0, 5 } }
				end,
			})
			ns.Tooltip.onItem(tip, { id = 6265, guid = SECRET })
			assert.equal(2, #tip.lines)
		end)

		it("leaves forbidden or protected tooltips alone", function()
			local ns = load()
			withSouls(ns)
			local tip = tipStub({ IsForbidden = function() return true end })
			ns.Tooltip.onItem(tip, { id = 6265, guid = "A" })
			assert.equal(0, #tip.lines)
			_G.C_RestrictedActions = { CheckAllowProtectedFunctions = function() return false end }
			tip = tipStub()
			ns.Tooltip.onItem(tip, { id = 6265, guid = "A" })
			assert.equal(0, #tip.lines)
		end)

		it("falls back to SetBagItem without TooltipDataProcessor", function()
			_G.TooltipDataProcessor = nil
			local hooked
			_G.hooksecurefunc = function(_, method) hooked = method end
			local ns = load()
			assert.equal("SetBagItem", hooked)
			withSouls(ns)
			world.bags[0][1] = { id = 6265, guid = "A" }
			world.bags[0][2] = { id = 6265, guid = "B" }
			local tip = tipStub()
			ns.Tooltip.onSetBagItem(tip, 0, 1)
			assert.equal(2, #tip.lines)
			tip = tipStub()
			ns.Tooltip.onSetBagItem(tip, 0, 2)
			ns.Tooltip.onSetBagItem(tip, 0, 3)
			assert.equal(0, #tip.lines)
		end)
	end)
end)
