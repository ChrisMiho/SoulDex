-- The options: switches saved to db.settings the moment they are clicked, the window's
-- size, a sample popup and a window reset. Shown in a small panel (/souldex options or
-- the gear on the window) and as a page of the game's own Settings window. Game code.
local _, ns = ...

local Options = {}
ns.Options = Options

Options.ITEMS = {
	{ key = "popup", label = "New-soul popup" },
	{ key = "sound", label = "New-soul sound" },
	{ key = "announce", label = "Guild announcements" },
	{ key = "chatter", label = "Claim chatter in chat" },
	{ key = "greeting", label = "Login message in chat" },
	{ key = "lateAsk", label = "Boss names after the fight (test)" },
}

local WIDTH = 200
local ROW_H = 24
local TOP = 24 -- the floating panel's title strip
local HEIGHT = TOP + #Options.ITEMS * ROW_H + 2 * 26 + 8
local panel
-- Every set of controls built (the floating panel's, the game Settings page's):
-- { checks = { CheckButton... }, scale = FontString }, kept in step by sync.
local sets = {}

local function percent(scale)
	return math.floor(scale * 100 + 0.5) .. "%"
end

local function sync()
	local settings = ns.db and ns.db.settings or {}
	for _, set in ipairs(sets) do
		for i, item in ipairs(Options.ITEMS) do
			set.checks[i]:SetChecked(settings[item.key] == true)
		end
		set.scale:SetText(percent(ns.UI.scale()))
	end
end

-- A sample of the new-soul popup (and its sound, when that is on), so the player can
-- see and hear what the switches do without draining anything. Nothing is recorded.
function Options.testPopup()
	local dex = ns.dex
	if not (dex and ns.Toast and ns.Ranks and ns.Rarity) then
		return
	end
	local info = { name = "Hogger", classification = "elite" }
	local result = { isNew = true, points = 5, total = dex:uniqueSouls() + 1, kind = "mob" }
	ns.Toast.show(result, info, { zone = "Elwynn Forest" }, ns.Rarity.color("elite"), ns.Ranks.of(dex:score()).emblem)
	if ns.db and ns.db.settings.sound and ns.Capture then
		pcall(PlaySound, ns.Capture.soundFor(result))
	end
end

-- Builds the switches, the window-size row and the two buttons into parent, from
-- (left, top) down. width: how far the rows reach (the labels are clickable).
local function fill(parent, left, top, width)
	local UI, C = ns.UI, ns.UIFormat.COLORS
	local set = { checks = {} }
	for i, item in ipairs(Options.ITEMS) do
		local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
		check:SetSize(22, 22)
		check:SetPoint("TOPLEFT", left, top - (i - 1) * ROW_H)
		check:SetHitRectInsets(0, -(width - 34), 0, 0) -- the label is clickable too
		local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		label:SetText(item.label)
		UI.textColor(label, C.TEXT)
		check:SetScript("OnClick", function(self)
			if ns.db and ns.db.settings then
				ns.db.settings[item.key] = self:GetChecked() and true or false
				-- Switched on: build the popup / load the sound now, not on the next catch.
				if ns.db.settings[item.key] and ns.Capture then
					pcall(ns.Capture.prepareFor, ns.db, item.key)
				end
				sync() -- the other set of switches, when both exist
			end
		end)
		set.checks[i] = check
	end

	-- Window size: a label, then - 100% +.
	local y = top - #Options.ITEMS * ROW_H - 4
	local sizeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sizeLabel:SetPoint("TOPLEFT", left + 4, y - 4)
	sizeLabel:SetText("Window size")
	UI.textColor(sizeLabel, C.TEXT)
	local function step(by)
		return function()
			UI.setScale(UI.scale() + by)
			sync()
		end
	end
	local plus = UI.button(parent, "+", 18, 16, step(ns.Settings.SCALE_STEP))
	plus:SetPoint("TOPLEFT", left + width - 30, y)
	set.scale = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	set.scale:SetPoint("RIGHT", plus, "LEFT", -4, 0)
	set.scale:SetWidth(34)
	set.scale:SetJustifyH("CENTER")
	UI.textColor(set.scale, C.WHITE)
	local minus = UI.button(parent, "-", 18, 16, step(-ns.Settings.SCALE_STEP))
	minus:SetPoint("RIGHT", set.scale, "LEFT", -4, 0)

	y = y - 24
	local half = math.floor((width - 16) / 2)
	local test = UI.button(parent, "Test popup", half, 18, Options.testPopup)
	test:SetPoint("TOPLEFT", left + 4, y)
	local reset = UI.button(parent, "Reset window", half, 18, function()
		UI.resetWindow()
		sync()
	end)
	reset:SetPoint("LEFT", test, "RIGHT", 4, 0)

	sets[#sets + 1] = set
	return set
end

local function build()
	local UI, C = ns.UI, ns.UIFormat.COLORS
	panel = CreateFrame("Frame", "SoulDexOptionsFrame", UIParent, "BackdropTemplate")
	panel:SetSize(WIDTH, HEIGHT)
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	UI.backdrop(panel, "14101c", "6b4fa0", 0.97)
	table.insert(UISpecialFrames, "SoulDexOptionsFrame") -- Escape closes it

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 8, -6)
	title:SetText("SoulDex Options")
	UI.textColor(title, C.TITLE)
	local close = UI.textButton(panel, "\195\151", 14)
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function()
		panel:Hide()
	end)
	local rule = panel:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 6, -22)
	rule:SetPoint("TOPRIGHT", -6, -22)
	UI.fill(rule, "3d2d5c")

	fill(panel, 6, -TOP, WIDTH - 12)
	panel:SetScript("OnShow", sync)
	panel:Hide()
end

function Options.toggle()
	if not ns.db then
		return
	end
	if not panel then
		build()
	end
	if panel:IsShown() then
		panel:Hide()
	else
		panel:Show()
		sync()
	end
end

-- The same controls as a page of the game's own Settings window (Options > AddOns >
-- SoulDex), where players look for an addon's settings first. The Settings API is the
-- game's global `Settings` (ns.Settings is SoulDex's own module). Returns whether the
-- page was registered; a client without the API just keeps the floating panel.
function Options.register()
	local api = Settings
	if type(api) ~= "table" or type(api.RegisterCanvasLayoutCategory) ~= "function"
		or type(api.RegisterAddOnCategory) ~= "function" then
		return false
	end
	local page = CreateFrame("Frame", "SoulDexSettingsPanel", UIParent)
	page:Hide()
	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("SoulDex")
	local note = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	note:SetText("Their souls. Your collection. Type /souldex or /dex to open the window.")
	fill(page, 12, -56, 240)
	page:SetScript("OnShow", sync)
	local ok, category = pcall(api.RegisterCanvasLayoutCategory, page, "SoulDex")
	if not ok or category == nil then
		return false
	end
	return (pcall(api.RegisterAddOnCategory, category))
end

ns.onLoaded = ns.onLoaded or {}
table.insert(ns.onLoaded, function()
	pcall(Options.register)
end)
