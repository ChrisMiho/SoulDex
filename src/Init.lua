-- Addon entry point: wires the addon into the game (events, slash command).
local addonName, ns = ...

local UNPACKAGED_VERSION = "@project-version@"

local function GetVersion()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if not version or version == UNPACKAGED_VERSION then
		return "dev"
	end
	return version
end

-- Personal output: the player's own chat frame only, never a channel.
local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9Soul-Dex|r " .. text)
end

ns.version = GetVersion()
ns.Print = Print

SLASH_SOULDEX1 = "/souldex"
SlashCmdList.SOULDEX = function(msg)
	if ns.OnSlash then
		ns.OnSlash(msg)
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, loaded)
	if loaded ~= addonName then
		return
	end
	SoulDexDB = SoulDexDB or {}
	if ns.OnLoaded then
		ns.OnLoaded(SoulDexDB)
	end
end)
