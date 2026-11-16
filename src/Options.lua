-- The options panel (/souldex options or the gear on the window): four switches and,
-- under SIZE, the size of the window and of the popups. Everything is saved the moment
-- it is clicked. Game code.
local _, ns = ...

local Options = {}
ns.Options = Options

Options.ITEMS = {
	{ key = "popup", label = "New-soul popup" },
	{ key = "sound", label = "New-soul sound" },
	{ key = "announce", label = "Guild announcements" },
	{ key = "chatter", label = "Claim chatter in chat" },
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
		-- The popups take the new size at once, and a sample shows it.
		set = function(scale, preview)
			if not (ns.db and ns.db.settings) then
				return
			end
			ns.db.settings.popupScale = scale
			if ns.Toast then
				ns.Toast.rescale()
				if preview then
					Options.testPopup()
				end
			end
		end,
	},
}

local WIDTH = 200
local ROW_H = 24
local TOP = 24 -- the title strip
local SIZE_TOP = TOP + #Options.ITEMS * ROW_H + 4 -- the rule above SIZE
local SIZE_HEAD, SIZE_ROW = 20, 22
local HEIGHT = SIZE_TOP + SIZE_HEAD + #Options.SIZES * SIZE_ROW + 6
local DIM = 0.35 -- a - or + that can go no further
local panel
local checks = {}
local steppers = {}
local resetButton

local function sync()
	local settings = ns.db and ns.db.settings or {}
	for i, item in ipairs(Options.ITEMS) do
		checks[i]:SetChecked(settings[item.key] == true)
	end
	local S = ns.Settings
	local changed = false
	for i, size in ipairs(Options.SIZES) do
		local scale = size.get()
		steppers[i].value:SetText(S.percent(scale))
		steppers[i].minus:SetAlpha(scale <= S.SCALE_MIN and DIM or 1)
		steppers[i].plus:SetAlpha(scale >= S.SCALE_MAX and DIM or 1)
		changed = changed or scale ~= S.SCALE_DEFAULT
	end
	-- "Reset" is there only while a size is not 100%.
	if changed then
		resetButton:Show()
	else
		resetButton:Hide()
	end
end

-- A silent sample of the new-soul popup, so the player can see what the popup size does
-- without draining anything (also while the popup itself is switched off). Nothing is
-- recorded.
function Options.testPopup()
	local dex = ns.dex
	if not (dex and ns.Toast and ns.Ranks and ns.Rarity) then
		return
	end
	local info = { name = "Hogger", classification = "elite" }
	local result = { isNew = true, points = 5, total = dex:uniqueSouls() + 1, kind = "mob" }
	ns.Toast.show(result, info, { zone = "Elwynn Forest" }, ns.Rarity.color("elite"), ns.Ranks.of(dex:score()).emblem)
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

-- Under the switches: a rule, the SIZE heading with "Reset" on its right, and one row
-- per size.
local function buildSizes()
	local UI, C = ns.UI, ns.UIFormat.COLORS
	local rule = panel:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 6, -SIZE_TOP)
	rule:SetPoint("TOPRIGHT", -6, -SIZE_TOP)
	UI.fill(rule, "3d2d5c")
	local head = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	head:SetPoint("TOPLEFT", 12, -SIZE_TOP - 7)
	head:SetText("SIZE")
	head:SetTextHeight(8)
	UI.textColor(head, C.HEADER)

	resetButton = CreateFrame("Button", nil, panel)
	resetButton:SetSize(36, 14)
	resetButton:SetPoint("TOPRIGHT", -8, -SIZE_TOP - 4)
	resetButton.label = resetButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	resetButton.label:SetPoint("RIGHT", 0, 0)
	resetButton.label:SetText("Reset")
	UI.textColor(resetButton.label, C.MUTED)
	resetButton:SetScript("OnEnter", function(self)
		UI.textColor(self.label, C.WHITE)
	end)
	resetButton:SetScript("OnLeave", function(self)
		UI.textColor(self.label, C.MUTED)
	end)
	resetButton:SetScript("OnClick", function()
		for _, size in ipairs(Options.SIZES) do
			if size.get() ~= ns.Settings.SCALE_DEFAULT then
				size.set(ns.Settings.SCALE_DEFAULT, false)
			end
		end
		sync()
	end)

	for i, size in ipairs(Options.SIZES) do
		local y = -SIZE_TOP - SIZE_HEAD - (i - 1) * SIZE_ROW
		local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 12, y - 3)
		label:SetText(size.label)
		UI.textColor(label, C.TEXT)
		local plus = UI.button(panel, "+", 18, 16, step(size, 1))
		plus:SetPoint("TOPRIGHT", -8, y)
		local value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
		value:SetWidth(36)
		value:SetJustifyH("CENTER")
		UI.textColor(value, C.WHITE)
		local minus = UI.button(panel, "-", 18, 16, step(size, -1))
		minus:SetPoint("RIGHT", value, "LEFT", -4, 0)
		steppers[i] = { minus = minus, plus = plus, value = value }
	end
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

	for i, item in ipairs(Options.ITEMS) do
		local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		check:SetSize(22, 22)
		check:SetPoint("TOPLEFT", 6, -TOP - (i - 1) * ROW_H)
		check:SetHitRectInsets(0, -(WIDTH - 40), 0, 0) -- the label is clickable too
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
			end
		end)
		checks[i] = check
	end
	buildSizes()
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
