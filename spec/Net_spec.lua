describe("Net", function()
	local function loadNs()
		local ns = {
			RaidData = {
				{ key = "MC", name = "Molten Core", instanceID = 409, mobs = { { id = 12118, name = "Lucifron", boss = true } } },
			},
			Print = function() end,
		}
		local files = {
			"Settings", "Raids", "Points", "Rarity", "Ranks", "Flavour", "Dex", "Milestones", "View", "UIFormat", "Comm",
			"Friends", "Shards", "Capture", "Net",
		}
		for _, file in ipairs(files) do
			LoadAddonFile("src/" .. file .. ".lua", ns)
		end
		return ns
	end

	describe("pure helpers", function()
		local Net, ns

		before_each(function()
			ns = loadNs()
			Net = ns.Net
		end)

		it("browse status: asking, then asking again, then no answer", function()
			assert.equal("asking", Net.browseStage(100, 100))
			assert.equal("asking", Net.browseStage(100, 159))
			assert.equal("retrying", Net.browseStage(100, 161))
			assert.equal("retrying", Net.browseStage(100, 190))
			assert.equal("expired", Net.browseStage(100, 191))
			assert.equal("expired", Net.browseStage(nil, 191))
		end)

		it("forgets throttle entries older than their window", function()
			local t = { Ann = 10, Bob = 95 }
			Net.forgetOlder(t, 100, 30)
			assert.same({ Bob = 95 }, t)
		end)

		it("broadcasts to the guild and the group", function()
			assert.same({}, Net.channels(false, false, false))
			assert.same({ "GUILD" }, Net.channels(true, false, false))
			assert.same({ "GUILD", "PARTY" }, Net.channels(true, false, true))
			assert.same({ "RAID" }, Net.channels(false, true, true))
		end)

		it("throttles", function()
			assert.equal(0, Net.wait(nil, 100, 30))
			assert.is_true(Net.allowed(nil, 100, 30))
			assert.equal(20, Net.wait(90, 100, 30))
			assert.is_false(Net.allowed(90, 100, 30))
			assert.is_true(Net.allowed(70, 100, 30))
		end)

		it("accepts summaries from the guild, group and added friends only", function()
			assert.is_true(Net.accepts("S", "GUILD"))
			assert.is_true(Net.accepts("S", "PARTY"))
			assert.is_true(Net.accepts("S", "RAID"))
			assert.is_false(Net.accepts("S", "WHISPER", false))
			assert.is_true(Net.accepts("S", "WHISPER", true))
		end)

		it("answers requests by whisper and only takes a dex it asked for", function()
			assert.is_true(Net.accepts("Q", "WHISPER"))
			assert.is_true(Net.accepts("R", "WHISPER"))
			assert.is_false(Net.accepts("R", "GUILD"))
			assert.is_false(Net.accepts("D", "WHISPER", true, false))
			assert.is_true(Net.accepts("D", "WHISPER", false, true))
			assert.is_false(Net.accepts("D", "GUILD", false, true))
			assert.is_false(Net.accepts("X", "WHISPER", true, true))
		end)

		it("recognises yourself", function()
			assert.is_true(Net.isMe("Fel", "Fel"))
			assert.is_true(Net.isMe("fel-Realm", "Fel"))
			assert.is_false(Net.isMe("Bob", "Fel"))
			assert.is_false(Net.isMe(nil, nil))
			-- WoW: Forever: UnitName("player") returns "Forgot", "Shards"; messages come from "Forgot Shards".
			assert.is_true(Net.isMe("Forgot Shards", "Forgot", "Shards"))
			assert.is_true(Net.isMe("forgot shards-91", "Forgot", "Shards"))
			assert.is_false(Net.isMe("Forgot Other", "Forgot", "Shards"))
			assert.is_false(Net.isMe("Forgot", "Forgot", "Shards")) -- a one-word player named like your first half
		end)

		it("treats unknown or long-silent people as newcomers", function()
			assert.is_true(Net.isNewcomer(nil, 1000))
			assert.is_true(Net.isNewcomer({}, 1000))
			assert.is_false(Net.isNewcomer({ seen = 900 }, 1000))
			assert.is_true(Net.isNewcomer({ seen = 100 }, 1000))
		end)

		it("asks added friends not heard from in the last minute", function()
			local store = {
				Ann = { added = true, seen = 990 },
				Bob = { added = true, seen = 900 },
				Cid = { added = true },
				Dan = { added = false, seen = 1 },
			}
			assert.same({ "Bob", "Cid" }, Net.dueQueries(store, 1000, 60))
		end)

		it("cleans typed names", function()
			assert.equal("Bob", Net.cleanName("  bob "))
			assert.equal("Bob", Net.cleanName("BOB-Realm"))
			assert.equal("Forgot Shards", Net.cleanName("forgot shards"))
			assert.equal("Forgot Shards", Net.cleanName(" Forgot   Shards "))
			assert.is_nil(Net.cleanName("one two three"))
			assert.is_nil(Net.cleanName("b0b"))
			assert.is_nil(Net.cleanName(""))
			assert.is_nil(Net.cleanName(nil))
		end)

		it("reads the name out of the player-not-found line", function()
			local fmt = "No player named '%s' is currently playing."
			assert.equal("Bob", Net.notFoundName("No player named 'Bob' is currently playing.", fmt))
			assert.is_nil(Net.notFoundName("Bob has come online.", fmt))
			assert.is_nil(Net.notFoundName("No player named 'Bob' is currently playing.", nil))
		end)

		it("formats leaderboard rows", function()
			local C = ns.UIFormat.COLORS
			local rows = Net.leaderRows({
				{ name = "Ann", score = 50, online = true, heard = true },
				{ name = "Fel", score = 40, online = true, isMe = true },
				{ name = "Bob", score = 10, online = false, heard = true },
			}, "Bob")
			assert.equal(3, #rows)
			assert.equal("1. Ann", rows[1].text)
			assert.equal("2. Fel (you)", rows[2].text)
			assert.equal(C.TITLE, rows[2].color)
			assert.is_nil(rows[2].value)
			assert.equal(C.DIM, rows[3].color)
			assert.equal("10", rows[3].right)
			assert.equal("Bob", rows[3].value)
			assert.is_true(rows[3].selected)
			assert.is_false(rows[1].selected)
		end)

		it("adds a hint when there is nobody but you", function()
			assert.is_false(Net.showSelf({ { name = "Fel", isMe = true } }))
			assert.is_true(Net.showSelf({ { name = "Ann", heard = true }, { name = "Fel", isMe = true } }))
			-- an added person we have not heard from does not count
			local waiting = { { name = "Cid", heard = false }, { name = "Fel", isMe = true } }
			assert.is_false(Net.showSelf(waiting))
			local rows2 = Net.leaderRows(waiting, nil)
			assert.equal(2, #rows2)
			assert.truthy(rows2[1].text:find("appear here"))
			local rows = Net.leaderRows({ { name = "Fel", score = 0, online = true, isMe = true } }, nil)
			assert.equal(2, #rows)
			assert.is_nil(rows[1].value)
			assert.truthy(rows[1].text:find("appear here"))
			assert.equal("/souldex add <name>", rows[2].text)
		end)

		it("formats a person's numbers", function()
			local row = { name = "Bob", score = 120, mobs = 30, players = 2, raids = 1, online = false }
			local lines = Net.personLines(row, { summary = {}, seen = 86400 * 300 }, os.date)
			assert.equal("Bob", lines[1].text)
			assert.equal("offline", lines[1].right)
			assert.equal("Rank", lines[3].text)
			assert.equal("Acolyte", lines[3].right)
			assert.equal("120 pts", lines[4].right)
			assert.equal("30", lines[5].right)
			assert.equal("2", lines[6].right)
			assert.equal("1", lines[7].right)
			assert.equal("Last seen", lines[8].text)

			local fresh = Net.personLines({ name = "Cid", score = 0, mobs = 0, players = 0, raids = 0 }, { added = true })
			assert.equal("Not heard from yet.", fresh[#fresh].text)
		end)
	end)

	describe("game glue", function()
		local STUBBED = {
			"LibStub", "CreateFrame", "C_Timer", "GetTime", "time", "UnitName", "Ambiguate",
			"IsInGuild", "IsInRaid", "IsInGroup", "ChatFrame_AddMessageEventFilter", "ERR_CHAT_PLAYER_NOT_FOUND_S",
			"GetNumGroupMembers", "GetNumGuildMembers", "GetGuildRosterInfo", "issecretvalue",
		}
		local saved, ns, sent, registered, printed, clock, wall, timers, filter, shown

		before_each(function()
			saved = {}
			for _, name in ipairs(STUBBED) do
				saved[name] = _G[name]
			end
			sent, registered, printed, timers, shown = {}, {}, {}, {}, {}
			clock, wall = 100, 1000000
			local AceComm = {
				Embed = function(_, target)
					target.RegisterComm = function(_, prefix) registered[#registered + 1] = prefix end
					target.SendCommMessage = function(_, prefix, text, dist, target2, prio)
						sent[#sent + 1] = { prefix = prefix, text = text, dist = dist, target = target2, prio = prio }
					end
				end,
			}
			_G.LibStub = function(name) return name == "AceComm-3.0" and AceComm or nil end
			_G.CreateFrame = function()
				return { RegisterEvent = function() end, SetScript = function() end }
			end
			_G.C_Timer = {
				After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end,
				NewTicker = function() end,
			}
			_G.GetTime = function() return clock end
			_G.time = function() return wall end
			_G.UnitName = function() return "Fel" end
			_G.Ambiguate = function(name) return name end
			_G.IsInGuild = function() return true end
			_G.IsInRaid = function() return false end
			_G.IsInGroup = function() return false end
			_G.ChatFrame_AddMessageEventFilter = function(_, fn) filter = fn end
			_G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."

			ns = loadNs()
			ns.Print = function(text) printed[#printed + 1] = text end
			ns.UI = {
				tab = "Friends",
				setFriendsTab = function(fn) ns.UI.builder = fn end,
				currentTab = function() return ns.UI.tab end,
				refresh = function() end,
				showDex = function(dex, owner) shown[#shown + 1] = { dex = dex, owner = owner } end,
				setCompare = function(dex) ns.UI.compare = dex end,
				selectTab = function(name) ns.UI.tab = name end,
			}
		end)

		after_each(function()
			for _, name in ipairs(STUBBED) do
				_G[name] = saved[name]
			end
		end)

		local function start()
			local db = { settings = ns.Settings.normalise(nil) }
			ns.db = db
			ns.dex = ns.Dex.new(db)
			for _, fn in ipairs(ns.onLoaded) do
				fn(db)
			end
			return db
		end

		local function summary(score)
			return ns.Comm.encodeSummary({ score = score, mobs = 3, players = 1, raids = 0 })
		end

		it("registers the prefix and the Friends tab once loaded", function()
			local db = start()
			assert.same({ "SoulDex" }, registered)
			assert.same({}, db.friends)
			assert.equal("function", type(ns.UI.builder))
			assert.equal(1, #ns.onCatch)
		end)

		it("keeps a summary from a guild member", function()
			local db = start()
			ns.Net:OnCommReceived("SoulDex", summary(42), "GUILD", "Bob-Realm")
			assert.equal(42, db.friends.Bob.summary.score)
			assert.equal(wall, db.friends.Bob.seen)
			assert.is_false(db.friends.Bob.added)
			-- a newcomer gets our summary back on the guild channel
			assert.equal("GUILD", sent[#sent].dist)
			assert.equal("S", sent[#sent].text:sub(1, 1))
		end)

		it("sends nothing to the guild when IsInGuild is a secret value", function()
			local secret = {}
			_G.issecretvalue = function(v) return rawequal(v, secret) end
			_G.IsInGuild = function() return secret end
			local db = start()
			local before = #sent
			ns.Net:OnCommReceived("SoulDex", summary(42), "GUILD", "Bob-Realm")
			assert.equal(42, db.friends.Bob.summary.score)
			for i = before + 1, #sent do
				assert.are_not.equal("GUILD", sent[i].dist)
			end
		end)

		it("ignores its own messages and strangers' whispers", function()
			local db = start()
			ns.Net:OnCommReceived("SoulDex", summary(5), "GUILD", "Fel")
			ns.Net:OnCommReceived("SoulDex", summary(5), "WHISPER", "Zed")
			ns.Net:OnCommReceived("Other", summary(5), "GUILD", "Amy")
			assert.same({}, db.friends)
		end)

		it("takes whispered summaries from added friends", function()
			local db = start()
			ns.Net.addFriend("ann")
			assert.is_true(db.friends.Ann.added)
			assert.equal("WHISPER", sent[#sent].dist)
			assert.equal("Ann", sent[#sent].target)
			assert.equal(ns.Comm.encodeRequest("Q"), sent[#sent].text)
			ns.Net:OnCommReceived("SoulDex", summary(7), "WHISPER", "Ann")
			assert.equal(7, db.friends.Ann.summary.score)
		end)

		it("won't add yourself and removes added friends", function()
			local db = start()
			ns.Net.addFriend("fel")
			assert.is_nil(db.friends.Fel)
			ns.Net.addFriend("Ann")
			ns.Net.removeFriend("ann")
			assert.is_nil(db.friends.Ann)
			ns.Net.removeFriend("Nobody")
			assert.matches("isn't on your friends list", printed[#printed])
		end)

		it("adds and removes two-part names", function()
			local db = start()
			ns.Net.addFriend("forgot shards")
			assert.is_true(db.friends["Forgot Shards"].added)
			assert.equal("Forgot Shards", sent[#sent].target)
			ns.Net.removeFriend("Forgot Shards")
			assert.is_nil(db.friends["Forgot Shards"])
		end)

		it("removes a guild member you never added", function()
			local db = start()
			ns.Net:OnCommReceived("SoulDex", summary(42), "GUILD", "Bob")
			ns.Net.removeFriend("Bob")
			assert.is_nil(db.friends.Bob)
			assert.equal("Removed Bob.", printed[#printed])
		end)

		it("clean up keeps added people and anyone in the guild or group", function()
			local db = start()
			_G.GetNumGroupMembers = function() return 2 end
			_G.UnitName = function(unit)
				if unit == "party1" then
					return "Pat", "Two"
				end
				return "Fel"
			end
			_G.GetNumGuildMembers = function() return 1 end
			_G.GetGuildRosterInfo = function() return "Gil-Realm" end
			ns.Net.addFriend("Ann")
			for _, who in ipairs({ "Pat Two", "Gil", "Zed", "Old" }) do
				ns.Net:OnCommReceived("SoulDex", summary(1), "GUILD", who)
			end
			ns.Net.cleanUp()
			assert.is_not_nil(db.friends.Ann)
			assert.is_not_nil(db.friends["Pat Two"])
			assert.is_not_nil(db.friends.Gil)
			assert.is_nil(db.friends.Zed)
			assert.is_nil(db.friends.Old)
			assert.equal("Removed 2 people.", printed[#printed])
		end)

		it("ignores a request with a bad version or shape", function()
			start()
			local before = #sent
			ns.Net:OnCommReceived("SoulDex", "R\t2", "WHISPER", "Bob")
			ns.Net:OnCommReceived("SoulDex", "Rxyz", "WHISPER", "Bob")
			ns.Net:OnCommReceived("SoulDex", "Q", "WHISPER", "Bob")
			assert.equal(before, #sent)
		end)

		it("asks again at 60 s and gives up at 90 s", function()
			start()
			ns.Net.browse("Bob")
			local asks = #sent
			assert.equal(2, #timers)
			assert.equal(60, timers[1].delay)
			assert.equal(90, timers[2].delay)
			clock = clock + 60
			timers[1].fn()
			assert.equal(asks + 1, #sent)
			assert.equal(ns.Comm.encodeRequest("R"), sent[#sent].text)
			assert.equal("No answer from Bob yet, asking again...", printed[#printed])
			clock = clock + 30
			timers[2].fn()
			assert.equal("No answer from Bob.", printed[#printed])
			-- a dex arriving after that is ignored
			local payload = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			assert.equal(0, #shown)
		end)

		it("an answer before 60 s stops the retry", function()
			start()
			ns.Net.browse("Bob")
			local payload = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			local count = #sent
			timers[1].fn()
			timers[2].fn()
			assert.equal(count, #sent)
			assert.equal(1, #shown)
		end)

		it("a late dex from someone browsed earlier is ignored", function()
			start()
			ns.Net.browse("Ann")
			ns.Net.browse("Bob")
			local payload = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Ann")
			assert.equal(0, #shown)
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			assert.equal("Bob", shown[1].owner)
		end)

		it("answers a dex request in bulk, once per 30 s", function()
			start()
			local request = ns.Comm.encodeRequest("R")
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob")
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob")
			local replies = {}
			for _, m in ipairs(sent) do
				if m.text:sub(1, 1) == "D" then
					replies[#replies + 1] = m
				end
			end
			assert.equal(1, #replies)
			assert.equal("BULK", replies[1].prio)
			assert.equal("Bob", replies[1].target)
			clock = clock + 30
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob")
			assert.equal("D", sent[#sent].text:sub(1, 1))
		end)

		it("opens a dex it asked for and compares it with yours", function()
			start()
			local friendDb = { mobs = {}, places = {}, players = {}, raids = {} }
			local friend = ns.Dex.new(friendDb)
			friend:recordMob({ name = "Wolf" }, { time = 5, zone = "Durotar", group = "Kalimdor" })
			local payload = ns.Comm.encodeDex(friendDb)

			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			assert.equal(0, #shown) -- not asked for

			ns.Net.browse("Bob")
			assert.equal(ns.Comm.encodeRequest("R"), sent[#sent].text)
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			assert.equal(1, #shown)
			assert.equal("Bob", shown[1].owner)
			assert.is_truthy(shown[1].dex.db.mobs.Wolf)
			assert.equal(ns.dex, ns.UI.compare)
			assert.equal("Mobs", ns.UI.tab)
		end)

		it("says so when a dex can't be read", function()
			start()
			ns.Net.browse("Bob")
			ns.Net:OnCommReceived("SoulDex", "D\t1\nGARBAGE", "WHISPER", "Bob")
			assert.equal(0, #shown)
			assert.equal("Couldn't read Bob's dex.", printed[#printed])
		end)

		it("throttles summary broadcasts and queues the next one", function()
			start()
			ns.onCatch[1]()
			local count = #sent
			ns.onCatch[1]()
			ns.onCatch[1]()
			assert.equal(count, #sent)
			assert.equal(1, #timers)
			timers[1].fn()
			assert.equal(count + 1, #sent)
		end)

		it("hides 'no player named' lines for names it just whispered", function()
			start()
			ns.Net.addFriend("Ann")
			assert.is_true(filter(nil, "CHAT_MSG_SYSTEM", "No player named 'Ann' is currently playing."))
			assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", "No player named 'Zed' is currently playing."))
			clock = clock + 60
			assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", "No player named 'Ann' is currently playing."))
		end)

		it("disables itself with one note without AceComm", function()
			_G.LibStub = nil
			local db = start()
			assert.equal(1, #printed)
			assert.same({}, registered)
			assert.same({}, db.friends)
			ns.Net.addFriend("Ann")
			assert.is_true(db.friends.Ann.added)
			assert.equal(0, #sent)
		end)
	end)
end)
