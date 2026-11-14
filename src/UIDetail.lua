-- The detail pane: slides in from the right edge over the names list in 0.2 s,
-- with a "« Back" button and a "×" that slide it away. Game code; its lines are
-- UIFormat descriptors drawn by a UI list.
local _, ns = ...

local UIDetail = {}
ns.UIDetail = UIDetail

local SLIDE_TIME = 0.2
local PANE_BG, PANE_EDGE = "0d0a14", "8a72b8"
local LINE_H = 15

local Pane = {}
Pane.__index = Pane

-- pos: 0 = fully in, 1 = fully out. Squared so it eases out coming in and eases in going away.
function Pane:place()
	self.frame:ClearAllPoints()
	self.frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + self.width * self.pos * self.pos, 0)
end

function Pane:open(lines)
	self:setLines(lines, false)
	self.target = 0
	self:place()
	self.frame:Show()
end

function Pane:setLines(lines, keepScroll)
	self.list:set(lines, nil, keepScroll)
end

-- Slides away (or hides at once when instant).
function Pane:close(instant)
	self.target = 1
	if instant then
		self.pos = 1
		self.frame:Hide()
	end
end

-- parent: the window body (clips children). x/width/height: where the pane rests.
-- onClose() runs when the player closes it with Back or ×.
function UIDetail.create(parent, x, width, height, onClose)
	local UI = ns.UI
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	frame:SetFrameLevel(parent:GetFrameLevel() + 20)
	frame:EnableMouse(true) -- rows underneath don't take clicks through it

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.fill(bg, PANE_BG)
	local edge = frame:CreateTexture(nil, "BORDER")
	edge:SetWidth(1)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	UI.fill(edge, PANE_EDGE)

	local pane = setmetatable({ frame = frame, parent = parent, x = x, width = width, pos = 1, target = 1 }, Pane)
	local function close()
		pane:close(false)
		if onClose then
			onClose()
		end
	end

	local back = UI.button(frame, "\194\171 Back", 50, 14, close)
	back:SetPoint("TOPLEFT", 6, -3)
	local cross = UI.textButton(frame, "\195\151", 14)
	cross:SetPoint("TOPRIGHT", -4, -2)
	cross:SetScript("OnClick", close)

	pane.list = UI.newList(frame, width - 10, height - 21, LINE_H, false)
	pane.list.frame:SetPoint("TOPLEFT", 6, -20)
	frame:EnableMouseWheel(true) -- the wheel anywhere on the pane scrolls its lines
	frame:SetScript("OnMouseWheel", function(_, delta)
		pane.list:scrollTo(pane.list.scroll - delta * LINE_H * 2)
	end)

	frame:SetScript("OnUpdate", function(_, elapsed)
		if pane.pos == pane.target then
			return
		end
		local step = elapsed / SLIDE_TIME
		if pane.target < pane.pos then
			pane.pos = math.max(pane.target, pane.pos - step)
		else
			pane.pos = math.min(pane.target, pane.pos + step)
		end
		pane:place()
		if pane.pos >= 1 then
			frame:Hide()
		end
	end)
	frame:Hide()
	return pane
end
