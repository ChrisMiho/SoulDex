describe("Net", function()
	local function loadNs()
		local ns = {
			RaidData = {
				{ key = "MC", name = "Molten Core", instanceID = 409, mobs = { { id = 12118, name = "Lucifron", boss = true } } },
			},
			Print = function() end,
		}
		local files = {
			"Settings", "Raids", "Points", "Rarity", "Ranks", "Flavour", "Dex", "Milestones", "View", "UIFormat", "Version",
			"Comm", "Friends", "Shards", "Capture", "Net",
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

		it("browse status: receiving once the dex is announced, until its own deadline", function()
			assert.equal("receiving", Net.browseStage(100, 150, 400, true))
			assert.equal("receiving", Net.browseStage(100, 300, 400, true)) -- past 60 s and 90 s: no retry, no give-up
			assert.equal("receiving", Net.browseStage(100, 400, 400, true))
			assert.equal("expired", Net.browseStage(100, 401, 400, true))
			assert.equal("retrying", Net.browseStage(100, 170, 190, false))
			assert.equal("Asking Bob...", Net.browseStatus("Bob", "asking"))
			assert.equal("Asking Bob again...", Net.browseStatus("Bob", "retrying"))
			assert.equal("Receiving Bob's dex... ~3 min", Net.browseStatus("Bob", "receiving", 170))
			assert.equal("Receiving Bob's dex... ~2 min", Net.browseStatus("Bob", "receiving", 61))
			assert.equal("Receiving Bob's dex... <1 min", Net.browseStatus("Bob", "receiving", 60))
			assert.equal("Receiving Bob's dex... <1 min", Net.browseStatus("Bob", "receiving", 0))
			assert.equal("Receiving Bob's dex...", Net.browseStatus("Bob", "receiving", nil))
		end)

		it("estimates how long a dex takes from its size", function()
			assert.equal(30, Net.transferTime(0))
			assert.equal(31, Net.transferTime(1))
			assert.equal(130, Net.transferTime(30000)) -- 300 bytes a second plus 30 s
			assert.equal(600, Net.transferTime(171000))
			assert.equal(600, Net.transferTime(2000000)) -- never more than 10 minutes
			assert.equal(30, Net.transferTime(nil))
			-- the deadline only ever moves later
			assert.equal(1130, Net.extendDeadline(1090, 1000, 30000))
			assert.equal(1090, Net.extendDeadline(1090, 1000, 300))
			-- seconds left of the estimate (without the margin), never negative
			assert.equal(100, Net.receiveLeft(1000, 30000, 1000))
			assert.equal(40, Net.receiveLeft(1000, 30000, 1060))
			assert.equal(0, Net.receiveLeft(1000, 30000, 1200))
		end)

		it("sends one dex at a time, and not back to back", function()
			-- nothing sent before
			assert.is_true(Net.maySendDex(100, nil, nil, nil))
			-- a dex is still going out (to anyone): no
			local flight = { started = 90, ceiling = 60 }
			assert.is_false(Net.maySendDex(100, nil, nil, flight))
			assert.is_false(Net.maySendDex(149, nil, 90, flight))
			-- its finished-callback never came: free again after the ceiling
			assert.is_true(Net.maySendDex(150, nil, 90, flight))
			-- finished: the same person waits 30 s, anyone else 10 s
			assert.is_false(Net.maySendDex(100, 80, 80, nil))
			assert.is_true(Net.maySendDex(110, 80, 80, nil))
			assert.is_false(Net.maySendDex(100, nil, 95, nil))
			assert.is_true(Net.maySendDex(105, nil, 95, nil))
			-- the ceiling: twice the estimate
			assert.equal(60, Net.sendCeiling(0))
			assert.equal(260, Net.sendCeiling(30000))
			assert.equal(1200, Net.sendCeiling(2000000))
		end)

		it("cleans up only when it can tell who is in your guild and group", function()
			assert.is_true(Net.cleanUpSafe(false, 0, true)) -- not in a guild
			assert.is_true(Net.cleanUpSafe(false, nil, true))
			assert.is_true(Net.cleanUpSafe(true, 40, true))
			assert.is_false(Net.cleanUpSafe(true, 0, true)) -- roster not loaded
			assert.is_false(Net.cleanUpSafe(true, nil, true)) -- roster size unreadable
			assert.is_false(Net.cleanUpSafe(nil, 40, true)) -- can't tell whether you are in a guild
			assert.is_false(Net.cleanUpSafe(true, 40, false)) -- a name was unreadable
			assert.is_false(Net.cleanUpSafe(false, 0, false))
		end)

		it("words the newer-version notice, once", function()
			assert.equal("A newer SoulDex is out: v1.5.0. You have v1.4.0.", Net.versionNotice("1.5.0", "v1.4.0", false))
			assert.is_nil(Net.versionNotice("v1.5.0", "v1.4.0", true)) -- already told this session
			assert.is_nil(Net.versionNotice("v1.4.0", "v1.4.0", false))
			assert.is_nil(Net.versionNotice("v1.3.0", "v1.4.0", false))
			assert.is_nil(Net.versionNotice("v1.5.0", "dev", false))
			assert.is_nil(Net.versionNotice("v1.5.0-beta.1", "v1.4.0", false))
			assert.is_nil(Net.versionNotice("junk", "v1.4.0", false))
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

		it("takes 'it's coming' only by whisper from someone it asked", function()
			assert.is_true(Net.accepts("W", "WHISPER", false, true))
			assert.is_false(Net.accepts("W", "WHISPER", true, false))
			assert.is_false(Net.accepts("W", "GUILD", true, true))
		end)

		it("accepts versions from the guild, group and added friends only", function()
			assert.is_true(Net.accepts("V", "GUILD"))
			assert.is_true(Net.accepts("V", "PARTY"))
			assert.is_true(Net.accepts("V", "RAID"))
			assert.is_false(Net.accepts("V", "WHISPER", false, true))
			assert.is_true(Net.accepts("V", "WHISPER", true))
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
			-- an added person we have not heard from does not count: your own row stays out,
			-- but theirs is listed so they can be selected and removed
			local waiting = {
				{ name = "Cid", score = 0, heard = false },
				{ name = "Fel", score = 0, isMe = true },
				{ name = "Gus", score = 0, heard = false },
			}
			assert.is_false(Net.showSelf(waiting))
			local rows2 = Net.leaderRows(waiting, "Gus")
			assert.equal(2, #rows2)
			assert.equal("1. Cid", rows2[1].text)
			assert.equal("Cid", rows2[1].value)
			assert.equal("2. Gus", rows2[2].text)
			assert.is_true(rows2[2].selected)
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

		it("shows when a person's dex was saved", function()
			local row = { name = "Bob", score = 0, mobs = 0, players = 0, raids = 0, online = true }
			local lines = Net.personLines(row, { summary = {}, seen = 1, dex = "D\t1", dexAt = 86400 * 300 }, os.date)
			assert.equal("Dex saved", lines[#lines].text)
			assert.equal(ns.UIFormat.dateText(86400 * 300, os.date), lines[#lines].right)
			local none = Net.personLines(row, { summary = {}, seen = 1 }, os.date)
			assert.are_not.equal("Dex saved", none[#none].text)
		end)

		it("plans a browse: a saved copy at once, and a fresh one from someone online", function()
			assert.same({ copy = false, ask = true, quiet = false }, Net.browsePlan(false, true))
			assert.same({ copy = false, ask = true, quiet = false }, Net.browsePlan(false, false))
			assert.same({ copy = true, ask = true, quiet = true }, Net.browsePlan(true, true))
			assert.same({ copy = true, ask = false, quiet = true }, Net.browsePlan(true, false))
		end)
	end)

	describe("game glue", function()
		local STUBBED = {
			"LibStub", "CreateFrame", "C_Timer", "GetTime", "time", "UnitName", "Ambiguate",
			"IsInGuild", "IsInRaid", "IsInGroup", "ChatFrame_AddMessageEventFilter", "ERR_CHAT_PLAYER_NOT_FOUND_S",
			"GetNumGroupMembers", "GetNumGuildMembers", "GetGuildRosterInfo", "issecretvalue", "date",
		}
		local saved, ns, sent, registered, printed, clock, wall, timers, filter, shown
		local onEvent, finishSends, windowShown

		before_each(function()
			saved = {}
			for _, name in ipairs(STUBBED) do
				saved[name] = _G[name]
			end
			sent, registered, printed, timers, shown = {}, {}, {}, {}, {}
			clock, wall = 100, 1000000
			finishSends, windowShown, onEvent = true, true, nil
			local AceComm = {
				Embed = function(_, target)
					target.RegisterComm = function(_, prefix) registered[#registered + 1] = prefix end
					target.SendCommMessage = function(_, prefix, text, dist, target2, prio, callback, arg)
						local m = { prefix = prefix, text = text, dist = dist, target = target2, prio = prio }
						-- like AceComm: callback(arg, bytes sent so far, bytes in all)
						m.progress = function(bytes)
							if callback then
								callback(arg, bytes, #text)
							end
						end
						sent[#sent + 1] = m
						if finishSends then
							m.progress(#text)
						end
					end
				end,
			}
			_G.LibStub = function(name) return name == "AceComm-3.0" and AceComm or nil end
			_G.CreateFrame = function()
				return { RegisterEvent = function() end, SetScript = function(_, _, fn) onEvent = fn end }
			end
			_G.C_Timer = {
				After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end,
				NewTicker = function() end,
			}
			_G.GetTime = function() return clock end
			_G.time = function() return wall end
			_G.date = os.date
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
				showDex = function(dex, owner, savedAt)
					shown[#shown + 1] = { dex = dex, owner = owner, savedAt = savedAt }
					ns.UI.viewing = owner
				end,
				owner = function() return ns.UI.viewing end,
				isShown = function() return windowShown end,
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

		it("clean up removes nobody while the guild roster is not loaded", function()
			local db = start()
			_G.GetNumGroupMembers = function() return 0 end
			_G.GetNumGuildMembers = function() return 0 end
			ns.Net:OnCommReceived("SoulDex", summary(1), "GUILD", "Gil")
			ns.Net.cleanUp()
			assert.is_not_nil(db.friends.Gil)
			assert.equal(
				"Can't read your guild and group right now, so nobody was removed. Try Clean up again in a moment.",
				printed[#printed])
		end)

		it("clean up does not take a guild rank for part of a name", function()
			local db = start()
			_G.GetNumGroupMembers = function() return 0 end
			_G.GetNumGuildMembers = function() return 1 end
			_G.GetGuildRosterInfo = function() return "Gil", "Officer" end
			for _, who in ipairs({ "Gil", "Gil Officer" }) do
				ns.Net:OnCommReceived("SoulDex", summary(1), "GUILD", who)
			end
			ns.Net.cleanUp()
			assert.is_not_nil(db.friends.Gil)
			assert.is_nil(db.friends["Gil Officer"])
			assert.equal("Removed 1 person.", printed[#printed])
		end)

		it("clean up removes nobody when a roster name is a secret value", function()
			local secret = {}
			_G.issecretvalue = function(v) return rawequal(v, secret) end
			local db = start()
			_G.GetNumGroupMembers = function() return 0 end
			_G.GetNumGuildMembers = function() return 2 end
			_G.GetGuildRosterInfo = function(i) return i == 1 and "Gil" or secret end
			for _, who in ipairs({ "Gil", "Zed" }) do
				ns.Net:OnCommReceived("SoulDex", summary(1), "GUILD", who)
			end
			ns.Net.cleanUp()
			assert.is_not_nil(db.friends.Zed)
			assert.matches("nobody was removed", printed[#printed])
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

		it("once the dex is announced it waits for it: no second ask, a later deadline", function()
			start()
			ns.Net.browse("Bob")
			local asks = #sent
			clock = clock + 5
			ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeComing(60000), "WHISPER", "Bob") -- 200 s + 30 s
			clock = 160
			timers[1].fn()
			assert.equal(asks, #sent) -- no retry "R"
			assert.equal(0, #printed)
			clock = 190
			timers[2].fn() -- the 90 s give-up: not yet
			assert.equal(0, #printed)
			assert.equal(3, #timers)
			assert.equal(145, timers[3].delay) -- until 105 + 230
			-- pressing Browse dex again changes nothing while it is on its way
			ns.Net.browse("Bob")
			assert.equal(asks, #sent)
			assert.equal(3, #timers)
			-- the dex arrives after the old 90 s limit and is still wanted
			clock = 300
			local payload = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			assert.equal(1, #shown)
			timers[3].fn()
			assert.equal(0, #printed)
		end)

		it("gives up on an announced dex at its own deadline", function()
			start()
			ns.Net.browse("Bob")
			ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeComing(60000), "WHISPER", "Bob")
			ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeComing(170000), "WHISPER", "Bob") -- a second one is ignored
			clock = 190
			timers[2].fn()
			assert.equal(140, timers[3].delay) -- 100 + 230
			clock = 330
			timers[3].fn()
			assert.equal("Bob's dex didn't arrive in time.", printed[#printed])
			local payload = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			assert.equal(0, #shown)
		end)

		it("ignores 'it's coming' from someone it did not ask", function()
			start()
			ns.Net.browse("Bob")
			ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeComing(60000), "WHISPER", "Zed")
			ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeComing(60000), "GUILD", "Bob")
			clock = 160
			timers[1].fn()
			assert.equal("No answer from Bob yet, asking again...", printed[#printed])
		end)

		it("a dex arriving while the window is closed does not open it", function()
			start()
			ns.Net.browse("Bob")
			windowShown = false
			local payload = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
			ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
			assert.equal(0, #shown)
			assert.equal("Friends", ns.UI.tab)
			assert.equal("Bob's dex arrived while SoulDex was closed. It's saved: press Browse dex to see it.",
				printed[#printed])
			-- the request is over: no retry, no "no answer"
			local count, lines = #sent, #printed
			clock = 160
			timers[1].fn()
			clock = 190
			timers[2].fn()
			assert.equal(count, #sent)
			assert.equal(lines, #printed)
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

		it("says the dex is coming, with its size, before sending it", function()
			start()
			ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeRequest("R"), "WHISPER", "Bob")
			local coming, dex = sent[#sent - 1], sent[#sent]
			assert.equal("D", dex.text:sub(1, 1))
			assert.equal(ns.Comm.encodeComing(#dex.text), coming.text)
			assert.equal("WHISPER", coming.dist)
			assert.equal("Bob", coming.target)
			assert.is_nil(coming.prio) -- normal priority: ahead of the bulk dex
		end)

		it("ignores dex requests while a dex is still being sent", function()
			start()
			finishSends = false
			local request = ns.Comm.encodeRequest("R")
			local function dexes()
				local out = {}
				for _, m in ipairs(sent) do
					if m.text:sub(1, 1) == "D" then
						out[#out + 1] = m
					end
				end
				return out
			end
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob")
			assert.equal(1, #dexes())
			local first = dexes()[1]
			first.progress(1) -- partly sent
			clock = clock + 45 -- past the 30 s gap, still uploading
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob") -- Bob's 60 s retry
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Ann") -- someone else
			assert.equal(1, #dexes())
			first.progress(#first.text) -- done
			clock = clock + 1
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Ann")
			assert.equal(2, #dexes())
			assert.equal("Ann", dexes()[2].target)
			-- Ann's finished-callback never comes: blocked until the ceiling (62 s for a tiny dex), then free
			clock = clock + 61
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob")
			assert.equal(2, #dexes())
			clock = clock + 1
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob")
			assert.equal(3, #dexes())
			-- Ann's late callback must not end Bob's send
			dexes()[2].progress(#dexes()[2].text)
			clock = clock + 31
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Cid")
			assert.equal(3, #dexes())
		end)

		it("leaves 10 s between dexes to different people", function()
			start()
			local request = ns.Comm.encodeRequest("R")
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Bob")
			local count = #sent
			clock = clock + 9
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Ann")
			assert.equal(count, #sent)
			clock = clock + 1
			ns.Net:OnCommReceived("SoulDex", request, "WHISPER", "Ann")
			assert.equal(count + 2, #sent)
		end)

		describe("version notice", function()
			local function versions(dist)
				local out = {}
				for _, m in ipairs(sent) do
					if m.text:sub(1, 1) == "V" and (not dist or m.dist == dist) then
						out[#out + 1] = m
					end
				end
				return out
			end

			it("tells the guild its version once at login, not with every summary", function()
				ns.version = "v1.4.0"
				start()
				onEvent(nil, "PLAYER_ENTERING_WORLD")
				timers[1].fn()
				assert.equal(1, #versions("GUILD"))
				assert.equal("V\t1\tv1.4.0", versions()[1].text)
				clock = clock + 300
				ns.onCatch[1]()
				assert.equal(1, #versions())
			end)

			it("tells it again when a newcomer is first heard", function()
				ns.version = "v1.4.0"
				start()
				ns.Net:OnCommReceived("SoulDex", summary(1), "GUILD", "Bob")
				assert.equal(1, #versions("GUILD"))
				clock = clock + 31
				ns.Net:OnCommReceived("SoulDex", summary(1), "GUILD", "Bob") -- heard a moment ago: no newcomer
				ns.onCatch[1]()
				assert.equal(1, #versions())
				clock = clock + 31
				ns.Net:OnCommReceived("SoulDex", summary(1), "GUILD", "Cid")
				assert.equal(2, #versions("GUILD"))
			end)

			it("whispers it once to someone who asks for your summary", function()
				ns.version = "v1.4.0"
				start()
				ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeRequest("Q"), "WHISPER", "Bob")
				clock = clock + 60
				ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeRequest("Q"), "WHISPER", "Bob")
				assert.equal(1, #versions("WHISPER"))
				assert.equal("Bob", versions()[1].target)
			end)

			it("an unbuilt checkout tells nobody", function()
				ns.version = "dev"
				start()
				onEvent(nil, "PLAYER_ENTERING_WORLD")
				timers[1].fn()
				ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeRequest("Q"), "WHISPER", "Bob")
				assert.equal(0, #versions())
			end)

			it("prints one line for a newer version, once per session", function()
				ns.version = "v1.4.0"
				start()
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv1.4.0", "GUILD", "Bob")
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv1.3.9", "GUILD", "Bob")
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv9.9.9", "WHISPER", "Zed") -- a stranger's whisper
				ns.Net:OnCommReceived("SoulDex", "V\t1\tnonsense", "GUILD", "Bob")
				assert.equal(0, #printed)
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv1.5.0", "GUILD", "Bob")
				assert.equal("A newer SoulDex is out: v1.5.0. You have v1.4.0.", printed[#printed])
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv1.6.0", "RAID", "Cid")
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv1.5.0", "GUILD", "Bob")
				assert.equal(1, #printed)
			end)

			it("takes a whispered version from an added friend", function()
				ns.version = "v1.4.0"
				start()
				ns.Net.addFriend("Ann")
				local lines = #printed
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv1.5.0", "WHISPER", "Ann")
				assert.equal(lines + 1, #printed)
			end)

			it("a dev build is never told", function()
				ns.version = "dev"
				start()
				ns.Net:OnCommReceived("SoulDex", "V\t1\tv1.5.0", "GUILD", "Bob")
				assert.equal(0, #printed)
			end)
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

		describe("saved copies", function()
			local function friendDex()
				local friendDb = { mobs = {}, places = {}, players = {}, raids = {} }
				ns.Dex.new(friendDb):recordMob({ name = "Wolf" }, { time = 5, zone = "Durotar", group = "Kalimdor" })
				return ns.Comm.encodeDex(friendDb)
			end

			it("keeps the dex it asked for", function()
				local db = start()
				ns.Net.addFriend("Bob")
				ns.Net.browse("Bob")
				local payload = friendDex()
				ns.Net:OnCommReceived("SoulDex", payload, "WHISPER", "Bob")
				assert.equal(payload, db.friends.Bob.dex)
				assert.equal(wall, db.friends.Bob.dexAt)
				assert.is_nil(shown[1].savedAt) -- a fresh one: no "saved" date
			end)

			it("opens the saved copy of someone offline without asking them", function()
				local db = start()
				db.friends.Bob = { added = true, seen = wall - 3600, dex = friendDex(), dexAt = 5 }
				local count = #sent
				ns.Net.browse("Bob")
				assert.equal(count, #sent)
				assert.equal(1, #shown)
				assert.equal("Bob", shown[1].owner)
				assert.equal(5, shown[1].savedAt)
				assert.is_truthy(shown[1].dex.db.mobs.Wolf)
				assert.equal(ns.dex, ns.UI.compare)
				assert.equal("Mobs", ns.UI.tab)
				assert.equal(0, #timers)
			end)

			it("opens the saved copy of someone online and quietly asks for a fresh one", function()
				local db = start()
				db.friends.Bob = { added = true, seen = wall, dex = friendDex(), dexAt = 5 }
				ns.Net.browse("Bob")
				assert.equal(5, shown[1].savedAt)
				assert.equal(ns.Comm.encodeRequest("R"), sent[#sent].text)
				local lines = #printed
				clock = 161
				timers[1].fn() -- asks again, without a chat line
				assert.equal(ns.Comm.encodeRequest("R"), sent[#sent].text)
				assert.equal(lines, #printed)
				local fresh = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
				wall = wall + 50
				ns.Net:OnCommReceived("SoulDex", fresh, "WHISPER", "Bob")
				assert.equal(2, #shown)
				assert.is_nil(shown[2].savedAt)
				assert.equal(fresh, db.friends.Bob.dex)
				assert.equal(wall, db.friends.Bob.dexAt)
				assert.equal(lines, #printed)
			end)

			it("says nothing when the quiet ask gets no answer", function()
				local db = start()
				db.friends.Bob = { added = true, seen = wall, dex = friendDex(), dexAt = 5 }
				ns.Net.browse("Bob")
				local lines = #printed
				clock = 161
				timers[1].fn()
				clock = 191
				timers[2].fn()
				assert.equal(lines, #printed)
			end)

			it("a fresh copy doesn't pull you away from what you went to", function()
				local db = start()
				db.friends.Bob = { added = true, seen = wall, dex = friendDex(), dexAt = 5 }
				ns.Net.browse("Bob")
				ns.UI.viewing = nil -- back to your own dex
				local fresh = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
				local lines = #printed
				ns.Net:OnCommReceived("SoulDex", fresh, "WHISPER", "Bob")
				assert.equal(1, #shown)
				assert.equal(fresh, db.friends.Bob.dex)
				assert.equal(lines, #printed)
			end)

			it("a fresh copy arriving with the window closed is only saved", function()
				local db = start()
				db.friends.Bob = { added = true, seen = wall, dex = friendDex(), dexAt = 5 }
				ns.Net.browse("Bob")
				windowShown = false
				local fresh = ns.Comm.encodeDex({ mobs = {}, places = {}, players = {}, raids = {} })
				local lines = #printed
				ns.Net:OnCommReceived("SoulDex", fresh, "WHISPER", "Bob")
				assert.equal(1, #shown)
				assert.equal(fresh, db.friends.Bob.dex)
				assert.equal(lines, #printed)
			end)

			it("drops a saved copy it can't read and asks as before", function()
				local db = start()
				db.friends.Bob = { added = true, seen = wall - 3600, dex = "D\t1\nGARBAGE", dexAt = 5 }
				ns.Net.browse("Bob")
				assert.equal(0, #shown)
				assert.is_nil(db.friends.Bob.dex)
				assert.is_nil(db.friends.Bob.dexAt)
				assert.equal(ns.Comm.encodeRequest("R"), sent[#sent].text)
			end)
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

		it("keeps hiding them while a long dex is still going out to someone who logged off", function()
			start()
			finishSends = false
			ns.Net:OnCommReceived("SoulDex", ns.Comm.encodeRequest("R"), "WHISPER", "Bob")
			local dex = sent[#sent]
			local line = "No player named 'Bob' is currently playing."
			clock = clock + 120 -- two minutes in: Bob has logged off, pieces still go out
			assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", line))
			dex.progress(500) -- a piece is sent; the game answers with the line
			assert.is_true(filter(nil, "CHAT_MSG_SYSTEM", line))
			clock = clock + 90
			dex.progress(1000)
			clock = clock + 2
			assert.is_true(filter(nil, "CHAT_MSG_SYSTEM", line))
		end)

		it("leaves a system line it can't read alone", function()
			local secret = setmetatable({}, { __index = function() error("touched a secret value") end })
			_G.issecretvalue = function(v) return rawequal(v, secret) end
			start()
			ns.Net.addFriend("Ann")
			assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", secret))
			assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", nil))
			assert.is_false(filter(nil, "CHAT_MSG_SYSTEM", ""))
		end)

		it("forgets people it never added and hasn't seen for 30 days when it loads", function()
			local db = { settings = ns.Settings.normalise(nil), friends = {
				Old = { added = false, seen = wall - 31 * 86400 },
				New = { added = false, seen = wall - 86400 },
				Pal = { added = true, seen = wall - 99 * 86400 },
			} }
			ns.db = db
			ns.dex = ns.Dex.new(db)
			for _, fn in ipairs(ns.onLoaded) do
				fn(db)
			end
			assert.is_nil(db.friends.Old)
			assert.is_not_nil(db.friends.New)
			assert.is_not_nil(db.friends.Pal)
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
