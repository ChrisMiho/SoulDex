-- The new-catch popup. Text builders are pure and tested; the frame is game code.
local _, ns = ...

local Toast = {}
ns.Toast = Toast

local WIDTH, HEIGHT = 300, 54
local SLIDE_IN, HOLD, FADE_OUT = 0.3, 4, 0.5
local TOP_OFFSET, SLIDE_DISTANCE = -140, 30

Toast.SHARD_ICON_FILE = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"

-- The Soul Shard icon. GetItemIcon is gone on WoW: Forever; C_Item.GetItemIconByID replaces it.
-- itemApi is C_Item (or nil), legacy is GetItemIcon (or nil); falls back to the icon file.
function Toast.shardIcon(itemApi, legacy)
	local getter = itemApi and itemApi.GetItemIconByID or legacy
	if getter then
		local ok, icon = pcall(getter, ns.Shards.ITEM_ID)
		if ok and icon and ns.Capture.readable(icon) then
			return icon
		end
	end
	return Toast.SHARD_ICON_FILE
end

-- Second line: "<zone> · Soul #<total> · +<points> pts", where total is how many different
-- souls the dex holds after this catch; without a total: "<zone> · +<points> pts".
function Toast.subtitle(result, zone)
	if result.total then
		return string.format("%s \194\183 Soul #%d \194\183 |cff7dff6a+%d pts|r", zone, result.total, result.points)
	end
	return string.format("%s \194\183 |cff7dff6a+%d pts|r", zone, result.points)
end

function Toast.nameLine(info)
	local label = ns.Rarity.label(info.classification)
	if label and not info.class then
		return info.name .. "  (" .. label .. ")"
	end
	return info.name
end

local frame

local function build()
	frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:EnableMouse(false)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	frame:SetBackdropColor(0x14 / 255, 0x10 / 255, 0x1c / 255, 0.95)
	frame:SetBackdropBorderColor(0x6b / 255, 0x4f / 255, 0xa0 / 255, 1)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(38, 38)
	frame.icon:SetPoint("LEFT", 8, 0)
	frame.icon:SetTexture(Toast.shardIcon(C_Item, GetItemIcon))

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, 0)
	frame.title:SetText("NEW SOUL CAUGHT!")
	frame.title:SetTextColor(0xc9 / 255, 0xa8 / 255, 1)

	frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.name:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -2)

	frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
	frame.sub:SetTextColor(0x9a / 255, 0x8f / 255, 0xb0 / 255)

	frame:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		local t = self.t
		local y, alpha = TOP_OFFSET, 1
		if t < SLIDE_IN then
			local p = t / SLIDE_IN
			y, alpha = TOP_OFFSET + SLIDE_DISTANCE * (1 - p), p
		elseif t > SLIDE_IN + HOLD then
			alpha = 1 - (t - SLIDE_IN - HOLD) / FADE_OUT
			if alpha <= 0 then
				self:Hide()
				return
			end
		end
		self:ClearAllPoints()
		self:SetPoint("TOP", UIParent, "TOP", 0, y)
		self:SetAlpha(alpha)
	end)
	frame:Hide()
end

-- Builds the frame ahead of time, so the first catch of a session doesn't pay for the
-- frame, its backdrop and the icon on top of the bag scan (a visible hitch). Run when the
-- world first loads and when the popup is switched on (Capture.prepareFor).
function Toast.prepare()
	if not frame then
		build()
	end
end

-- result: Dex.record* result; info: the mob/player details; ctx: catch context (needs zone);
-- color: the soul's hex colour (the same one its shard tooltip uses). A second catch
-- replaces the first.
function Toast.show(result, info, ctx, color)
	Toast.prepare()
	frame.name:SetText("|cff" .. (color or "ffffff") .. Toast.nameLine(info) .. "|r")
	frame.sub:SetText(Toast.subtitle(result, ctx.zone))
	frame.t = 0
	frame:SetAlpha(0)
	frame:Show()
end
