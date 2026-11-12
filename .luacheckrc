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
	"scripts/probe/", -- throwaway in-game probes (not shipped)
}

-- Globals this addon creates
globals = {
	"SlashCmdList",
	"SLASH_SOULDEX1",
	"SoulDexDB",
	"SoulDexFrame",
	"SoulDexOptionsFrame",
	"StaticPopupDialogs", -- the Friends tab adds its clean-up dialog
}

-- WoW API this addon reads. Add each new API here as it is used,
-- so a typo in an API name fails lint instead of failing in game.
read_globals = {
	"Ambiguate",
	"C_AddOns",
	"C_ChatInfo",
	"C_Container",
	"C_GuildInfo",
	"C_Item",
	"C_RestrictedActions",
	"C_Spell",
	"canaccesstable",
	"C_Map",
	"C_Timer",
	"ChatFrame_AddMessageEventFilter",
	"CreateFrame",
	"DEFAULT_CHAT_FRAME",
	"Enum",
	"ERR_CHAT_PLAYER_NOT_FOUND_S",
	"GetCursorInfo",
	"GetGuildInfo",
	"GetGuildRosterInfo",
	"GetInstanceInfo",
	"GetNumGroupMembers",
	"GetNumGuildMembers",
	"GetItemIcon",
	"GetRealZoneText",
	"GetRealmName",
	"GetTime",
	"GameFontHighlightSmall",
	"GameFontNormal",
	"GameTooltip",
	"GetZoneText",
	"geterrorhandler",
	"hooksecurefunc",
	"issecretvalue",
	"ItemLocation",
	"IsInGroup",
	"IsInGuild",
	"IsInRaid",
	"LibStub",
	"LOCALIZED_CLASS_NAMES_MALE",
	"NUM_BAG_SLOTS",
	"NUM_TOTAL_EQUIPPED_BAG_SLOTS",
	"PlaySound",
	"RAID_CLASS_COLORS",
	"SOUNDKIT",
	"StaticPopup_Show",
	"SendChatMessage",
	"TooltipDataProcessor",
	"UIParent",
	"UISpecialFrames",
	"date",
	"time",
	"UnitClass",
	"UnitClassification",
	"UnitCreatureFamily",
	"UnitCreatureType",
	"UnitGUID",
	"UnitIsPlayer",
	"UnitLevel",
	"UnitName",
	"UnitRace",
	"UNKNOWN",
	"UNKNOWNOBJECT",
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
