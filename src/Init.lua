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

local HELP = {
	"/souldex - open or close the Soul-Dex",
	"/souldex options - popup, sound and announcement switches",
	"/souldex add <name> - follow a friend's dex by name",
	"/souldex remove <name> - stop following them",
}

-- "" toggles the window; options; add/remove <name> (needs the friends module); else help.
function ns.OnSlash(msg)
	local action, name = ns.Settings.parseCommand(msg)
	if action == "toggle" then
		if ns.UI then
			ns.UI.toggle()
		end
	elseif action == "options" then
		if ns.Options then
			ns.Options.toggle()
		end
	elseif action == "add" or action == "remove" then
		local fn = ns.Net and (action == "add" and ns.Net.addFriend or ns.Net.removeFriend)
		if fn then
			fn(name)
		else
			Print("Friends aren't available yet.")
		end
	else
		Print("commands:")
		for _, line in ipairs(HELP) do
			Print(line)
		end
	end
end

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
