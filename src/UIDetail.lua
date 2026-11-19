-- The detail pane, drawn as a trophy card (spec 5.5): it slides in from the right edge
-- over the names list in 0.2 s, and "« Back" slides it away. Game code; what it shows is
-- a UIFormat card (F.mobCard / F.playerCard).
local _, ns = ...

local UIDetail = {}
ns.UIDetail = UIDetail

local SLIDE_TIME = 0.2
local LINE_H = 15
local PAD = 7
local BAND_H, ICON = 44, 30
local CELL_H, CELL_GAP = 25, 3

local Pane = {}
Pane.__index = Pane

-- pos: 0 = fully in, 1 = fully out. Squared so it eases out coming in and eases in going away.
function Pane:place()
	self.frame:ClearAllPoints()
	self.frame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + self.width * self.pos * self.pos, 0)
end

function Pane:open(card)
	self:setCard(card, false)
	self.target = 0
	self:place()
	self.frame:Show()
end

-- Lays the card out top to bottom; parts the card doesn't have are hidden and take no room.
function Pane:setCard(card, keepScroll)
	local UI, F = ns.UI, ns.UIFormat
	local C = F.COLORS
	local p = self.parts
	local color = card.color or C.WHITE
	local setShown = ns.UIList.setShown

	ns.UIList.gradient(p.band, "VERTICAL", color, 0, color, 0.3)
	UI.fill(p.iconEdge, color)
	p.icon:SetTexture(card.icon or ns.Ranks.emblem(1))
	-- The emblem is drawn whole (also as the fallback); a game icon has its border cropped off.
	local own = card.ownArt or not card.icon
	if own then
		p.icon:SetTexCoord(0, 1, 0, 1)
	else
		p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	p.title:SetText(card.title or "")
	UI.textColor(p.title, color)
	p.sub:SetText(card.sub or "")
	setShown(p.badge, card.badge ~= nil)
	if card.badge then
		p.badge.label:SetText(card.badge)
		p.badge:SetWidth(math.ceil(p.badge.label:GetStringWidth() or 0) + 10)
	end

	local y = BAND_H + 2
	setShown(p.quote, card.quote ~= nil)
	setShown(p.quoteBar, card.quote ~= nil)
	if card.quote then
		p.quote:ClearAllPoints()
		p.quote:SetPoint("TOPLEFT", PAD + 7, -y)
		p.quote:SetText(card.quote)
		local h = math.ceil(p.quote:GetStringHeight() or 0)
		p.quoteBar:ClearAllPoints()
		p.quoteBar:SetPoint("TOPLEFT", PAD, -y)
		p.quoteBar:SetHeight(math.max(h, 1))
		y = y + h + 6
	end

	local stars = card.stars
	for _, part in ipairs({ p.stars, p.starsNote, p.track }) do
		setShown(part, stars ~= nil)
	end
	local fill = stars and ns.UIList.barWidth(stars.bar, self.width - 2 * PAD)
	setShown(p.fill, fill ~= nil)
	if stars then
		p.stars:ClearAllPoints()
		p.stars:SetPoint("TOPLEFT", PAD, -y)
		p.stars:SetText(F.starText(stars))
		p.starsNote:ClearAllPoints()
		p.starsNote:SetPoint("TOPRIGHT", -PAD, -y - 1)
		p.starsNote:SetText(stars.text)
		p.track:ClearAllPoints()
		p.track:SetPoint("TOPLEFT", PAD, -y - 15)
		if fill then
			p.fill:ClearAllPoints()
			p.fill:SetPoint("TOPLEFT", PAD, -y - 15)
			p.fill:SetWidth(fill)
		end
		y = y + 24
	end

	local cellW = (self.width - 2 * PAD - CELL_GAP) / 2
	for i, box in ipairs(p.cells) do
		local data = card.cells and card.cells[i]
		setShown(box, data ~= nil)
		if data then
			local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
			box:ClearAllPoints()
			box:SetPoint("TOPLEFT", PAD + col * (cellW + CELL_GAP), -y - row * (CELL_H + CELL_GAP))
			box:SetSize(cellW, CELL_H)
			box.label:SetText(data.label:upper())
			box.value:SetText(data.value)
		end
	end
	y = y + 2 * (CELL_H + CELL_GAP) + 2

	-- Whatever is left (a player's places) scrolls below the cells, above the Back button.
	local lines = card.lines or {}
	local listH = math.max(LINE_H, self.height - y - 20)
	self.list.frame:ClearAllPoints()
	self.list.frame:SetPoint("TOPLEFT", PAD - 2, -y)
	self.list.frame:SetHeight(listH)
	self.list.height = listH
	self.list:set(lines, nil, keepScroll)
	self.list:show(#lines > 0)
end

-- Slides away (or hides at once when instant).
function Pane:close(instant)
	self.target = 1
	if instant then
		self.pos = 1
		self.frame:Hide()
	end
end

local function buildParts(frame, width)
	local UI = ns.UI
	local p = {}
	p.band = frame:CreateTexture(nil, "BORDER")
	p.band:SetPoint("TOPLEFT", 1, 0)
	p.band:SetPoint("TOPRIGHT")
	p.band:SetHeight(BAND_H)

	p.iconEdge = frame:CreateTexture(nil, "ARTWORK")
	p.iconEdge:SetSize(ICON + 2, ICON + 2)
	p.iconEdge:SetPoint("TOPLEFT", PAD, -6)
	-- Behind the icon, so the border colour doesn't show through an emblem's transparent corners.
	p.iconBack = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	p.iconBack:SetSize(ICON, ICON)
	p.iconBack:SetPoint("TOPLEFT", PAD + 1, -7)
	UI.fill(p.iconBack, "BG")
	p.icon = frame:CreateTexture(nil, "OVERLAY")
	p.icon:SetSize(ICON, ICON)
	p.icon:SetPoint("TOPLEFT", PAD + 1, -7)

	p.badge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	p.badge:SetSize(40, 15)
	p.badge:SetPoint("TOPRIGHT", -PAD + 1, -7)
	UI.backdrop(p.badge, "CHIP_BG", "CHIP_EDGE")
	p.badge.label = p.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.badge.label:SetPoint("CENTER")
	UI.textColor(p.badge.label, "GOOD")

	p.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", p.iconEdge, "TOPRIGHT", 7, -1)
	p.title:SetPoint("RIGHT", p.badge, "LEFT", -4, 0)
	p.title:SetJustifyH("LEFT")
	p.title:SetWordWrap(false)
	p.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.sub:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)
	p.sub:SetPoint("RIGHT", -PAD, 0)
	p.sub:SetJustifyH("LEFT")
	p.sub:SetWordWrap(false)
	UI.textColor(p.sub, "MUTED")

	p.quoteBar = frame:CreateTexture(nil, "ARTWORK")
	p.quoteBar:SetWidth(2)
	UI.fill(p.quoteBar, "QUOTE_BAR")
	p.quote = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.quote:SetWidth(width - 2 * PAD - 9)
	p.quote:SetJustifyH("LEFT")
	p.quote:SetWordWrap(true)
	UI.textColor(p.quote, "FLAVOUR")

	p.stars = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.stars:SetJustifyH("LEFT")
	UI.textColor(p.stars, "ACCENT")
	p.starsNote = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.starsNote:SetJustifyH("RIGHT")
	UI.textColor(p.starsNote, "MUTED")
	p.track = frame:CreateTexture(nil, "BORDER")
	p.track:SetSize(width - 2 * PAD, 3)
	UI.fill(p.track, "TRACK")
	p.fill = frame:CreateTexture(nil, "ARTWORK")
	p.fill:SetHeight(3)
	UI.fill(p.fill, "GOOD")

	p.cells = {}
	for i = 1, 4 do
		local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		UI.backdrop(box, "TILE_BG", "TILE_EDGE")
		box.label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.label:SetPoint("TOPLEFT", 5, -2)
		box.label:SetTextHeight(8)
		UI.textColor(box.label, "HEADER")
		box.value = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		box.value:SetPoint("BOTTOMLEFT", 5, 3)
		box.value:SetPoint("RIGHT", -3, 0)
		box.value:SetJustifyH("LEFT")
		box.value:SetWordWrap(false)
		UI.textColor(box.value, "TEXT")
		p.cells[i] = box
	end
	return p
end

-- parent: the window body (clips children). x/width/height: where the pane rests.
-- onClose() runs when the player closes it with Back.
function UIDetail.create(parent, x, width, height, onClose)
	local UI = ns.UI
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width, height)
	frame:SetFrameLevel(parent:GetFrameLevel() + 20)
	frame:EnableMouse(true) -- rows underneath don't take clicks through it

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	UI.fill(bg, "PANE_BG")
	local edge = frame:CreateTexture(nil, "BORDER")
	edge:SetWidth(1)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	UI.fill(edge, "HEADER")

	local pane = setmetatable({
		frame = frame, parent = parent, x = x, width = width, height = height, pos = 1, target = 1,
	}, Pane)
	local function close()
		pane:close(false)
		if onClose then
			onClose()
		end
	end

	pane.parts = buildParts(frame, width)
	local back = UI.button(frame, "\194\171 Back", 50, 14, close)
	back:SetPoint("BOTTOMRIGHT", -5, 4)

	pane.list = UI.newList(frame, width - 2 * PAD + 4, LINE_H, LINE_H, false)
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
