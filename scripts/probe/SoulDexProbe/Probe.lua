-- SoulDex probe (throwaway, not shipped). Records what this client exposes to addons
-- about the player's spellcasts, the target and the bags, into SoulDexProbeLog
-- (written to SavedVariables on /reload or logout). Every read is protected.
local PREFIX = "|cff9482c9SoulDexProbe|r "
local SHARD = 6265
local MAX_LINES = 1500

SoulDexProbeLog = SoulDexProbeLog or {}

local function isSecret(v)
	if issecretvalue then
		local ok, res = pcall(issecretvalue, v)
		if ok and res then return true end
	end
	if canaccessvalue then
		local ok, res = pcall(canaccessvalue, v)
		if ok and res == false then return true end
	end
	return false
end

local function s(v)
	if isSecret(v) then return "<secret>" end
	local ok, res = pcall(tostring, v)
	return ok and res or "<tostring error>"
end

local function log(msg, echo)
	local line = date("%H:%M:%S") .. string.format(".%03d ", math.floor((GetTime() % 1) * 1000)) .. msg
	local L = SoulDexProbeLog
	L[#L + 1] = line
	while #L > MAX_LINES do table.remove(L, 1) end
	if echo then print(PREFIX .. msg) end
end

local function try(label, fn, ...)
	local res = { pcall(fn, ...) }
	if not res[1] then return label .. "=<error " .. s(res[2]) .. ">" end
	local parts = {}
	for i = 2, math.max(#res, 2) do parts[#parts + 1] = s(res[i]) end
	return label .. "=" .. table.concat(parts, ",")
end

local function spellName(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, id)
		if ok and type(info) == "table" then return s(info.name) end
	end
	if GetSpellInfo then
		local ok, name = pcall(GetSpellInfo, id)
		if ok then return s(name) end
	end
	return "?"
end

local function unitLine(unit)
	return table.concat({
		"unit=" .. unit,
		try("exists", UnitExists, unit),
		try("guid", UnitGUID, unit),
		try("name", UnitName, unit),
		try("dead", UnitIsDead, unit),
		try("level", UnitLevel, unit),
		try("class", UnitClassification, unit),
		try("type", UnitCreatureType, unit),
		try("family", UnitCreatureFamily, unit),
		try("player", UnitIsPlayer, unit),
		try("canAttack", UnitCanAttack, "player", unit),
		-- Identity leads (design spec, "Naming souls in dungeons and raids"):
		try("idSecret", C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret, unit),
		try("creatureID", UnitCreatureID, unit),
		try("nameUnmod", UnitNameUnmodified, unit),
	}, " ")
end

-- Which addon restrictions are on now: Combat, Encounter, ChallengeMode, PvPMatch, Map, Chat.
local RESTRICTIONS = { [0] = "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map", "Chat" }
local function restrictionLine()
	local parts = {}
	for id = 0, 5 do
		parts[#parts + 1] = try(RESTRICTIONS[id], C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState, id)
	end
	parts[#parts + 1] = try("chatLock", C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
	parts[#parts + 1] = try("encounter", IsEncounterInProgress)
	return "restrictions: " .. table.concat(parts, " ")
end

-- Other places the target's name might be readable: its tooltip and its nameplate.
local function tooltipLine(unit)
	local parts = {}
	local ok, data = pcall(function() return C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit) end)
	if not ok then
		parts[#parts + 1] = "tooltipInfo=<error " .. s(data) .. ">"
	elseif type(data) ~= "table" or isSecret(data) then
		parts[#parts + 1] = "tooltipInfo=" .. s(data)
	else
		local line = type(data.lines) == "table" and data.lines[1]
		parts[#parts + 1] = "tooltipInfo.line1=" .. s(type(line) == "table" and line.leftText or line)
		parts[#parts + 1] = "tooltipInfo.guid=" .. s(data.guid)
	end
	parts[#parts + 1] = try("gameTooltipLine1", function()
		GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
		GameTooltip:SetUnit(unit)
		local text = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
		GameTooltip:Hide()
		return text
	end)
	parts[#parts + 1] = try("nameplateText", function()
		local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
		local frame = plate and plate.UnitFrame
		return frame and frame.name and frame.name:GetText()
	end)
	return "names(" .. unit .. "): " .. table.concat(parts, " ")
end

-- Asks the game for the target's name the way SoulDex does (a whisper to yourself with
-- %t), tagged so the reply can be told apart in the log. The line shows in chat: this is
-- a probe. Never sent while chat is locked (that raises a red error).
local function askTarget(tag)
	local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
	if isSecret(locked) or locked then
		log("ask(" .. tag .. "): chat locked, not sent | " .. unitLine("target"), true)
		return
	end
	local me = GetUnitName and GetUnitName("player", true)
	local fn = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	local ok, err = pcall(fn, "SDXP:" .. tag .. ":%t", "WHISPER", nil, me)
	log("ask(" .. tag .. "): sent=" .. s(ok) .. " " .. s(err) .. " | " .. unitLine("target"), true)
end

local function shardSlots()
	local out, n = {}, 0
	local numSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
	local itemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID
	if not numSlots or not itemID then return nil, "no container API" end
	for bag = 0, 4 do
		local okN, count = pcall(numSlots, bag)
		for slot = 1, (okN and tonumber(count) or 0) do
			local ok, id = pcall(itemID, bag, slot)
			if ok and id == SHARD then
				n = n + 1
				out[#out + 1] = bag .. ":" .. slot
			end
		end
	end
	return out, n
end

local lastShards
local function bagCheck(reason)
	local slots, n = shardSlots()
	if not slots then
		log("bags(" .. reason .. "): " .. s(n), true)
		return
	end
	if lastShards ~= n then
		log(string.format("bags(%s): shards %s -> %d [%s] | %s", reason, s(lastShards), n,
			table.concat(slots, " "), unitLine("target")), lastShards ~= nil)
		lastShards = n
	end
end

local function apiReport()
	local names = {
		"C_Container", "GetContainerNumSlots", "GetSpellInfo", "C_Spell", "issecretvalue", "canaccessvalue",
		"CombatLogGetCurrentEventInfo", "GetPlayerInfoByGUID", "C_Map", "GetInstanceInfo", "UnitChannelInfo",
		"UnitCastingInfo", "C_UnitAuras", "UnitAura", "UnitDebuff", "C_TooltipInfo", "TooltipDataProcessor",
		"C_Timer", "GetRealZoneText", "C_ChatInfo",
	}
	local parts = {}
	for _, n in ipairs(names) do parts[#parts + 1] = n .. "=" .. type(_G[n]) end
	log("api: " .. table.concat(parts, " "), true)
	log("spells: 1120=" .. spellName(1120) .. " 17877=" .. spellName(17877)
		.. " shardItem=" .. try("GetItemInfo", GetItemInfo, SHARD), true)
	log("build: " .. try("GetBuildInfo", GetBuildInfo), false)
end

local SPELL_EVENTS = {
	"UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
}
local OTHER_EVENTS = {
	"PLAYER_TARGET_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
	"PLAYER_REGEN_DISABLED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "CHAT_MSG_LOOT",
	"ITEM_PUSH", "UNIT_DIED", "PLAYER_DEAD", "UI_ERROR_MESSAGE", "CHAT_MSG_COMBAT_XP_GAIN",
	"CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_XP_UPDATE",
	-- Leads for naming souls in dungeons and raids: is any of these readable there?
	"ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "PARTY_KILL", "ADDON_RESTRICTION_STATE_CHANGED",
	"CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_RAID_BOSS_EMOTE",
	"CHAT_MSG_WHISPER", "LOOT_OPENED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
}

local frame = CreateFrame("Frame")
for _, ev in ipairs(SPELL_EVENTS) do
	local ok, err = pcall(frame.RegisterUnitEvent, frame, ev, "player")
	if not ok then log("register " .. ev .. " failed: " .. s(err), true) end
end
for _, ev in ipairs(OTHER_EVENTS) do
	local ok, err = pcall(frame.RegisterEvent, frame, ev)
	if not ok then log("register " .. ev .. " failed: " .. s(err), true) end
end

local function argsLine(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = "[" .. i .. "]=" .. s((select(i, ...))) end
	return table.concat(parts, " ")
end

frame:SetScript("OnEvent", function(_, event, ...)
	local ok, err = pcall(function(...)
		if event == "BAG_UPDATE_DELAYED" then
			bagCheck("BAG_UPDATE_DELAYED")
		elseif event == "PLAYER_ENTERING_WORLD" then
			apiReport()
			C_Timer.After(1, function() bagCheck("login") end)
		elseif event:find("^UNIT_SPELLCAST") then
			local spellID = select(event == "UNIT_SPELLCAST_SENT" and 4 or 3, ...)
			local nm = isSecret(spellID) and "<secret>" or spellName(spellID)
			log(event .. " " .. argsLine(...) .. " spell=" .. nm .. " " .. try("channel", UnitChannelInfo, "player")
				.. " | " .. unitLine("target"))
		elseif event == "PLAYER_TARGET_CHANGED" then
			log(event .. " | " .. unitLine("target"))
		elseif event == "CHAT_MSG_WHISPER" then
			-- Only the probe's own replies: never log anyone's real whispers.
			local text = ...
			if isSecret(text) then
				log("CHAT_MSG_WHISPER <secret text>")
			elseif type(text) == "string" and text:find("^SDXP:") then
				log("reply: " .. text, true)
			end
		elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" or event == "BOSS_KILL" then
			log(event .. " " .. argsLine(...) .. " | " .. unitLine("target") .. " | " .. unitLine("boss1")
				.. " | " .. restrictionLine(), true)
			if event ~= "ENCOUNTER_START" then
				-- The boss is dead and probably still your target. Can its name be asked
				-- for once the chat lock lifts? Tried now, then 1 s and 3 s later.
				askTarget(event .. "+0")
				C_Timer.After(1, function() askTarget(event .. "+1") end)
				C_Timer.After(3, function() askTarget(event .. "+3") end)
			end
		elseif event == "LOOT_OPENED" then
			log(event .. " " .. argsLine(...) .. " " .. try("lootSource1", GetLootSourceInfo, 1)
				.. " | " .. unitLine("target"))
		else
			log(event .. " " .. argsLine(...) .. " | " .. unitLine("target"),
				event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN")
		end
	end, ...)
	if not ok then log("handler error in " .. event .. ": " .. s(err), true) end
end)

SLASH_SOULDEXPROBE1 = "/sdprobe"
SlashCmdList["SOULDEXPROBE"] = function(msg)
	if msg == "clear" then
		wipe(SoulDexProbeLog)
		print(PREFIX .. "log cleared")
	elseif msg == "target" then
		-- Everything known about the target right now (alive or dead), and one ask.
		log(unitLine("target"), true)
		log(tooltipLine("target"), true)
		log(restrictionLine(), true)
		askTarget("manual")
	else
		apiReport()
		bagCheck("manual")
		print(PREFIX .. #SoulDexProbeLog .. " lines logged. /reload to save them to disk.")
	end
end

log("---- probe loaded ----", true)
