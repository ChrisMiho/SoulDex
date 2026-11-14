-- A scrolling list of pooled rows painted from UIFormat line descriptors, plus the
-- small painting helpers every window part shares. Game code (exposed as ns.UIList
-- so the window, the detail pane and the Friends tab draw lists the same way).
local _, ns = ...

local L = {}
ns.UIList = L

local F = ns.UIFormat
local C = F.COLORS

local BORDER = "6b4fa0"
local SELECTED, HOVER, ROW_LINE, RULE = "3a2a55", "2a2040", "1d1629", "2d2240"

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
}

-- Painting helpers (shared with the window, the detail pane and Options) -----------------------

function L.textColor(fontString, hex)
	local r, g, b = F.hexRGB(hex)
	fontString:SetTextColor(r, g, b, 1)
end

function L.fill(texture, hex, alpha)
	local r, g, b = F.hexRGB(hex)
	texture:SetColorTexture(r, g, b, alpha or 1)
end

function L.backdrop(frame, bg, border, alpha)
	frame:SetBackdrop(BACKDROP)
	local r, g, b = F.hexRGB(bg)
	frame:SetBackdropColor(r, g, b, alpha or 1)
	r, g, b = F.hexRGB(border)
	frame:SetBackdropBorderColor(r, g, b, 1)
end

local BUTTON_BG, BUTTON_BORDER, BUTTON_HOVER = "251b36", "5a4486", "3d2d5c"

-- A small text button ("« Back", "Clean up"): dark purple, lighter on hover.
-- onClick is optional (callers may set OnClick later).
function L.button(parent, text, width, height, onClick)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, height)
	L.backdrop(button, BUTTON_BG, BUTTON_BORDER)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("CENTER", 0, 0)
	button.label:SetText(text)
	L.textColor(button.label, C.TITLE)
	button:SetScript("OnEnter", function(self)
		L.backdrop(self, BUTTON_HOVER, BUTTON_BORDER)
		L.textColor(self.label, C.WHITE)
	end)
	button:SetScript("OnLeave", function(self)
		L.backdrop(self, BUTTON_BG, BUTTON_BORDER)
		L.textColor(self.label, C.TITLE)
	end)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
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
	L.fill(thumb, BORDER, 0.8)
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
	L.fill(row.sel, SELECTED)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	L.fill(row.hover, HOVER)
	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetHeight(1)
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	L.fill(row.line, ROW_LINE)
	row.rule = row:CreateTexture(nil, "BORDER")
	row.rule:SetHeight(1)
	row.rule:SetPoint("LEFT", 2, 0)
	row.rule:SetPoint("RIGHT", -2, 0)
	L.fill(row.rule, RULE)
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
		L.textColor(left, item.color or C.TEXT)
		right:SetText(item.right or "")
		L.textColor(right, item.rightColor or C.MUTED)
		left:ClearAllPoints()
		if item.wrap then
			left:SetPoint("TOPLEFT", 4, -1)
			left:SetWidth(self.width - 8)
			left:SetWordWrap(true)
			h = math.max(h, math.ceil(left:GetStringHeight() or 0) + 3)
		else
			left:SetWordWrap(false)
			left:SetPoint("LEFT", 4, 0)
			left:SetPoint("RIGHT", right, "LEFT", -4, 0)
		end
		L.setShown(left, not item.hr)
		L.setShown(right, not item.hr)
		L.setShown(row.rule, item.hr)
		L.setShown(row.sel, item.selected)
		L.setShown(row.line, self.lines and not item.hr and not item.header)
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
