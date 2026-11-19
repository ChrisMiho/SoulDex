-- The options: switches saved to db.settings the moment they are clicked; the colour
-- theme; under SIZE, the size of the window and of the popups; a sample popup and a
-- window reset. Shown in a
-- small panel (/souldex options or the gear on the window) and as a page of the game's
-- own Settings window. Game code.
local _, ns = ...

local Options = {}
ns.Options = Options

Options.ITEMS = {
	{ key = "popup", label = "New-soul popup" },
	{ key = "sound", label = "New-soul sound" },
	{ key = "announce", label = "Guild announcements" },
	{ key = "greeting", label = "Login message in chat" },
	{ key = "unitTooltip", label = "\"Soul collected\" on tooltips" },
}

-- The SIZE rows: each is a label, then - 100% +. get/set read and save a scale.
Options.SIZES = {
	{
		key = "window",
		label = "Window",
		get = function()
			return ns.UI.scale()
		end,
		set = function(scale)
			ns.UI.setScale(scale)
		end,
	},
	{
		key = "popup",
		label = "Popup",
		get = function()
			local settings = ns.db and ns.db.settings
			return ns.Settings.scale(settings and settings.popupScale) or ns.Settings.SCALE_DEFAULT
		end,
		-- The popups take the new size at once, and a silent sample shows it.
		set = function(scale, preview)
			if not (ns.db and ns.db.settings) then
				return
			end
			ns.db.settings.popupScale = scale
			if ns.Toast then
				ns.Toast.rescale()
				if preview then
					Options.testPopup(true)
				end
			end
		end,
	},
}

local WIDTH = 200
local ROW_H = 24
local TOP = 24 -- the floating panel's title strip
local SIZE_GAP = 4 -- from the last switch to the rule above THEME
local THEME_H = 26 -- the Theme row, from its rule to the rule above SIZE
local THEME_VALUE_W = 70
local SIZE_HEAD, SIZE_ROW = 20, 22
local BUTTON_GAP, BUTTON_H = 4, 18
-- What fill() draws, top to bottom: the switches, the Theme row, the SIZE section, the
-- two buttons.
local FILL_H = #Options.ITEMS * ROW_H + SIZE_GAP + THEME_H
	+ SIZE_HEAD + #Options.SIZES * SIZE_ROW + BUTTON_GAP + BUTTON_H
local HEIGHT = TOP + FILL_H + 8
local DIM = 0.35 -- a - or + that can go no further
local panel
-- Every set of controls built (the floating panel's, the game Settings page's):
-- { checks = { CheckButton... }, theme = FontString, steppers = { { minus, plus, value }... },
-- reset = Button },
-- kept in step by sync.
local sets = {}

local function sync()
	local settings = ns.db and ns.db.settings or {}
	local S = ns.Settings
	for _, set in ipairs(sets) do
		for i, item in ipairs(Options.ITEMS) do
			set.checks[i]:SetChecked(settings[item.key] == true)
		end
		set.theme:SetText(ns.Themes.name(settings.theme))
		local changed = false
		for i, size in ipairs(Options.SIZES) do
			local scale = size.get()
			local stepper = set.steppers[i]
			stepper.value:SetText(S.percent(scale))
			stepper.minus:SetAlpha(scale <= S.SCALE_MIN and DIM or 1)
			stepper.plus:SetAlpha(scale >= S.SCALE_MAX and DIM or 1)
			changed = changed or scale ~= S.SCALE_DEFAULT
		end
		-- "Reset" is there only while a size is not 100%.
		if changed then
			set.reset:Show()
		else
			set.reset:Hide()
		end
	end
end

-- Brings every set of controls in step with what is saved: for a size changed from
-- outside the options (/souldex scale, /souldex reset) while they are open.
function Options.refresh()
	if #sets > 0 then
		sync()
	end
end

-- One step of a SIZE row's - or + (by: -1 or 1), kept within the limits.
local function step(size, by)
	return function()
		local S = ns.Settings
		local scale = S.scale(size.get() + by * S.SCALE_STEP)
		if scale ~= size.get() then
			size.set(scale, true)
			sync()
		end
	end
end

-- The theme `by` (1 or -1) steps from the one in use, wrapping round: applied at once,
-- with a silent sample popup in it.
function Options.stepTheme(by)
	local settings = ns.db and ns.db.settings
	if not settings then
		return
	end
	ns.UI.setTheme(ns.Themes.next(settings.theme, by))
	Options.testPopup(true)
	sync()
end

-- A sample of the new-soul popup, so the player can see (and, when the sound is on,
-- hear) what the options do without draining anything, also while the popup itself is
-- switched off. quiet: no sound (the Popup size row's preview). Nothing is recorded.
function Options.testPopup(quiet)
	local dex = ns.dex
	if not (dex and ns.Toast and ns.Ranks and ns.Rarity) then
		return
	end
	local info = { name = "Hogger", classification = "elite" }
	local result = { isNew = true, points = 5, total = dex:uniqueSouls() + 1, kind = "mob" }
	ns.Toast.show(result, info, { zone = "Elwynn Forest" }, ns.Rarity.color("elite"), ns.Ranks.of(dex:score()).emblem)
	if not quiet and ns.db and ns.db.settings.sound and ns.Capture then
		pcall(PlaySound, ns.Capture.soundFor(result))
	end
end

-- Builds the switches, the SIZE section and the two buttons into parent, from (left,
-- top) down. width: how far the rows reach (the labels are clickable).
local function fill(parent, left, top, width)
	local UI = ns.UI
	local set = { checks = {}, steppers = {} }
	for i, item in ipairs(Options.ITEMS) do
		local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
		check:SetSize(22, 22)
		check:SetPoint("TOPLEFT", left, top - (i - 1) * ROW_H)
		check:SetHitRectInsets(0, -(width - 34), 0, 0) -- the label is clickable too
		local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		label:SetText(item.label)
		UI.textColor(label, "TEXT")
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

	-- Theme: a rule, then "Theme" with  <  Soul Shard  >  on the right.
	local right = left + width - 2 -- the right edge the > / + buttons and "Reset" line up on
	local y = top - #Options.ITEMS * ROW_H - SIZE_GAP
	local themeRule = parent:CreateTexture(nil, "ARTWORK")
	themeRule:SetSize(width, 1)
	themeRule:SetPoint("TOPLEFT", left, y)
	UI.fill(themeRule, "DIVIDER")
	local themeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	themeLabel:SetPoint("TOPLEFT", left + 6, y - 8)
	themeLabel:SetText("Theme")
	UI.textColor(themeLabel, "TEXT")
	local nextTheme = UI.button(parent, ">", 18, 16, function()
		Options.stepTheme(1)
	end)
	nextTheme:SetPoint("TOPLEFT", right - 18, y - 5)
	local themeName = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	themeName:SetPoint("RIGHT", nextTheme, "LEFT", -4, 0)
	themeName:SetWidth(THEME_VALUE_W)
	themeName:SetJustifyH("CENTER")
	UI.textColor(themeName, "WHITE")
	local previousTheme = UI.button(parent, "<", 18, 16, function()
		Options.stepTheme(-1)
	end)
	previousTheme:SetPoint("RIGHT", themeName, "LEFT", -4, 0)
	set.theme = themeName

	-- SIZE: a rule, the heading with "Reset" on its right, and one row per size.
	y = y - THEME_H
	local rule = parent:CreateTexture(nil, "ARTWORK")
	rule:SetSize(width, 1)
	rule:SetPoint("TOPLEFT", left, y)
	UI.fill(rule, "DIVIDER")
	local head = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	head:SetPoint("TOPLEFT", left + 6, y - 7)
	head:SetText("SIZE")
	head:SetTextHeight(8)
	UI.textColor(head, "HEADER")

	local reset = CreateFrame("Button", nil, parent)
	reset:SetSize(36, 14)
	reset:SetPoint("TOPLEFT", right - 36, y - 4)
	reset.label = reset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	reset.label:SetPoint("RIGHT", 0, 0)
	reset.label:SetText("Reset")
	UI.textColor(reset.label, "MUTED")
	reset:SetScript("OnEnter", function(self)
		UI.textColor(self.label, "WHITE")
	end)
	reset:SetScript("OnLeave", function(self)
		UI.textColor(self.label, "MUTED")
	end)
	reset:SetScript("OnClick", function()
		for _, size in ipairs(Options.SIZES) do
			if size.get() ~= ns.Settings.SCALE_DEFAULT then
				size.set(ns.Settings.SCALE_DEFAULT, false)
			end
		end
		sync()
	end)
	set.reset = reset

	for i, size in ipairs(Options.SIZES) do
		local rowY = y - SIZE_HEAD - (i - 1) * SIZE_ROW
		local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", left + 6, rowY - 3)
		label:SetText(size.label)
		UI.textColor(label, "TEXT")
		local plus = UI.button(parent, "+", 18, 16, step(size, 1))
		plus:SetPoint("TOPLEFT", right - 18, rowY)
		local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
		value:SetWidth(36)
		value:SetJustifyH("CENTER")
		UI.textColor(value, "WHITE")
		local minus = UI.button(parent, "-", 18, 16, step(size, -1))
		minus:SetPoint("RIGHT", value, "LEFT", -4, 0)
		set.steppers[i] = { minus = minus, plus = plus, value = value }
	end

	-- Under SIZE: a sample popup (with its sound), and the window back to the middle.
	y = y - SIZE_HEAD - #Options.SIZES * SIZE_ROW - BUTTON_GAP
	local half = math.floor((width - 16) / 2)
	local test = UI.button(parent, "Test popup", half, BUTTON_H, function()
		Options.testPopup()
	end)
	test:SetPoint("TOPLEFT", left + 4, y)
	local resetWindow = UI.button(parent, "Reset window", half, BUTTON_H, function()
		UI.resetWindow()
		sync()
	end)
	resetWindow:SetPoint("LEFT", test, "RIGHT", 4, 0)

	sets[#sets + 1] = set
	return set
end

local function build()
	local UI = ns.UI
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
	UI.backdrop(panel, "BG", "BORDER", 0.97)
	table.insert(UISpecialFrames, "SoulDexOptionsFrame") -- Escape closes it

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 8, -6)
	title:SetText("SoulDex Options")
	UI.textColor(title, "TITLE")
	local close = UI.textButton(panel, "\195\151", 14)
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function()
		panel:Hide()
	end)
	local rule = panel:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 6, -22)
	rule:SetPoint("TOPRIGHT", -6, -22)
	UI.fill(rule, "DIVIDER")

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
