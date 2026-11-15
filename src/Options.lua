-- The options panel (/souldex options or the gear on the window): three switches
-- saved to db.settings the moment they are clicked. Game code.
local _, ns = ...

local Options = {}
ns.Options = Options

Options.ITEMS = {
	{ key = "popup", label = "New-catch popup" },
	{ key = "sound", label = "New-catch sound" },
	{ key = "announce", label = "Guild announcements" },
}

local WIDTH, HEIGHT = 200, 104
local panel
local checks = {}

local function sync()
	local settings = ns.db and ns.db.settings or {}
	for i, item in ipairs(Options.ITEMS) do
		checks[i]:SetChecked(settings[item.key] == true)
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
		check:SetPoint("TOPLEFT", 6, -24 - (i - 1) * 24)
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
