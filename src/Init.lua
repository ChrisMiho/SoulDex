-- Addon entry point: wires the addon into the game (events, slash command).
local addonName, ns = ...

-- An unbuilt checkout's .toc still holds the packager's version token (an "@"-wrapped
-- placeholder). Never write that token in this file: the packager replaces it in every
-- file, Lua included, which made this check match the real version and print "dev".
local function GetVersion()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if type(version) ~= "string" or version == "" or version:find("@", 1, true) then
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
	"/dex works everywhere in place of /souldex",
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
SLASH_SOULDEX2 = "/dex" -- short form; /sd was left alone, too likely to clash
SlashCmdList.SOULDEX = function(msg)
	if ns.OnSlash then
		ns.OnSlash(msg)
	end
end

-- The one chat line after login or /reload, so the player can see the addon is on.
function ns.Greeting()
	-- The packager stamps tags as they are ("v1.1.0"); add the "v" only when it is missing.
	local version = ns.version
	if version ~= "dev" and not version:find("^v") then
		version = "v" .. version
	end
	return version .. " loaded. Type /souldex or /dex to open."
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, loaded)
	if event == "PLAYER_LOGIN" then
		-- Fires once per login and per /reload, after the chat frame is ready.
		Print(ns.Greeting())
		return
	end
	if loaded ~= addonName then
		return
	end
	SoulDexDB = SoulDexDB or {}
	if ns.OnLoaded then
		ns.OnLoaded(SoulDexDB)
	end
end)
