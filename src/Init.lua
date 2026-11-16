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
	DEFAULT_CHAT_FRAME:AddMessage("|cff9482c9SoulDex|r " .. text)
end

ns.version = GetVersion()
ns.Print = Print

local HELP = {
	"/souldex - open or close the SoulDex",
	"/souldex options - popup, sound, announcement and window switches",
	"/souldex find <text> - look a soul up by name",
	"/souldex add <name> - follow a friend's dex by name",
	"/souldex remove <name> - stop following them",
	"/souldex scale <60-160> - the window's size in percent",
	"/souldex reset - put the window back in the middle, at normal size",
	"/souldex test - show a sample popup",
	"/souldex version - the version you are running",
	"/dex works everywhere in place of /souldex",
}

-- The version as shown to the player. The packager stamps tags as they are ("v1.1.0");
-- the "v" is added only when it is missing.
local function shownVersion()
	local version = ns.version
	if version ~= "dev" and not version:find("^v") then
		version = "v" .. version
	end
	return version
end

-- Actions that only need their module: action -> function(arg).
local actions = {}

function actions.toggle()
	if ns.UI then
		ns.UI.toggle()
	end
end

function actions.options()
	if ns.Options then
		ns.Options.toggle()
	end
end

function actions.version()
	Print("version " .. shownVersion() .. ".")
end

function actions.reset()
	if ns.UI and ns.db then
		ns.UI.resetWindow()
		if ns.Options and ns.Options.refresh then
			ns.Options.refresh()
		end
		Print("The window is back in the middle of the screen, at normal size.")
	end
end

function actions.scale(arg)
	if not (ns.UI and ns.db) then
		return
	end
	if not ns.Settings.scale(arg) then
		Print("The scale is a number from 60 to 160 (percent), like /souldex scale 120.")
		return
	end
	Print("Window scale: " .. ns.Settings.percent(ns.UI.setScale(arg)) .. ".")
	if ns.Options and ns.Options.refresh then
		ns.Options.refresh()
	end
end

function actions.find(arg)
	if not (ns.dex and ns.View) then
		Print("SoulDex is still loading.")
		return
	end
	for _, line in ipairs(ns.View.findLines(ns.dex, arg, LOCALIZED_CLASS_NAMES_MALE)) do
		Print(line)
	end
end

function actions.test()
	if ns.Options and ns.Options.testPopup then
		ns.Options.testPopup()
	end
end

-- "" toggles the window; options, find, scale, reset, test, version; add/remove <name>
-- (needs the friends module); anything else prints the command list.
function ns.OnSlash(msg)
	local action, arg = ns.Settings.parseCommand(msg)
	if action == "add" or action == "remove" then
		local fn = ns.Net and (action == "add" and ns.Net.addFriend or ns.Net.removeFriend)
		if fn then
			fn(arg)
		else
			Print("Friends aren't available yet.")
		end
	elseif actions[action] then
		actions[action](arg)
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

-- Key binding (Bindings.xml): Options > Keybindings > AddOns > SoulDex.
BINDING_HEADER_SOULDEX = "SoulDex"
BINDING_NAME_SOULDEX_TOGGLE = "Open or close SoulDex"
function SoulDex_Toggle()
	actions.toggle()
end

-- The addon button by the minimap (the game's addon list; named in SoulDex.toc): a click
-- opens or closes the window, a right-click the options.
function SoulDex_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		actions.options()
	else
		actions.toggle()
	end
end

-- The two tooltip lines under the title: "Reaper · 2,612 pts" once the dex is loaded.
function ns.CompartmentLines()
	local lines = {}
	if ns.dex and ns.Ranks then
		local score = ns.dex:score()
		local pts = ns.View and ns.View.thousands(score) or tostring(score)
		lines[#lines + 1] = ns.Ranks.of(score).name .. " \194\183 " .. pts .. " pts"
	end
	lines[#lines + 1] = "Click to open. Right-click for options."
	return lines
end

function SoulDex_OnAddonCompartmentEnter(_, button)
	if not GameTooltip or type(button) ~= "table" then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetText("SoulDex " .. shownVersion())
	for _, line in ipairs(ns.CompartmentLines()) do
		GameTooltip:AddLine(line, 1, 1, 1)
	end
	GameTooltip:Show()
end

function SoulDex_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

-- The one chat line after login or /reload, so the player can see the addon is on; with
-- the dex loaded it names their rank: "v1.3.0 loaded. Reaper, 612 pts. Type ...".
function ns.Greeting()
	local version = shownVersion()
	local rank = ""
	if ns.dex and ns.Ranks then
		local score = ns.dex:score()
		rank = "|cff9dff3a" .. ns.Ranks.of(score).name .. "|r, " .. score .. " pts. "
	end
	return version .. " loaded. " .. rank .. "Type /souldex or /dex to open."
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, loaded)
	if event == "PLAYER_LOGIN" then
		-- Fires once per login and per /reload, after the chat frame is ready. The line
		-- can be switched off in the options.
		local settings = ns.db and ns.db.settings
		if not (settings and settings.greeting == false) then
			Print(ns.Greeting())
		end
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
