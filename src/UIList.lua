-- A scrolling list of pooled rows painted from UIFormat line descriptors, plus the
-- small painting helpers every window part shares. Game code (exposed as ns.UIList
-- so the window, the detail pane and the Friends tab draw lists the same way).
local _, ns = ...

local L = {}
ns.UIList = L

local F = ns.UIFormat
local C = F.COLORS

local BAR_H = 2

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
}

-- Painting helpers (shared with the window, the detail pane and Options) -----------------------
-- A colour is a slot name from UIFormat.COLORS ("BORDER", "ACCENT": it follows the theme)
-- or a hex "rrggbb" (a soul's or class's own colour: it doesn't). What was painted by slot
-- name is remembered, weakly, so L.repaint() can paint it again after a theme change; a
-- later paint with hex only forgets it.

local painted = setmetatable({}, { __mode = "k" })

local function hex(color)
	return C[color] or color
end

local function remember(obj, kind, a, b, c, d, e)
	if C[a] or C[c] or (kind == "gradient" and C[d]) then
		painted[obj] = { kind, a, b, c, d, e }
	else
		painted[obj] = nil
	end
end

function L.textColor(fontString, color)
	remember(fontString, "textColor", color)
	local r, g, b = F.hexRGB(hex(color))
	fontString:SetTextColor(r, g, b, 1)
end

function L.fill(texture, color, alpha)
	remember(texture, "fill", color, alpha)
	local r, g, b = F.hexRGB(hex(color))
	texture:SetColorTexture(r, g, b, alpha or 1)
end

-- Shades a texture from one colour to another: "VERTICAL" runs bottom to top,
-- "HORIZONTAL" left to right. Clients name the call differently; where neither works
-- the texture is filled flat with the end colour.
function L.gradient(texture, orientation, from, fromAlpha, to, toAlpha)
	remember(texture, "gradient", orientation, fromAlpha, from, to, toAlpha)
	local r1, g1, b1 = F.hexRGB(hex(from))
	local r2, g2, b2 = F.hexRGB(hex(to))
	texture:SetColorTexture(1, 1, 1, 1)
	if texture.SetGradient and CreateColor then
		local fromColor, toColor = CreateColor(r1, g1, b1, fromAlpha), CreateColor(r2, g2, b2, toAlpha)
		if pcall(texture.SetGradient, texture, orientation, fromColor, toColor) then
			return
		end
	end
	if texture.SetGradientAlpha
		and pcall(texture.SetGradientAlpha, texture, orientation, r1, g1, b1, fromAlpha, r2, g2, b2, toAlpha) then
		return
	end
	texture:SetColorTexture(r2, g2, b2, toAlpha)
end

function L.backdrop(frame, bg, border, alpha)
	remember(frame, "backdrop", bg, alpha, border)
	frame:SetBackdrop(BACKDROP)
	local r, g, b = F.hexRGB(hex(bg))
	frame:SetBackdropColor(r, g, b, alpha or 1)
	r, g, b = F.hexRGB(hex(border))
	frame:SetBackdropBorderColor(r, g, b, 1)
end

-- Paints everything painted by slot name again, from UIFormat.COLORS as it is now.
function L.repaint()
	local jobs = {}
	for obj, job in pairs(painted) do
		jobs[#jobs + 1] = { obj, job }
	end
	for _, entry in ipairs(jobs) do
		local obj, job = entry[1], entry[2]
		local kind, a, b, c, d, e = job[1], job[2], job[3], job[4], job[5], job[6]
		if kind == "textColor" then
			L.textColor(obj, a)
		elseif kind == "fill" then
			L.fill(obj, a, b)
		elseif kind == "gradient" then
			L.gradient(obj, a, c, b, d, e)
		else
			L.backdrop(obj, a, c, b)
		end
	end
end

-- A small text button ("« Back", "Clean up"): theme-coloured, lighter on hover.
-- onClick is optional (callers may set OnClick later).
function L.button(parent, text, width, height, onClick)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, height)
	L.backdrop(button, "TAB_BG", "BUTTON_EDGE")
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("CENTER", 0, 0)
	button.label:SetText(text)
	L.textColor(button.label, "TITLE")
	button:SetScript("OnEnter", function(self)
		L.backdrop(self, "DIVIDER", "BUTTON_EDGE")
		L.textColor(self.label, "WHITE")
	end)
	button:SetScript("OnLeave", function(self)
		L.backdrop(self, "TAB_BG", "BUTTON_EDGE")
		L.textColor(self.label, "TITLE")
	end)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
end

-- Width in pixels of a progress bar's fill for a 0..1 fraction, or nil when there is
-- nothing to draw (no fraction, or an empty bar: a texture can't be 0 wide).
function L.barWidth(fraction, full)
	if type(fraction) ~= "number" or fraction <= 0 then
		return nil
	end
	return math.max(1, math.floor(full * math.min(fraction, 1) + 0.5))
end

function L.setShown(obj, shown)
	if shown then
		obj:Show()
	else
		obj:Hide()
	end
end

-- A scrolling list of pooled rows (mouse wheel; a thin thumb only when it overflows) -----

local List = {}
List.__index = List

function L.new(parent, width, height, rowHeight, lines)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	sf:SetSize(width, height)
	sf:EnableMouseWheel(true)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(width, 1)
	sf:SetScrollChild(child)
	local thumb = sf:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(2)
	L.fill(thumb, "BORDER", 0.8)
	thumb:Hide()

	local list = setmetatable({
		frame = sf,
		child = child,
		thumb = thumb,
		width = width,
		height = height,
		rowHeight = rowHeight,
		lines = lines,
		rows = {},
		scroll = 0,
		contentH = 0,
	}, List)
	sf:SetScript("OnMouseWheel", function(_, delta)
		list:scrollTo(list.scroll - delta * rowHeight * 2)
	end)
	return list
end

function List:scrollTo(y)
	local max = math.max(0, self.contentH - self.height)
	y = math.max(0, math.min(y, max))
	self.scroll = y
	self.frame:SetVerticalScroll(y)
	local thumb = self.thumb
	if max > 0 then
		local h = math.max(12, self.height * self.height / self.contentH)
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -(self.height - h) * (y / max))
		thumb:Show()
	else
		thumb:Hide()
	end
end

function List:row(i)
	local row = self.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, self.child)
	row:SetWidth(self.width)
	row.sel = row:CreateTexture(nil, "BACKGROUND")
	row.sel:SetAllPoints()
	L.fill(row.sel, "SELECTED")
	-- Left edge: the selection marker, or a stripe in the row's own colour (item.stripe).
	row.mark = row:CreateTexture(nil, "ARTWORK")
	row.mark:SetWidth(2)
	row.mark:SetPoint("TOPLEFT", 0, -2)
	row.mark:SetPoint("BOTTOMLEFT", 0, 2)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	L.fill(row.hover, "HOVER")
	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	L.fill(row.line, "ROW_LINE")
	-- Progress bar along the bottom (item.bar): a track and its fill.
	row.track = row:CreateTexture(nil, "BORDER")
	row.track:SetHeight(BAR_H)
	row.track:SetPoint("BOTTOMLEFT", 4, 0)
	row.track:SetPoint("BOTTOMRIGHT", -4, 0)
	L.fill(row.track, "TRACK")
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetHeight(BAR_H)
	row.bar:SetPoint("BOTTOMLEFT", 4, 0)
	L.fill(row.bar, "GOOD")
	row.rule = row:CreateTexture(nil, "BORDER")
	row.rule:SetHeight(1)
	row.rule:SetPoint("LEFT", 2, 0)
	row.rule:SetPoint("RIGHT", -2, 0)
	L.fill(row.rule, "TRACK")
	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.right:SetPoint("RIGHT", -4, 0)
	row.right:SetJustifyH("RIGHT")
	row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.left:SetJustifyH("LEFT")
	row:SetScript("OnClick", function(button)
		if button.onClick and button.value ~= nil then
			button.onClick(button.value)
		end
	end)
	self.rows[i] = row
	return row
end

-- items: UIFormat line descriptors. onClick(value) for rows with a value.
function List:set(items, onClick, keepScroll)
	local y = 0
	for i, item in ipairs(items) do
		local row = self:row(i)
		local left, right = row.left, row.right
		local h = item.hr and 5 or self.rowHeight
		left:SetFontObject(item.big and GameFontNormal or GameFontHighlightSmall)
		left:SetText(item.text or "")
		L.textColor(left, item.color or "TEXT")
		right:SetText(item.right or "")
		L.textColor(right, item.rightColor or "MUTED")
		left:ClearAllPoints()
		if item.wrap then
			left:SetPoint("TOPLEFT", 4, -1)
			left:SetWidth(self.width - 8)
			left:SetWordWrap(true)
			h = math.max(h, math.ceil(left:GetStringHeight() or 0) + 3)
		else
			left:SetWordWrap(false)
			left:SetPoint("LEFT", item.stripe and 7 or 4, 0)
			left:SetPoint("RIGHT", right, "LEFT", -4, 0)
		end
		L.setShown(left, not item.hr)
		L.setShown(right, not item.hr)
		L.setShown(row.rule, item.hr)
		L.setShown(row.sel, item.selected)
		local mark = item.selected and "ACCENT" or item.stripe
		if mark then
			L.fill(row.mark, mark)
		end
		L.setShown(row.mark, mark ~= nil and mark ~= false)
		local bar = L.barWidth(item.bar, self.width - 8)
		if bar then
			row.bar:SetWidth(bar)
		end
		L.setShown(row.bar, bar ~= nil)
		L.setShown(row.track, item.bar ~= nil)
		L.setShown(row.line, self.lines and not item.hr and not item.header and item.bar == nil)
		row.value = item.value
		row.onClick = onClick
		row:EnableMouse(item.value ~= nil and onClick ~= nil)
		row:SetHeight(h)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -y)
		row:Show()
		y = y + h
	end
	for i = #items + 1, #self.rows do
		self.rows[i]:Hide()
	end
	self.contentH = y
	self.child:SetHeight(math.max(y, 1))
	self:scrollTo(keepScroll and self.scroll or 0)
end

function List:show(shown)
	L.setShown(self.frame, shown)
end
