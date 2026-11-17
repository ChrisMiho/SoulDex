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
	"SendChatMessage", "C_ChatInfo", "IsEncounterInProgress", "PlaySound", "StopSound", "SOUNDKIT", "geterrorhandler",
	"UNKNOWN", "UNKNOWNOBJECT", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "RAID_CLASS_COLORS",
	"UnitExists", "UnitIsUnit", "UnitIsAFK", "UnitIsDND", "GetUnitName", "ChatFrameUtil",
	"ChatFrame_AddMessageEventFilter", "ChatEdit_GetLastTellTarget", "ChatEdit_SetLastTellTarget",
	"InCombatLockdown", "C_PlayerInteractionManager",
}

describe("Capture glue", function()
	local saved
	local world -- the fake game state the stubs read
	local frames, timers, tickers, postCalls

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
		frames, timers, tickers, postCalls = {}, {}, {}, {}
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
		_G.C_Timer = {
			After = function(_, fn) timers[#timers + 1] = fn end,
			NewTicker = function(_, fn)
				local ticker = { fn = fn }
				function ticker:Cancel() self.cancelled = true end
				tickers[#tickers + 1] = ticker
				return ticker
			end,
		}
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
		_G.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
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
		_G.IsEncounterInProgress = function() return false end
		_G.PlaySound = function() end
		_G.StopSound = nil
		_G.SOUNDKIT = nil
		_G.geterrorhandler = function() return function(err) error(err, 0) end end
		_G.UNKNOWN = "Unknown"
		_G.UNKNOWNOBJECT = "Unknown"
		_G.NUM_BAG_SLOTS = 4
		_G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil
		_G.RAID_CLASS_COLORS = nil
		-- Unset unless a test sets them: without them SoulDex never whispers.
		_G.UnitExists = nil
		_G.UnitIsUnit = nil
		_G.UnitIsAFK = nil
		_G.UnitIsDND = nil
		_G.GetUnitName = nil
		_G.ChatFrameUtil = nil
		_G.ChatFrame_AddMessageEventFilter = nil
		_G.ChatEdit_GetLastTellTarget = nil
		_G.ChatEdit_SetLastTellTarget = nil
		_G.InCombatLockdown = nil
		_G.C_PlayerInteractionManager = nil
	end)

	after_each(function()
		for _, k in ipairs(STUBBED) do
			_G[k] = saved[k]
		end
	end)

	local function load()
		local ns = {}
		local pure = {
			"Settings", "RaidData", "ForeverData", "Raids", "Points", "Rarity", "Ranks", "Flavour", "Dex", "Milestones",
			"Friends", "Catch", "Whisper", "Shards",
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
		assert.equal(2, #postCalls)
		assert.equal(0, postCalls[1].kind)
		assert.equal(2, postCalls[2].kind)
	end)

	it("adds no unit post-call on a client without the Unit tooltip type", function()
		_G.Enum = { TooltipDataType = { Item = 0 } }
		load()
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
			assert.equal("ffd25a", soul.color)
			assert.equal("Elwynn Forest", soul.zone)
			assert.is_false(db.shardSouls.OLD.soul)
			assert.equal(1, #caught)
			assert.equal("mob", caught[1][2].kind)
			assert.is_true(caught[1][1].isNew)
		end)

		-- WoW: Forever's Drain Soul can drop a shard on a damage tick as well as at the kill.
		it("a second shard under the same capture gets its soul; the catch counts once", function()
			world.target = HOGGER
			local ns, db = boot()
			local caught = 0
			table.insert(ns.onCatch, function() caught = caught + 1 end)
			drain("cast1", "Hogger")
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED")
			flush()
			world.clock = 101
			putShard(2, "B")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.equal(1, db.mobs.Hogger.places["Elwynn Forest"].count)
			assert.equal(1, caught)
			assert.equal("Hogger", db.shardSouls.A.soul.name)
			assert.equal("Hogger", db.shardSouls.B.soul.name)
			assert.equal("ffd25a", db.shardSouls.B.soul.color)
			assert.are_not.equal(db.shardSouls.A.soul, db.shardSouls.B.soul) -- each its own copy
		end)

		it("two new shards in one scan both get the soul, counted once", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			putShard(1, "A")
			putShard(2, "B")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.equal(1, db.mobs.Hogger.places["Elwynn Forest"].count)
			assert.equal(1, db.today.count)
			assert.equal("Hogger", db.shardSouls.A.soul.name)
			assert.equal("Hogger", db.shardSouls.B.soul.name)
		end)

		it("a shard more than 3 s after the channel stopped stays soulless, even after a named one", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED")
			flush()
			fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
			world.clock = world.clock + 3.5
			putShard(2, "B")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.equal("Hogger", db.shardSouls.A.soul.name)
			assert.is_false(db.shardSouls.B.soul)
		end)

		it("an extra shard while another mob's capture is live stays soulless", function()
			world.target = HOGGER
			local _, db = boot()
			drain("cast1", "Hogger")
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED")
			flush()
			fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
			world.clock = world.clock + 1
			world.target = { name = "Wolf", guid = "Creature-0-1-0-2-299-9", level = 5, classification = "normal" }
			drain("cast2", "Wolf")
			-- the Wolf dies at once with two shards, the Hogger's grace still running
			putShard(2, "B")
			putShard(3, "C")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.equal("Wolf", db.shardSouls.B.soul.name)
			assert.is_false(db.shardSouls.C.soul)
			assert.equal(1, db.mobs.Hogger.places["Elwynn Forest"].count)
			assert.equal(1, db.mobs.Wolf.places["Elwynn Forest"].count)
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

		-- WoW: Forever: a window's close event may never come (seen with the bank). The open
		-- flag then has to end some other way, or every later shard stays soulless.
		describe("a window whose close event never comes", function()
			-- WoW: Forever's bank is interaction type 67 (CharacterBanker), not 8 (Banker).
			local BANKER, CHARACTER_BANKER, MERCHANT = 8, 67, 5

			local function claimAfter()
				world.clock = world.clock + 30
				drain("cast" .. world.clock, "Hogger")
				putShard(1, "AFTER")
				fire("BAG_UPDATE_DELAYED")
				flush()
			end

			it("ends when the game says it is no longer open", function()
				world.target = HOGGER
				local open = { [CHARACTER_BANKER] = true }
				_G.C_PlayerInteractionManager = {
					IsInteractingWithNpcOfType = function(kind) return open[kind] == true end,
				}
				local _, db = boot()
				fire("BANKFRAME_OPENED")
				open[CHARACTER_BANKER] = nil -- walked away: no BANKFRAME_CLOSED
				claimAfter()
				assert.equal("Hogger", db.shardSouls.AFTER.soul.name)
			end)

			it("stays open while the game says it is open, as any kind of banker", function()
				for _, banker in ipairs({ BANKER, CHARACTER_BANKER }) do
					world.target = HOGGER
					world.bags = { [0] = {} }
					frames = {}
					_G.C_PlayerInteractionManager = {
						IsInteractingWithNpcOfType = function(kind) return kind == banker end,
					}
					local _, db = boot()
					fire("BANKFRAME_OPENED")
					claimAfter()
					assert.is_false(db.shardSouls.AFTER.soul)
				end
			end)

			it("uses the client's Enum for the bank's types", function()
				world.target = HOGGER
				_G.Enum = { TooltipDataType = { Item = 0 }, PlayerInteractionType = { CharacterBanker = 90 } }
				_G.C_PlayerInteractionManager = {
					IsInteractingWithNpcOfType = function(kind) return kind == 90 end,
				}
				local _, db = boot()
				fire("BANKFRAME_OPENED")
				claimAfter()
				assert.is_false(db.shardSouls.AFTER.soul)
			end)

			it("stays open when the game's answer is secret", function()
				world.target = HOGGER
				_G.C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return SECRET end }
				local _, db = boot()
				fire("BANKFRAME_OPENED")
				claimAfter()
				assert.is_false(db.shardSouls.AFTER.soul)
			end)

			it("ends on the interaction-hide event for its own window", function()
				world.target = HOGGER
				local _, db = boot()
				fire("BANKFRAME_OPENED")
				fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", CHARACTER_BANKER)
				claimAfter()
				assert.equal("Hogger", db.shardSouls.AFTER.soul.name)
			end)

			it("is not ended by another window's hide, or an unreadable one", function()
				world.target = HOGGER
				local _, db = boot()
				fire("BANKFRAME_OPENED")
				fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", MERCHANT)
				fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", SECRET)
				claimAfter()
				assert.is_false(db.shardSouls.AFTER.soul)
			end)
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
			assert.same({ "GUILD:SoulDex: Big one!" }, sentChat)
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

		it("shows the popup and a chat line when a repeat claim earns a mastery star", function()
			world.target = HOGGER
			local ns, db, printed = boot({ settings = { popup = true, sound = false, announce = false } })
			local shown, emblems = {}, {}
			ns.Toast.show = function(result, _, _, _, emblem)
				shown[#shown + 1] = result
				emblems[#emblems + 1] = emblem
			end
			for i = 1, 10 do
				world.clock = world.clock + 10
				drain("cast" .. i, "Hogger")
				putShard(i, "G" .. i)
				fire("BAG_UPDATE_DELAYED")
				flush()
			end
			assert.equal(2, #shown) -- the first claim, then the 10th
			assert.equal(1, shown[2].stars)
			assert.is_false(shown[2].isNew)
			assert.truthy(table.concat(printed, "\n"):find("Mastery: Hogger reached |cff9dff3a1 star|r (+2 pts).", 1, true))
			assert.equal(7, ns.dex:score())
			assert.equal(ns.Ranks.of(ns.dex:score()).emblem, emblems[2])
			assert.is_not_nil(db.mobs.Hogger)
		end)

		it("picks a sound for the claim: a rank, a boss, or the usual", function()
			local ns = boot()
			_G.SOUNDKIT = { UI_EPICLOOT_TOAST = 1, UI_LEGENDARY_LOOT_TOAST = 2, LEVEL_UP = 3 }
			local S = ns.Capture.soundFor
			assert.equal(1, S({ kind = "mob", points = 5 }))
			assert.equal(2, S({ kind = "raid", points = 25 }))
			assert.equal(1, S({ kind = "player", points = 25 }))
			assert.equal(3, S({ kind = "mob", points = 1 }, { name = "Reaper" }))
			_G.SOUNDKIT = nil
			assert.equal(888, S({ kind = "mob", points = 1 }, { name = "Reaper" }))
			assert.equal(8959, S({ kind = "raid", points = 25 }))
		end)

		it("prints a line for every claim when chatter is on, and none when it is off", function()
			world.target = HOGGER
			local _, _, printed = boot({ settings = { popup = false, sound = false, announce = false, chatter = true } })
			drain("cast1", "Hogger")
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED")
			flush()
			local text = table.concat(printed, "\n")
			assert.truthy(text:find("Hogger", 1, true))
			assert.truthy(text:find("(+5 pts)", 1, true))
		end)

		describe("ranking up", function()
			-- Two ranks, the second at one elite's worth of points.
			local function bootRanks(settings)
				world.target = HOGGER
				local ns, db, printed = boot({ settings = settings })
				ns.Ranks.LIST = { { min = 0, name = "Initiate" }, { min = 5, name = "Reaper" }, { min = 500, name = "Top" } }
				ns.Ranks.ANNOUNCE_FROM = 2
				return ns, db, printed
			end

			local function catchHogger(cast, slot, guid)
				world.clock = world.clock + 10
				drain(cast, "Hogger")
				putShard(slot, guid)
				fire("BAG_UPDATE_DELAYED")
				flush()
			end

			it("prints the new rank and hands it to the popup, once", function()
				local ns, _, printed = bootRanks({ popup = true, sound = false, announce = false })
				local shown, souls = {}, 0
				ns.Toast.show = function() souls = souls + 1 end
				ns.Toast.showRank = function(rank) shown[#shown + 1] = rank end
				catchHogger("cast1", 1, "A")
				assert.equal(1, souls) -- the soul's own popup still shows
				assert.equal("Reaper", shown[1].name)
				assert.equal(5, shown[1].score)
				local line = table.concat(printed, "\n")
				assert.truthy(line:find("Rank up: you are now |cff9dff3aReaper|r (rank 2 of 3).", 1, true))
				-- the same mob again scores nothing: no second rank-up
				local before = #printed
				catchHogger("cast2", 2, "B")
				assert.equal(1, #shown)
				assert.equal(before, #printed)
			end)

			it("shows the new rank's emblem on the soul popup of a claim that ranks you up", function()
				local ns = bootRanks({ popup = true, sound = false, announce = false })
				local emblems = {}
				ns.Toast.show = function(_, _, _, _, emblem) emblems[#emblems + 1] = emblem end
				ns.Toast.showRank = function() end
				catchHogger("cast1", 1, "A")
				assert.equal(ns.Ranks.emblem(2), emblems[1])
				assert.not_equal(ns.Ranks.emblem(1), emblems[1])
			end)

			it("tells the guild from the announcing rank on, when announcements are on", function()
				local sentChat = {}
				_G.IsInGuild = function() return true end
				_G.C_ChatInfo = {
					SendChatMessage = function(text, channel) sentChat[#sentChat + 1] = channel .. ":" .. text end,
				}
				bootRanks({ popup = false, sound = false, announce = true })
				catchHogger("cast1", 1, "A")
				assert.same({ "GUILD:SoulDex: reached the rank of Reaper!" }, sentChat)
			end)

			it("stays out of guild chat when announcements are off", function()
				local sentChat = {}
				_G.IsInGuild = function() return true end
				_G.C_ChatInfo = { SendChatMessage = function(text) sentChat[#sentChat + 1] = text end }
				bootRanks({ popup = false, sound = false, announce = false })
				catchHogger("cast1", 1, "A")
				assert.same({}, sentChat)
			end)
		end)

		describe("announcing during a chat lockdown", function()
			local sentChat, locked

			-- Boots in a guild with announcements on and one announcing milestone per catch.
			local function bootGuild(db)
				sentChat, locked = {}, false
				_G.IsInGuild = function() return true end
				_G.C_ChatInfo = {
					SendChatMessage = function(text, channel) sentChat[#sentChat + 1] = channel .. ":" .. text end,
					InChatMessagingLockdown = function() return locked end,
				}
				db = db or {}
				db.settings = db.settings or { popup = false, sound = false, announce = true }
				local ns = boot(db)
				ns.Milestones.check = function() return { { text = "Completed Molten Core", announce = true } } end
				return ns, db
			end

			local function catch(cast, guid)
				world.target = HOGGER
				world.clock = world.clock + 10
				drain(cast, "Hogger")
				putShard(tonumber(guid:byte()) - 64, guid)
				fire("BAG_UPDATE_DELAYED")
				flush()
			end

			it("holds the message while chat is locked and sends it once the lockdown ends", function()
				local _, db = bootGuild()
				locked = true
				catch("cast1", "A")
				assert.same({}, sentChat)
				assert.same({ { text = "SoulDex: Completed Molten Core!", at = world.epoch } }, db.announceQueue)
				fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 2) -- still active: nothing yet
				assert.same({}, sentChat)
				locked = false
				fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
				assert.same({ "GUILD:SoulDex: Completed Molten Core!" }, sentChat)
				assert.same({}, db.announceQueue)
				fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0) -- sent once only
				assert.equal(1, #sentChat)
			end)

			it("holds the message during a boss encounter and sends it after combat", function()
				local _, db = bootGuild()
				_G.IsEncounterInProgress = function() return true end
				catch("cast1", "A")
				assert.same({}, sentChat)
				_G.IsEncounterInProgress = function() return false end
				fire("PLAYER_REGEN_ENABLED")
				flush()
				assert.same({ "GUILD:SoulDex: Completed Molten Core!" }, sentChat)
				assert.same({}, db.announceQueue)
			end)

			it("treats a secret lockdown answer as locked", function()
				local _, db = bootGuild()
				_G.issecretvalue = function(v) return v == SECRET end
				locked = SECRET
				catch("cast1", "A")
				assert.same({}, sentChat)
				assert.equal(1, #db.announceQueue)
			end)

			it("sends a message held over a reload once the world loads", function()
				bootGuild({ announceQueue = { { text = "SoulDex: Completed Molten Core!", at = world.epoch - 60 } } })
				assert.same({ "GUILD:SoulDex: Completed Molten Core!" }, sentChat)
			end)

			it("throws away junk and messages held for over an hour", function()
				local _, db = bootGuild({
					announceQueue = { "junk", { text = "SoulDex: Old!", at = world.epoch - 3601 }, { at = 1 } },
				})
				assert.same({}, sentChat)
				assert.same({}, db.announceQueue)
			end)

			it("drops held messages when announcements are turned off", function()
				local _, db = bootGuild()
				locked = true
				catch("cast1", "A")
				db.settings.announce = false
				locked = false
				fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
				assert.same({}, sentChat)
				assert.same({}, db.announceQueue)
			end)

			it("keeps held messages while not in a guild (the roster may still be loading)", function()
				local _, db = bootGuild()
				locked = true
				catch("cast1", "A")
				_G.IsInGuild = function() return false end
				locked = false
				fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
				assert.same({}, sentChat)
				assert.equal(1, #db.announceQueue)
				_G.IsInGuild = function() return true end
				fire("PLAYER_REGEN_ENABLED")
				flush()
				assert.same({ "GUILD:SoulDex: Completed Molten Core!" }, sentChat)
			end)

			it("keeps at most ten held messages", function()
				local _, db = bootGuild({ announceQueue = {} })
				locked = true
				for i = 1, 12 do
					db.announceQueue[#db.announceQueue + 1] = { text = "old " .. i, at = world.epoch }
				end
				catch("cast1", "A")
				assert.equal(10, #db.announceQueue)
				assert.equal("old 4", db.announceQueue[1].text)
				assert.equal("SoulDex: Completed Molten Core!", db.announceQueue[10].text)
			end)
		end)

		it("shows the popup and plays the sound a frame after the catch, not during it", function()
			world.target = HOGGER
			local ns = boot({ settings = { popup = true, sound = true, announce = false } })
			local log = {}
			ns.Toast.show = function() log[#log + 1] = "show" end
			_G.PlaySound = function() log[#log + 1] = "sound" end
			table.insert(ns.onCatch, function() log[#log + 1] = "hook" end)
			drain("cast1", "Hogger")
			putShard(1, "A")
			fire("BAG_UPDATE_DELAYED")
			table.remove(timers, 1)() -- the bag scan records the catch
			assert.same({ "hook" }, log)
			flush()
			assert.same({ "hook", "show", "sound" }, log)
		end)

		describe("sound preload at login", function()
			local played, stopped
			before_each(function()
				played, stopped = {}, {}
				_G.PlaySound = function(kit)
					played[#played + 1] = kit
					return true, 77
				end
				_G.StopSound = function(handle) stopped[#stopped + 1] = handle end
			end)

			it("starts the catch sound and stops it at once when the world loads", function()
				local ns = load()
				ns.Print = function() end
				ns.OnLoaded({ settings = { popup = false, sound = true, announce = false } })
				assert.same({}, played) -- not at ADDON_LOADED
				fire("PLAYER_ENTERING_WORLD")
				assert.same({ 8959 }, played)
				assert.same({ 77 }, stopped)
				fire("PLAYER_ENTERING_WORLD") -- a later loading screen: once per session
				assert.equal(1, #played)
			end)

			it("loads it when the sound is switched on later, and not while it is off", function()
				local ns, db = boot({ settings = { popup = false, sound = false, announce = false } })
				ns.Capture.prepareFor(db, "sound")
				assert.same({}, played)
				db.settings.sound = true
				ns.Capture.prepareFor(db, "sound")
				assert.same({ 8959 }, played)
				assert.same({ 77 }, stopped)
			end)

			it("does nothing when the sound is off", function()
				boot({ settings = { popup = false, sound = false, announce = false } })
				assert.same({}, played)
			end)

			it("does nothing when the client can't stop a sound, so none is heard", function()
				_G.StopSound = nil
				boot({ settings = { popup = false, sound = true, announce = false } })
				assert.same({}, played)
			end)

			it("stops nothing when the game won't play it or the handle is secret", function()
				_G.PlaySound = function() return false, nil end
				boot({ settings = { popup = false, sound = true, announce = false } })
				_G.issecretvalue = function(v) return v == SECRET end
				_G.PlaySound = function() return true, SECRET end
				boot({ settings = { popup = false, sound = true, announce = false } })
				assert.same({}, stopped)
			end)
		end)

		describe("popup frame", function()
			local function countPrepares(ns)
				local n = 0
				ns.Toast.prepare = function() n = n + 1 end
				return function() return n end
			end

			it("is built when the world first loads if the popup is on", function()
				local ns = load()
				ns.Print = function() end
				local prepared = countPrepares(ns)
				ns.OnLoaded({ settings = { popup = true, sound = false, announce = false } })
				assert.equal(0, prepared())
				fire("PLAYER_ENTERING_WORLD")
				assert.equal(1, prepared())
			end)

			it("is not built while the popup is off, and is built when it is switched on", function()
				local ns = load()
				ns.Print = function() end
				local prepared = countPrepares(ns)
				local db = { settings = { popup = false, sound = false, announce = false } }
				ns.OnLoaded(db)
				fire("PLAYER_ENTERING_WORLD")
				assert.equal(0, prepared())
				db.settings.popup = true
				ns.Capture.prepareFor(db, "popup")
				assert.equal(1, prepared())
			end)
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

	describe("soul-name whispers", function()
		local ME_GUID = "Player-1-ME"
		local MONK = { name = SECRET, guid = SECRET, level = SECRET, classification = "elite", creatureType = SECRET }
		local sends, filters, tellsSet

		before_each(function()
			sends, filters, tellsSet = {}, {}, {}
			world.locked = false
			world.afk, world.dnd = false, false
			world.mouseover, world.focus = nil, nil
			world.isUnit = nil -- set to force UnitIsUnit's answer
			world.sendFails = nil
			world.sendMovesTell = nil
			world.lines = {}
			_G.UnitExists = function(unit)
				if unit == "target" then
					return world.target ~= nil
				end
				if unit == "mouseover" or unit == "focus" then
					return world[unit] ~= nil
				end
				return unit == "player"
			end
			_G.UnitIsUnit = function(a, b)
				if world.isUnit ~= nil then
					return world.isUnit
				end
				local function of(u)
					return u == "target" and world.target or world[u]
				end
				return of(a) == of(b)
			end
			_G.UnitIsAFK = function() return world.afk end
			_G.UnitIsDND = function() return world.dnd end
			_G.GetUnitName = function(unit, full)
				if unit == "player" and full then
					return "Forgot Shards"
				end
			end
			local targetGuid = _G.UnitGUID
			_G.UnitGUID = function(unit)
				if unit == "player" then
					return ME_GUID
				end
				return targetGuid(unit)
			end
			_G.C_ChatInfo = {
				InChatMessagingLockdown = function() return world.locked end,
				SendChatMessage = function(text, chatType, _, target)
					if world.sendFails then
						error("refused")
					end
					sends[#sends + 1] = { text = text, chatType = chatType, target = target }
					if world.sendMovesTell then
						world.lastTell = { target, "WHISPER" }
					end
				end,
				GetChatLineText = function(id) return world.lines[id] and world.lines[id].text end,
				GetChatLineSenderGUID = function(id) return world.lines[id] and world.lines[id].guid end,
			}
			_G.ChatFrameUtil = {
				AddMessageEventFilter = function(event, fn) filters[#filters + 1] = { event = event, fn = fn } end,
			}
			world.lastTell = { "Friend", "WHISPER" }
			_G.ChatEdit_GetLastTellTarget = function() return world.lastTell[1], world.lastTell[2] end
			_G.ChatEdit_SetLastTellTarget = function(target, chatType)
				tellsSet[#tellsSet + 1] = { target = target, chatType = chatType }
				world.lastTell = { target, chatType }
			end
		end)

		-- CHAT_MSG_WHISPER as the client fires it: text, sender, ..., line id (11), sender GUID (12).
		local function whisper(text, guid, lineID)
			fire("CHAT_MSG_WHISPER", text, "Forgot Shards", "", "", "", "", 0, 0, "", 0, lineID or 1, guid)
		end

		local function tokenOf(send)
			return send.text:match("^SDX1:([^:]+):%%t$")
		end

		local function pendOf(ns, send)
			return ns.Capture.whispers.queue:get(tokenOf(send))
		end

		it("whispers the player once for a hidden name, with the details read", function()
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			assert.equal(1, #sends)
			assert.truthy(sends[1].text:match("^SDX1:[^:]+:%%t$"))
			assert.equal("WHISPER", sends[1].chatType)
			assert.equal("Forgot Shards", sends[1].target)
			local pend = pendOf(ns, sends[1])
			assert.equal("waiting", pend.state)
			assert.equal("elite", pend.details.classification)
			assert.is_nil(pend.details.level)
			assert.is_nil(pend.details.creatureType)
			assert.is_false(pend.details.isPlayer)
		end)

		it("asks on a hidden Shadowburn target too", function()
			world.target = MONK
			boot()
			fire("UNIT_SPELLCAST_SENT", "player", SECRET, "sb1", 17877)
			fire("UNIT_SPELLCAST_SUCCEEDED", "player", "sb1", 17877)
			assert.equal(1, #sends)
		end)

		-- One test per case: each boots its own addon, and globals are restored after each.
		for _, case in ipairs({
			{ "the mouse is over another unit", function() world.mouseover = { name = "Other" } end },
			{ "the focus is another unit", function() world.focus = { name = "Other" } end },
			{ "UnitIsUnit is secret", function()
				world.mouseover = MONK
				world.isUnit = SECRET
			end },
			{ "the player is AFK", function() world.afk = true end },
			{ "DND is secret", function() world.dnd = SECRET end },
			{ "chat is locked down", function() world.locked = true end },
			{ "the player's own name is secret", function() _G.GetUnitName = function() return SECRET end end },
		}) do
			it("does not ask when " .. case[1], function()
				world.target = MONK
				local ns = boot()
				case[2]()
				drain("cast1", SECRET)
				assert.equal(0, #sends)
				assert.equal(0, ns.Capture.whispers.queue:count())
			end)
		end

		it("still asks during a boss encounter while chat is not locked down", function()
			world.target = MONK
			_G.IsEncounterInProgress = function() return true end
			boot()
			drain("cast1", SECRET)
			assert.equal(1, #sends)
		end)

		it("treats a secret lockdown answer as locked", function()
			world.target = MONK
			world.locked = SECRET
			boot()
			drain("cast1", SECRET)
			assert.equal(0, #sends)
		end)

		-- SENT reading used (same cast id) / cross-checked by name (another cast id).
		for _, channelCast in ipairs({ "cast1", "other" }) do
			it("does not ask when the cast named a readable unit but the target's name is hidden ("
				.. channelCast .. ")", function()
				world.target = MONK
				local ns = boot()
				fire("UNIT_SPELLCAST_SENT", "player", "Party Member", "cast1", 1120)
				fire("UNIT_SPELLCAST_CHANNEL_START", "player", channelCast, 1120)
				assert.equal(0, #sends)
				assert.equal(0, ns.Capture.whispers.queue:count())
			end)
		end

		it("still asks when both the SENT name and the target's name are hidden, cast ids differing", function()
			world.target = MONK
			boot()
			fire("UNIT_SPELLCAST_SENT", "player", SECRET, "cast1", 1120)
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", "other", 1120)
			assert.equal(1, #sends)
		end)

		it("does not ask for a readable name", function()
			world.target = HOGGER
			boot()
			drain("cast1", "Hogger")
			assert.equal(0, #sends)
		end)

		it("a refused send leaves no pending whisper and an Unknown soul", function()
			world.target = MONK
			world.sendFails = true
			local ns, db = boot()
			drain("cast1", SECRET)
			assert.equal(0, ns.Capture.whispers.queue:count())
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			assert.is_true(db.shardSouls.NEW.soul.unknown)
		end)

		it("leaves the last tell target alone when sending did not move it", function()
			world.target = MONK
			boot()
			drain("cast1", SECRET)
			assert.equal(1, #sends)
			assert.same({}, tellsSet)
		end)

		it("puts the last tell target back when sending moved it", function()
			world.target = MONK
			world.sendMovesTell = true
			boot()
			drain("cast1", SECRET)
			assert.equal(1, #sends)
			assert.same({ { target = "Friend", chatType = "WHISPER" } }, tellsSet)
		end)

		it("does not ask when the target changed between the cast being sent and its channel start", function()
			world.target = MONK
			boot()
			fire("UNIT_SPELLCAST_SENT", "player", SECRET, "cast1", 1120)
			fire("PLAYER_TARGET_CHANGED")
			fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast1", 1120)
			assert.equal(0, #sends)
		end)

		it("asks when the target changed before the cast was sent (a targeting macro)", function()
			world.target = MONK
			boot()
			fire("PLAYER_TARGET_CHANGED")
			drain("cast1", SECRET)
			assert.equal(1, #sends)
		end)

		it("a recast on the same hidden target names its shard (the first capture is replaced)", function()
			world.target = MONK
			local ns, db = boot()
			drain("cast1", SECRET)
			fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
			world.clock = world.clock + 1
			drain("cast2", SECRET)
			assert.equal(2, #sends)
			putShard(1, "NEW")
			fire("BAG_UPDATE_DELAYED")
			flush()
			-- held for the second whisper's name, not dropped as ambiguous
			assert.is_not_nil(ns.Shards.pendingOf(db.shardSouls, "NEW"))
		end)

		it("never whispers when no chat filter could be installed", function()
			_G.ChatFrameUtil = nil
			_G.ChatFrame_AddMessageEventFilter = nil
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			assert.equal(0, #sends)
			assert.equal(0, ns.Capture.whispers.queue:count())
		end)

		it("never whispers when installing the chat filter fails", function()
			_G.ChatFrameUtil = { AddMessageEventFilter = function() error("no") end }
			world.target = MONK
			boot()
			drain("cast1", SECRET)
			assert.equal(0, #sends)
		end)

		it("puts /r back again when the reply arrives (the reply set it to the player)", function()
			world.target = MONK
			boot()
			drain("cast1", SECRET)
			world.lastTell = { "Forgot Shards", "WHISPER" } -- as the client does for an incoming whisper
			whisper("SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk", ME_GUID)
			assert.same({ "Friend", "WHISPER" }, world.lastTell)
		end)

		it("puts /r back after a failed reply, with the player's name given with a realm", function()
			world.target = MONK
			boot()
			drain("cast1", SECRET)
			world.lastTell = { "Forgot Shards-Home", "WHISPER" }
			whisper("SDX1:" .. tokenOf(sends[1]) .. ":%t", ME_GUID)
			assert.same({ "Friend", "WHISPER" }, world.lastTell)
		end)

		it("leaves /r alone when someone else whispered meanwhile", function()
			world.target = MONK
			boot()
			drain("cast1", SECRET)
			world.lastTell = { "Bestie", "WHISPER" }
			whisper("SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk", ME_GUID)
			assert.same({ "Bestie", "WHISPER" }, world.lastTell)
		end)

		it("the player's own reply names the soul; another sender's changes nothing", function()
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			local pend = pendOf(ns, sends[1])
			local token = tokenOf(sends[1])
			whisper("SDX1:" .. token .. ":Scarlet Monk", "Player-1-OTHER")
			assert.equal("waiting", pend.state)
			assert.is_nil(pend.name)
			whisper("SDX1:" .. token .. ":Scarlet Monk", ME_GUID)
			assert.equal("named", pend.state)
			assert.equal("Scarlet Monk", pend.name)
		end)

		it("a reply with no usable name fails the whisper", function()
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			local pend = pendOf(ns, sends[1])
			whisper("SDX1:" .. tokenOf(sends[1]) .. ":%t", ME_GUID)
			assert.equal("failed", pend.state)
			assert.equal(0, ns.Capture.whispers.queue:count())
		end)

		it("a reply with an unknown token, or other text, changes nothing", function()
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			local pend = pendOf(ns, sends[1])
			whisper("SDX1:zz:Scarlet Monk", ME_GUID)
			whisper("hello", ME_GUID)
			assert.equal("waiting", pend.state)
			assert.equal(1, ns.Capture.whispers.queue:count())
		end)

		it("a secret reply is re-read from chat history once combat ends", function()
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			local pend = pendOf(ns, sends[1])
			whisper(SECRET, SECRET, 7)
			assert.equal("waiting", pend.state)
			world.lines[7] = { text = "SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk", guid = ME_GUID }
			fire("PLAYER_REGEN_ENABLED")
			flush()
			assert.equal("named", pend.state)
			assert.equal("Scarlet Monk", pend.name)
			assert.equal(0, #ns.Capture.whispers.lines)
		end)

		it("keeps a line that is still secret, and re-reads it on a zone change", function()
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			local pend = pendOf(ns, sends[1])
			local reply = "SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk"
			whisper(reply, SECRET, 9)
			world.lines[9] = { text = reply, guid = SECRET }
			fire("ENCOUNTER_END")
			assert.equal("waiting", pend.state)
			world.lines[9].guid = ME_GUID
			fire("ZONE_CHANGED_NEW_AREA")
			assert.equal("named", pend.state)
		end)

		it("drops a kept line id after the ceiling", function()
			world.target = MONK
			local ns = boot()
			drain("cast1", SECRET)
			local pend = pendOf(ns, sends[1])
			whisper(SECRET, SECRET, 7)
			world.lines[7] = { text = SECRET, guid = SECRET }
			world.clock = world.clock + ns.Whisper.CEILING
			fire("PLAYER_REGEN_ENABLED") -- still secret, and too old: dropped
			assert.equal(0, #ns.Capture.whispers.lines)
			world.lines[7] = { text = "SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk", guid = ME_GUID }
			fire("ADDON_RESTRICTION_STATE_CHANGED")
			assert.equal("waiting", pend.state)
		end)

		it("keeps no line id while nothing is pending, and at most 32", function()
			world.target = HOGGER
			local ns = boot()
			whisper(SECRET, SECRET, 7)
			assert.equal(0, #ns.Capture.whispers.lines)
			world.target = MONK
			drain("cast1", SECRET)
			for id = 1, 40 do
				whisper(SECRET, SECRET, id)
			end
			assert.equal(32, #ns.Capture.whispers.lines)
			assert.equal(9, ns.Capture.whispers.lines[1].id) -- the oldest went first
		end)

		describe("holding the shard", function()
			-- Runs the live tickers once a second for the given seconds.
			local function wait(seconds)
				for _ = 1, seconds do
					world.clock = world.clock + 1
					for _, ticker in ipairs(tickers) do
						if not ticker.cancelled then
							ticker.fn()
						end
					end
				end
			end

			local function liveTickers()
				local n = 0
				for _, ticker in ipairs(tickers) do
					if not ticker.cancelled then
						n = n + 1
					end
				end
				return n
			end

			local function newShard(slot, guid)
				putShard(slot, guid)
				fire("BAG_UPDATE_DELAYED")
				flush()
			end

			local function bootCaught()
				local ns, db = boot()
				local caught = {}
				table.insert(ns.onCatch, function(result, entry) caught[#caught + 1] = { result, entry } end)
				return ns, db, caught
			end

			it("holds the shard until the reply, then records the named mob in the saved zone", function()
				world.target = MONK
				local ns, db, caught = bootCaught()
				drain("cast1", SECRET)
				local token = tokenOf(sends[1])
				newShard(1, "NEW")
				assert.same({}, db.mobs)
				assert.is_nil(db.unknown["Elwynn Forest"])
				assert.equal(0, #caught)
				assert.equal(0, #timers)
				assert.is_false(db.shardSouls.NEW.soul)
				assert.equal(token, ns.Shards.pendingOf(db.shardSouls, "NEW").token)
				assert.equal("Elwynn Forest", ns.Shards.pendingOf(db.shardSouls, "NEW").ctx.zone)

				world.zone = "Somewhere Else"
				whisper("SDX1:" .. token .. ":Scarlet Monk", ME_GUID)
				local mob = db.mobs["Scarlet Monk"]
				assert.is_not_nil(mob)
				assert.equal("elite", mob.classification)
				assert.equal(1, mob.places["Elwynn Forest"].count)
				assert.is_nil(db.places["Somewhere Else"])
				local soul = db.shardSouls.NEW.soul
				assert.equal("Scarlet Monk", soul.name)
				assert.equal("Elwynn Forest", soul.zone)
				assert.is_nil(ns.Shards.pendingOf(db.shardSouls, "NEW"))
				assert.equal(1, #caught)
				assert.equal("mob", caught[1][2].kind)
				assert.is_true(caught[1][1].isNew)
				assert.equal(1, #timers) -- the popup, a frame later
			end)

			describe("boss names after the fight (experimental, settings.lateAsk)", function()
				local function bootLate(on)
					world.target = MONK
					world.locked = true -- a boss encounter: chat is locked
					local ns, db = boot({ settings = { popup = false, sound = false, announce = false, lateAsk = on } })
					local caught = {}
					table.insert(ns.onCatch, function(result, entry) caught[#caught + 1] = { result, entry } end)
					return ns, db, caught
				end

				it("off: a soul claimed while chat is locked is an Unknown soul at once, as before", function()
					local ns, db = bootLate(false)
					drain("cast1", SECRET)
					assert.equal(0, ns.Capture.whispers.queue:count())
					newShard(1, "NEW")
					assert.is_true(db.shardSouls.NEW.soul.unknown)
				end)

				it("on: holds the shard, asks when the fight ends, and names the soul", function()
					local ns, db, caught = bootLate(true)
					drain("cast1", SECRET)
					assert.equal(0, #sends) -- never sent into a chat lock
					assert.equal(1, ns.Capture.whispers.queue:count())
					newShard(1, "NEW")
					assert.is_not_nil(ns.Shards.pendingOf(db.shardSouls, "NEW"))
					assert.equal(0, #caught)
					fire("ENCOUNTER_END")
					assert.equal(0, #sends) -- still locked
					world.locked = false
					fire("ENCOUNTER_END")
					assert.equal(1, #sends)
					fire("ENCOUNTER_END")
					assert.equal(1, #sends) -- once
					whisper("SDX1:" .. tokenOf(sends[1]) .. ":Arcanist Doan", ME_GUID)
					assert.is_not_nil(db.mobs["Arcanist Doan"])
					assert.equal("Arcanist Doan", db.shardSouls.NEW.soul.name)
					assert.equal(1, #caught)
				end)

				it("on: a target change before the fight ends makes it an Unknown soul, and nothing is sent", function()
					local _, db = bootLate(true)
					drain("cast1", SECRET)
					newShard(1, "NEW")
					fire("PLAYER_TARGET_CHANGED")
					world.locked = false
					fire("ENCOUNTER_END")
					assert.equal(0, #sends)
					assert.is_true(db.shardSouls.NEW.soul.unknown)
					assert.equal(1, db.unknown["Elwynn Forest"].count)
				end)

				it("on: recasting through the fight ends in one whisper", function()
					local ns = bootLate(true)
					drain("cast1", SECRET)
					fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
					world.clock = world.clock + 20
					drain("cast2", SECRET)
					world.clock = world.clock + 20
					drain("cast3", SECRET)
					assert.equal(1, ns.Capture.whispers.queue:count())
					world.locked = false
					fire("ENCOUNTER_END")
					assert.equal(1, #sends)
				end)

				it("on: a refused send at the end makes it an Unknown soul", function()
					local _, db = bootLate(true)
					drain("cast1", SECRET)
					newShard(1, "NEW")
					world.locked, world.sendFails = false, true
					fire("ENCOUNTER_END")
					assert.is_true(db.shardSouls.NEW.soul.unknown)
				end)
			end)

			it("a raid soul named by whisper fills its slot in the raid's list (held shard)", function()
				world.target = { name = SECRET, guid = SECRET, level = 62, classification = "elite" }
				world.instanceType, world.instanceID, world.zone = "raid", 409, "Molten Core"
				local _, db, caught = bootCaught()
				drain("cast1", SECRET)
				local token = tokenOf(sends[1])
				newShard(1, "NEW")
				whisper("SDX1:" .. token .. ":Core Hound", ME_GUID)
				assert.is_not_nil(db.raids[11671])
				assert.equal(409, db.raids[11671].instanceID)
				assert.is_nil(db.mobs["Core Hound"])
				assert.equal("raid", caught[1][2].kind)
			end)

			it("a raid soul named before its shard arrives fills its slot too; a boss scores as one", function()
				world.target = { name = SECRET, guid = SECRET, level = -1, classification = "worldboss" }
				world.instanceType, world.instanceID, world.zone = "raid", 409, "Molten Core"
				local _, db, caught = bootCaught()
				drain("cast1", SECRET)
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":Ragnaros", ME_GUID)
				newShard(1, "NEW")
				assert.is_not_nil(db.raids[11502])
				assert.equal(25, caught[1][1].points)
			end)

			it("a whisper-named creature the raid doesn't list stays a plain mob under Raids", function()
				world.target = { name = SECRET, guid = SECRET, level = 60, classification = "elite" }
				world.instanceType, world.instanceID, world.zone = "raid", 409, "Molten Core"
				local _, db = bootCaught()
				drain("cast1", SECRET)
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":Some New Thing", ME_GUID)
				newShard(1, "NEW")
				assert.is_not_nil(db.mobs["Some New Thing"])
				assert.same({}, db.raids)
			end)

			it("a reply before the shard records the named soul when the shard arrives", function()
				world.target = MONK
				local ns, db, caught = bootCaught()
				drain("cast1", SECRET)
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk", ME_GUID)
				assert.equal(0, ns.Capture.whispers.queue:count()) -- named: out of the queue
				assert.same({}, db.mobs)
				newShard(1, "NEW")
				assert.equal(1, db.mobs["Scarlet Monk"].places["Elwynn Forest"].count)
				assert.equal("Scarlet Monk", db.shardSouls.NEW.soul.name)
				assert.is_nil(ns.Shards.pendingOf(db.shardSouls, "NEW"))
				assert.equal(1, #caught)
			end)

			it("a named whisper can't time out later", function()
				world.target = MONK
				local ns = boot()
				drain("cast1", SECRET)
				local pend = pendOf(ns, sends[1])
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk", ME_GUID)
				wait(ns.Whisper.CEILING + 1)
				assert.equal("named", pend.state)
				assert.equal("Scarlet Monk", pend.name)
			end)

			it("no reply in 60 s out of combat: one Unknown soul in the shard's zone", function()
				world.target = MONK
				local ns, db, caught = bootCaught()
				drain("cast1", SECRET)
				newShard(1, "NEW")
				assert.equal(1, liveTickers())
				wait(59)
				assert.is_nil(db.unknown["Elwynn Forest"])
				wait(2)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
				local soul = db.shardSouls.NEW.soul
				assert.is_true(soul.unknown)
				assert.equal(ns.Capture.UNKNOWN_SOUL, soul.name)
				assert.equal("Elwynn Forest", soul.zone)
				assert.is_nil(ns.Shards.pendingOf(db.shardSouls, "NEW"))
				assert.equal(1, #caught)
				assert.equal("unknown", caught[1][2].kind)
				wait(120)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
				assert.equal(0, liveTickers()) -- nothing left to wait for
			end)

			it("puts /r back when the wait ends, if a reply set it to the player", function()
				world.target = MONK
				boot()
				drain("cast1", SECRET)
				whisper(SECRET, SECRET, 7) -- a reply that never becomes readable
				world.lastTell = { "Forgot Shards", "WHISPER" }
				wait(61)
				assert.same({ "Friend", "WHISPER" }, world.lastTell)
			end)

			it("a later catch that tops up a whisper-named soul's points can rank you up", function()
				world.target = { name = SECRET, guid = SECRET, level = SECRET, classification = SECRET }
				local ns, db, printed = boot()
				ns.Ranks.LIST = { { min = 0, name = "Initiate" }, { min = 5, name = "Reaper" }, { min = 500, name = "Top" } }
				drain("cast1", SECRET)
				newShard(1, "A")
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":Hogger", ME_GUID)
				assert.equal(ns.Points.forMob(nil), ns.dex:score())
				fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
				world.clock = world.clock + 30
				world.target = HOGGER
				drain("cast2", "Hogger")
				newShard(2, "B")
				assert.equal(2, ns.Points.count(db.mobs.Hogger))
				assert.equal(5, ns.dex:score())
				local line = table.concat(printed, "\n")
				assert.truthy(line:find("Rank up: you are now |cff9dff3aReaper|r", 1, true))
			end)

			describe("when the game blocks a whisper", function()
				local LINE = "Soul names in dungeons are off for this session: the game blocked SoulDex's whisper."

				for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
					it(event .. " for SoulDex ends the waiting whisper as Unknown and stops later sends", function()
						world.target = MONK
						local ns, db, printed = boot()
						local caught = {}
						table.insert(ns.onCatch, function(result) caught[#caught + 1] = result end)
						drain("cast1", SECRET)
						newShard(1, "NEW")
						fire(event, "SoulDex", "UNKNOWN()")
						assert.equal(0, ns.Capture.whispers.queue:count())
						assert.equal(1, db.unknown["Elwynn Forest"].count)
						assert.is_true(db.shardSouls.NEW.soul.unknown)
						assert.equal(1, #caught)
						local lines = 0
						for _, line in ipairs(printed) do
							if line == LINE then
								lines = lines + 1
							end
						end
						assert.equal(1, lines)
						fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
						world.clock = world.clock + 30
						drain("cast2", SECRET)
						assert.equal(1, #sends) -- no second whisper this session
						fire(event, "SoulDex", "UNKNOWN()")
						wait(61)
						assert.equal(1, db.unknown["Elwynn Forest"].count)
						local again = 0
						for _, line in ipairs(printed) do
							if line == LINE then
								again = again + 1
							end
						end
						assert.equal(1, again) -- the line is printed once
					end)
				end

				it("a block naming another addon, or an unreadable one, changes nothing", function()
					world.target = MONK
					local ns, db, printed = boot()
					drain("cast1", SECRET)
					newShard(1, "NEW")
					fire("ADDON_ACTION_BLOCKED", "OtherAddon", "SendChatMessage()")
					fire("ADDON_ACTION_BLOCKED", SECRET, "UNKNOWN()")
					assert.equal(1, ns.Capture.whispers.queue:count())
					assert.is_nil(db.unknown["Elwynn Forest"])
					assert.same({}, printed)
					fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
					world.clock = world.clock + 5
					drain("cast2", SECRET)
					assert.equal(2, #sends)
				end)
			end)

			it("a reply with no usable name after the shard is held gives one Unknown soul", function()
				world.target = MONK
				local _, db = boot()
				drain("cast1", SECRET)
				newShard(1, "NEW")
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":%t", ME_GUID)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
				assert.is_true(db.shardSouls.NEW.soul.unknown)
				wait(120)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
			end)

			it("the clock stops in combat; a reply re-read when combat ends still names the soul", function()
				world.target = MONK
				local inCombat = true
				_G.InCombatLockdown = function() return inCombat end
				local _, db = boot()
				drain("cast1", SECRET)
				newShard(1, "NEW")
				whisper(SECRET, SECRET, 7)
				wait(90)
				assert.is_nil(db.unknown["Elwynn Forest"])
				assert.is_false(db.shardSouls.NEW.soul)
				world.lines[7] = { text = "SDX1:" .. tokenOf(sends[1]) .. ":Scarlet Monk", guid = ME_GUID }
				inCombat = false
				fire("PLAYER_REGEN_ENABLED")
				flush()
				assert.equal("Scarlet Monk", db.shardSouls.NEW.soul.name)
				assert.is_not_nil(db.mobs["Scarlet Monk"])
				assert.is_nil(db.unknown["Elwynn Forest"])
			end)

			for _, case in ipairs({
				{ "a secret combat answer", function() _G.InCombatLockdown = function() return SECRET end end },
				{ "a chat lockdown", function() world.locked = true end },
			}) do
				it(case[1] .. " stops the clock too", function()
					world.target = MONK
					local _, db = boot()
					drain("cast1", SECRET)
					newShard(1, "NEW")
					case[2]()
					wait(90)
					assert.is_nil(db.unknown["Elwynn Forest"])
					assert.is_false(db.shardSouls.NEW.soul)
				end)
			end

			it("a reply that arrives after its whisper timed out changes nothing", function()
				world.target = MONK
				local ns, db, caught = bootCaught()
				drain("cast1", SECRET)
				local token = tokenOf(sends[1])
				newShard(1, "NEW")
				wait(61)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
				assert.equal(1, #caught)
				whisper("SDX1:" .. token .. ":Scarlet Monk", ME_GUID)
				world.lines[7] = { text = "SDX1:" .. token .. ":Scarlet Monk", guid = ME_GUID }
				whisper(SECRET, SECRET, 7) -- the same reply arriving secret, re-read later
				fire("PLAYER_REGEN_ENABLED")
				flush()
				assert.equal(1, db.unknown["Elwynn Forest"].count)
				assert.same({}, db.mobs)
				assert.is_true(db.shardSouls.NEW.soul.unknown)
				assert.equal(ns.Capture.UNKNOWN_SOUL, db.shardSouls.NEW.soul.name)
				assert.equal(1, #caught)
				assert.equal(0, ns.Capture.whispers.queue:count())
			end)

			it("two held shards each get their own name", function()
				world.target = MONK
				local _, db = boot()
				drain("cast1", SECRET)
				local tokenA = tokenOf(sends[1])
				fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast1", 1120)
				newShard(1, "gA")
				world.clock = world.clock + 5
				drain("cast2", SECRET)
				local tokenB = tokenOf(sends[2])
				fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast2", 1120)
				newShard(2, "gB")
				assert.are_not.equal(tokenA, tokenB)
				whisper("SDX1:" .. tokenB .. ":Scarlet Abbot", ME_GUID)
				whisper("SDX1:" .. tokenA .. ":Scarlet Monk", ME_GUID)
				assert.equal("Scarlet Monk", db.shardSouls.gA.soul.name)
				assert.equal("Scarlet Abbot", db.shardSouls.gB.soul.name)
			end)

			it("two shards from one held capture are both named by its reply, counted once", function()
				world.target = MONK
				local ns, db, caught = bootCaught()
				drain("cast1", SECRET)
				local token = tokenOf(sends[1])
				putShard(1, "gA")
				putShard(2, "gB")
				fire("BAG_UPDATE_DELAYED")
				flush()
				assert.equal(token, ns.Shards.pendingOf(db.shardSouls, "gA").token)
				assert.equal(token, ns.Shards.pendingOf(db.shardSouls, "gB").token)
				world.clock = world.clock + 1
				newShard(3, "gC") -- a third, a moment later: held too
				assert.equal(token, ns.Shards.pendingOf(db.shardSouls, "gC").token)
				whisper("SDX1:" .. token .. ":Scarlet Monk", ME_GUID)
				for _, g in ipairs({ "gA", "gB", "gC" }) do
					assert.equal("Scarlet Monk", db.shardSouls[g].soul.name)
					assert.is_nil(ns.Shards.pendingOf(db.shardSouls, g))
				end
				assert.equal(1, db.mobs["Scarlet Monk"].places["Elwynn Forest"].count)
				assert.equal(1, #caught)
			end)

			it("a shard after its capture's reply came takes the named soul at once", function()
				world.target = MONK
				local ns, db, caught = bootCaught()
				drain("cast1", SECRET)
				local token = tokenOf(sends[1])
				newShard(1, "gA")
				whisper("SDX1:" .. token .. ":Scarlet Monk", ME_GUID)
				world.clock = world.clock + 1
				newShard(2, "gB")
				assert.equal("Scarlet Monk", db.shardSouls.gB.soul.name)
				assert.is_nil(ns.Shards.pendingOf(db.shardSouls, "gB"))
				assert.equal(1, db.mobs["Scarlet Monk"].places["Elwynn Forest"].count)
				assert.equal(1, #caught)
			end)

			it("two held shards whose whisper fails are one Unknown soul", function()
				world.target = MONK
				local _, db = boot()
				drain("cast1", SECRET)
				putShard(1, "gA")
				putShard(2, "gB")
				fire("BAG_UPDATE_DELAYED")
				flush()
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":%t", ME_GUID)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
				assert.is_true(db.shardSouls.gA.soul.unknown)
				assert.is_true(db.shardSouls.gB.soul.unknown)
			end)

			it("a player named by whisper is stored under Name-Realm", function()
				world.target = { name = SECRET, guid = SECRET, level = 20, player = true }
				local _, db = boot()
				drain("cast1", SECRET)
				newShard(1, "NEW")
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":Forgot Shards", ME_GUID)
				assert.is_not_nil(db.players["Forgot Shards-Home"])
				assert.is_nil(db.players["Forgot Shards-"])
				assert.equal("Forgot Shards", db.shardSouls.NEW.soul.name)
			end)

			-- A capture lives at most Catch.MAX_LIFE (20 s), less than the 60 s timeout, so in
			-- play a whisper that fails before its shard fails by reply; a timeout gives the
			-- same state ("failed"), checked on Capture.record directly.
			it("a whisper that fails before its shard: the shard is one Unknown soul at the scan", function()
				world.target = MONK
				local ns, db = boot()
				drain("cast1", SECRET)
				local pend = pendOf(ns, sends[1])
				whisper("SDX1:" .. tokenOf(sends[1]) .. ":%t", ME_GUID)
				assert.equal("failed", pend.state)
				assert.is_nil(db.unknown["Elwynn Forest"])
				newShard(1, "NEW")
				assert.equal(1, db.unknown["Elwynn Forest"].count)
				assert.is_true(db.shardSouls.NEW.soul.unknown)
				assert.is_nil(ns.Shards.pendingOf(db.shardSouls, "NEW"))
				wait(120)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
			end)

			it("Capture.record of a timed-out whisper records one Unknown soul and holds nothing", function()
				local ns, db = boot()
				local pend = { token = "1", state = "failed", details = {} } -- as the ticker leaves an expired pend
				local soul, after, park = ns.Capture.record(ns.dex, { info = { unknown = true, pend = pend } })
				assert.is_nil(park)
				assert.is_true(soul.unknown)
				assert.equal("unknown", after.entry.kind)
				assert.equal(1, db.unknown["Elwynn Forest"].count)
			end)

			it("a shard still held at login becomes one Unknown soul, once", function()
				local ctx = { time = 5000, zone = "Scarlet Monastery", group = "Dungeons" }
				local ns, db = boot({
					shardSouls = { HELD = { soul = false, pending = { token = "1", ctx = ctx }, seen = 5000 } },
				})
				assert.equal(1, db.unknown["Scarlet Monastery"].count)
				local soul = db.shardSouls.HELD.soul
				assert.is_true(soul.unknown)
				assert.equal("Scarlet Monastery", soul.zone)
				assert.equal(5000, soul.time)
				assert.is_nil(ns.Shards.pendingOf(db.shardSouls, "HELD"))
				ns.OnLoaded(db)
				assert.equal(1, db.unknown["Scarlet Monastery"].count)
			end)

			it("shards held together at login are one Unknown soul", function()
				local ctx = { time = 5000, zone = "Scarlet Monastery", group = "Dungeons" }
				local _, db = boot({
					shardSouls = {
						H1 = { soul = false, pending = { token = "1", ctx = ctx }, seen = 5000 },
						H2 = { soul = false, pending = { token = "1", ctx = ctx }, seen = 5000 },
						H3 = { soul = false, pending = { token = "2", ctx = ctx }, seen = 5000 },
					},
				})
				assert.equal(2, db.unknown["Scarlet Monastery"].count)
				assert.is_true(db.shardSouls.H1.soul.unknown)
				assert.is_true(db.shardSouls.H2.soul.unknown)
				assert.is_true(db.shardSouls.H3.soul.unknown)
			end)
		end)

		describe("chat filter", function()
			local function filterFor(event)
				for _, f in ipairs(filters) do
					if f.event == event then
						return f.fn
					end
				end
			end

			local function hides(event, msg, sender, guid)
				return filterFor(event)(nil, event, msg, sender, "", "", "", "", 0, 0, "", 0, 1, guid) == true
			end

			it("hides SDX1 lines to and from the player only", function()
				boot()
				for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }) do
					assert.is_true(hides(event, "SDX1:1:Scarlet Monk", "Forgot Shards", ME_GUID))
					assert.is_true(hides(event, "SDX1:1:%t", "Forgot Shards", SECRET))
					assert.is_true(hides(event, "SDX1:1:%t", "Forgot Shards-Home", nil))
					assert.is_false(hides(event, "SDX1:1:Scarlet Monk", "Someone", "Player-1-OTHER"))
					assert.is_false(hides(event, "SDX1:1:Scarlet Monk", SECRET, SECRET))
					assert.is_false(hides(event, "hello", "Forgot Shards", ME_GUID))
					assert.is_false(hides(event, SECRET, "Forgot Shards", ME_GUID))
				end
				assert.equal(2, #filters)
			end)

			it("falls back to ChatFrame_AddMessageEventFilter", function()
				_G.ChatFrameUtil = nil
				_G.ChatFrame_AddMessageEventFilter = function(event, fn)
					filters[#filters + 1] = { event = event, fn = fn }
				end
				boot()
				assert.equal(2, #filters)
				assert.is_true(hides("CHAT_MSG_WHISPER", "SDX1:1:Scarlet Monk", "Forgot Shards", ME_GUID))
			end)
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

		it("buildContext gives the instance name", function()
			local ns = load()
			_G.GetInstanceInfo = function() return "Hyjal Summit", "raid", 1, "", 20, 0, false, 3002 end
			assert.equal("Hyjal Summit", ns.Capture.buildContext().instanceName)
		end)

		it("buildContext drops a secret instance name", function()
			local ns = load()
			_G.GetInstanceInfo = function() return SECRET, "raid", 1, "", 20, 0, false, 3002 end
			assert.is_nil(ns.Capture.buildContext().instanceName)
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
		assert.equal("ffd25a", ns.Capture.colorFor({ classification = "elite" }))
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
		it("files a claim in a TBD raid under that raid, learning its id from the name", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-3001-2-555-3", info = { name = "Barrow Thing", classification = "elite" } }
			local raidCtx = { time = 100, myLevel = 60, zone = "The Barrow Deeps", group = "Raids",
				instanceName = "The Barrow Deeps" }
			local r, kind = ns.Capture.recordCatch(dex, cand, raidCtx, "raid", 3001)
			assert.equal("raid", kind)
			assert.is_true(r.isNew)
			assert.equal("Barrow Thing", dex.db.raids[555].name)
			assert.is_nil(dex.db.mobs["Barrow Thing"])
			assert.equal(3001, dex.db.instances.BD)
		end)
		it("does not learn from a party-type instance or without a name", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-3001-2-555-3", info = { name = "Barrow Thing", classification = "elite" } }
			local named = { time = 100, zone = "X", group = "Dungeons", instanceName = "The Barrow Deeps" }
			local _, kind = ns.Capture.recordCatch(dex, cand, named, "party", 3001)
			assert.equal("mob", kind)
			local unnamed = { time = 100, zone = "X", group = "Raids" }
			_, kind = ns.Capture.recordCatch(dex, cand, unnamed, "raid", 3001)
			assert.equal("mob", kind)
			assert.same({}, dex.db.instances)
		end)
		it("records everything else as a mob", function()
			local ns, dex = setup()
			local cand = { guid = "Creature-0-1-0-2-299-3", info = { name = "Young Wolf", classification = "normal" } }
			local r, kind = ns.Capture.recordCatch(dex, cand, ctx, "none")
			assert.equal("mob", kind)
			assert.equal(1, r.total)
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
			local mob = { kind = "mob", total = 3, points = 5 }
			local player = { kind = "player", total = 42, points = 10 }
			local raid = { kind = "raid", total = 7, points = 25 }
			assert.equal("Elwynn Forest \194\183 Soul #3", ns.Toast.subtitle(mob, "Elwynn Forest"))
			assert.equal("Elwynn Forest \194\183 Soul #42", ns.Toast.subtitle(player, "Elwynn Forest"))
			assert.equal("Molten Core \194\183 Soul #7", ns.Toast.subtitle(raid, "Molten Core"))
			assert.equal("Nowhere", ns.Toast.subtitle({ kind = "unknown", points = 0 }, "Nowhere"))
			assert.equal("+25", ns.Toast.pointsText(raid))
			assert.equal("+0", ns.Toast.pointsText({}))
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
		it("names the soul plainly and puts its rarity in the title", function()
			local ns = load()
			local T = ns.Toast
			assert.equal("Hogger", T.nameLine({ name = "Hogger", classification = "elite" }))
			assert.equal("SOUL CLAIMED", T.title({ name = "Wolf", classification = "normal" }))
			assert.equal("ELITE SOUL CLAIMED", T.title({ name = "Hogger", classification = "elite" }))
			assert.equal("RARE ELITE SOUL CLAIMED", T.title({ name = "X", classification = "rareelite" }))
			assert.equal("BOSS SOUL CLAIMED", T.title({ name = "Ragnaros", classification = "worldboss" }))
			assert.equal("PLAYER SOUL CLAIMED", T.title({ name = "Bob", classification = "elite", class = "ROGUE" }))
			assert.equal("MASTERY: 1 STAR", T.title({ name = "Wolf" }, 1))
			assert.equal("MASTERY: 4 STARS", T.title({ name = "Hogger", classification = "elite" }, 4))
			assert.same({ "9dff3a", "9dff3a" }, { T.accent("ffd25a", 2) })
			assert.equal("Durotar \194\183 \195\151100 claimed",
				T.subtitle({ stars = 4, count = 100, points = 3, total = 9, isNew = false }, "Durotar"))
			ns.View = { thousands = function(n) return "<" .. n .. ">" end }
			assert.equal("Rank 4 of 8 \194\183 next: Reaper at <2500>",
				T.rankSub({ index = 4, count = 8, nextName = "Reaper", nextMin = 2500 }))
			assert.equal("Rank 8 of 8 \194\183 the highest rank", T.rankSub({ index = 8, count = 8 }))
		end)
		it("colours the popup by the soul, and fel green for a mastery star", function()
			local T = load().Toast
			assert.same({ "6b4fa0", "c9a8ff" }, { T.accent(nil) })
			assert.same({ "6b4fa0", "c9a8ff" }, { T.accent("ffffff") })
			assert.same({ "ffd25a", "ffd25a" }, { T.accent("ffd25a") })
			assert.same({ "9dff3a", "9dff3a" }, { T.accent("ffd25a", 3) })
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

		it("a shard held for its soul's name shows a grey Unknown soul, name pending", function()
			local ns = load()
			withSouls(ns)
			ns.db.shardSouls.H = {
				soul = false, seen = 1, pending = { token = "1", ctx = { zone = "Scarlet Monastery", time = 1 } },
			}
			local tip = tipStub()
			ns.Tooltip.onItem(tip, { id = 6265, guid = "H" })
			assert.same({ "|cff9d9d9dUnknown soul|r", "Scarlet Monastery \194\183 name pending" }, tip.lines)
			tip = tipStub()
			ns.Tooltip.onItem(tip, { id = 6265, guid = "B" }) -- an ordinary soulless shard: still nothing
			assert.equal(0, #tip.lines)
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

		describe("unit tooltips", function()
			local function unitTip(extra)
				local tip = tipStub(extra)
				tip.GetUnit = function() return "whoever", "target" end
				return tip
			end

			local function withDex(ns)
				ns.db = {}
				ns.dex = ns.Dex.new(ns.db)
				return ns.dex
			end

			local CTX = { time = 1, zone = "Elwynn Forest" }

			it("says nothing for a soul never caught", function()
				local ns = load()
				withDex(ns)
				world.target = HOGGER
				local tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({}, tip.lines)
			end)

			it("marks a caught creature, with a count past the first", function()
				local ns = load()
				local dex = withDex(ns)
				dex:recordMob({ name = "Hogger" }, CTX)
				world.target = HOGGER
				local tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({ "Soul collected" }, tip.lines)
				dex:recordMob({ name = "Hogger" }, CTX)
				tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({ "Soul collected \195\1512" }, tip.lines)
			end)

			it("adds nothing when the switch is off", function()
				local ns = load()
				local dex = withDex(ns)
				dex:recordMob({ name = "Hogger" }, CTX)
				ns.db.settings = { unitTooltip = false }
				world.target = HOGGER
				local tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({}, tip.lines)
				ns.db.settings.unitTooltip = true
				tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({ "Soul collected" }, tip.lines)
			end)

			it("finds a raid creature by its NPC ID", function()
				local ns = load()
				local dex = withDex(ns)
				dex:recordRaid({ name = "Lucifron" }, CTX, 409, 12118)
				world.target = { name = "Lucifron", guid = "Creature-0-1-409-2-12118-3" }
				local tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({ "Soul collected" }, tip.lines)
			end)

			it("marks a caught player by joined name and home realm", function()
				local ns = load()
				local dex = withDex(ns)
				dex:recordPlayer({ name = "Forgot Shards", realm = "Home" }, CTX)
				world.target = { name = "Forgot", realm = "Shards", guid = "Player-1-2", player = true }
				local tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({ "Soul collected" }, tip.lines)
				-- a creature of the same name is not that player
				world.target = { name = "Forgot Shards", guid = "Creature-0-1-0-2-5-3" }
				tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({}, tip.lines)
			end)

			it("says nothing when the name, the unit or the player flag is secret or unknown", function()
				local ns = load()
				local dex = withDex(ns)
				dex:recordMob({ name = "Hogger" }, CTX)
				world.target = { name = SECRET, guid = HOGGER.guid }
				local tip = unitTip()
				ns.Tooltip.onUnit(tip)
				world.target = { name = "Unknown", guid = HOGGER.guid }
				ns.Tooltip.onUnit(tip)
				world.target = HOGGER
				tip.GetUnit = function() return "Hogger", SECRET end
				ns.Tooltip.onUnit(tip)
				tip.GetUnit = function() return "Hogger", nil end
				ns.Tooltip.onUnit(tip)
				tip.GetUnit = nil
				ns.Tooltip.onUnit(tip)
				tip = unitTip()
				_G.UnitIsPlayer = function() return SECRET end
				ns.Tooltip.onUnit(tip)
				assert.same({}, tip.lines)
			end)

			it("leaves forbidden or protected tooltips alone, and waits for the dex", function()
				local ns = load()
				world.target = HOGGER
				local tip = unitTip()
				ns.Tooltip.onUnit(tip) -- no dex yet
				withDex(ns):recordMob({ name = "Hogger" }, CTX)
				tip = unitTip({ IsForbidden = function() return true end })
				ns.Tooltip.onUnit(tip)
				ns.Tooltip.onUnit(nil)
				assert.same({}, tip.lines)
				_G.C_RestrictedActions = { CheckAllowProtectedFunctions = function() return false end }
				tip = unitTip()
				ns.Tooltip.onUnit(tip)
				assert.same({}, tip.lines)
			end)

			it("hooks OnTooltipSetUnit without TooltipDataProcessor", function()
				_G.TooltipDataProcessor = nil
				local script, handler
				_G.GameTooltip = { HookScript = function(_, name, fn) script, handler = name, fn end }
				local ns = load()
				assert.equal("OnTooltipSetUnit", script)
				assert.equal(ns.Tooltip.onUnit, handler)
			end)
		end)
	end)
end)
