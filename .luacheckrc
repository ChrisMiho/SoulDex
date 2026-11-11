std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
	"Libs/",
	".release/",
	".lua/",      -- Lua installed by CI (leafo/gh-actions-lua)
	".luarocks/", -- LuaRocks installed by CI (leafo/gh-actions-luarocks)
	".luacheckrc",
	".worktrees/",   -- package worktrees
	".superpowers/", -- local tooling state
}

-- Globals this addon creates
globals = {
	"SlashCmdList",
	"SLASH_SOULDEX1",
	"SoulDexDB",
	"SoulDexFrame",
	"SoulDexOptionsFrame",
}

-- WoW API this addon reads. Add each new API here as it is used,
-- so a typo in an API name fails lint instead of failing in game.
read_globals = {
	"Ambiguate",
	"C_AddOns",
	"C_Container",
	"C_Map",
	"C_Timer",
	"ChatFrame_AddMessageEventFilter",
	"CombatLogGetCurrentEventInfo",
	"CreateFrame",
	"DEFAULT_CHAT_FRAME",
	"ERR_CHAT_PLAYER_NOT_FOUND_S",
	"GetGuildInfo",
	"GetInstanceInfo",
	"GetItemIcon",
	"GetPlayerInfoByGUID",
	"GetRealZoneText",
	"GetRealmName",
	"GetSpellInfo",
	"GetTime",
	"GameFontHighlightSmall",
	"GameFontNormal",
	"GameTooltip",
	"GetZoneText",
	"geterrorhandler",
	"hooksecurefunc",
	"IsInGroup",
	"IsInGuild",
	"IsInRaid",
	"LibStub",
	"LOCALIZED_CLASS_NAMES_MALE",
	"PlaySound",
	"RAID_CLASS_COLORS",
	"SOUNDKIT",
	"SendChatMessage",
	"UIParent",
	"UISpecialFrames",
	"date",
	"time",
	"UnitClass",
	"UnitClassification",
	"UnitCreatureFamily",
	"UnitCreatureType",
	"UnitExists",
	"UnitGUID",
	"UnitIsPlayer",
	"UnitLevel",
	"UnitName",
	"UnitRace",
}

files["spec/"] = {
	std = "+busted",
	read_globals = { "LoadAddonFile" },
}

files["spec/helper.lua"] = {
	globals = { "LoadAddonFile" },
}

-- Generated data: long lines are fine
files["src/RaidData.lua"] = {
	max_line_length = false,
}

-- Dev scripts (not shipped) run under LuaJIT and use io/os
files["scripts/"] = {
	std = "+luajit",
	read_globals = { "arg" },
}
