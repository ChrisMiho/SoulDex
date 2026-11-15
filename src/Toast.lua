-- The new-soul popup. Text builders are pure and tested; the frame is game code.
local _, ns = ...

local Toast = {}
ns.Toast = Toast

local WIDTH, HEIGHT = 330, 54
local SLIDE_IN, HOLD, FADE_OUT = 0.3, 4, 0.5
local TOP_OFFSET, SLIDE_DISTANCE = -140, 30
local RANK_OFFSET = TOP_OFFSET - HEIGHT - 8 -- the rank-up popup sits under the soul's
local SHINE_TIME, SHINE_W = 0.45, 26 -- one pass of light across the popup as it lands

-- Second line: "<zone> · Soul #<total>", where total is how many different souls the dex
-- holds after this claim; a star earned on a soul you already have shows its claim count
-- instead; with neither, the zone alone. The points are drawn large on the right.
function Toast.subtitle(result, zone)
	if result.stars and not result.isNew then
		return string.format("%s \194\183 \195\151%d claimed", zone, result.count)
	end
	if result.total then
		return string.format("%s \194\183 Soul #%d", zone, result.total)
	end
	return zone
end

-- "+25", the points this claim scored.
function Toast.pointsText(result)
	return "+" .. (result.points or 0)
end

-- The soul's name. Its rarity is in the title line (Toast.title), not repeated here.
function Toast.nameLine(info)
	return info.name
end

-- Top line: what was claimed, by rarity ("ELITE SOUL CLAIMED", "PLAYER SOUL CLAIMED"), or
-- the mastery stars this claim earned ("MASTERY: 3 STARS"). Rank-ups have their own popup.
function Toast.title(info, stars)
	if stars then
		return "MASTERY: " .. stars .. (stars == 1 and " STAR" or " STARS")
	end
	if info.class then
		return "PLAYER SOUL CLAIMED"
	end
	local label = ns.Rarity.label(info.classification)
	if label then
		return label:upper() .. " SOUL CLAIMED"
	end
	return "SOUL CLAIMED"
end

local BORDER, TITLE, FEL = "6b4fa0", "c9a8ff", "9dff3a"
local BG = "14101c"

local function rgb(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- Hex colours for the popup's border and title: fel green for a mastery star, the soul's
-- own colour for a rare one (anything not plain white), else the window's purple.
function Toast.accent(color, stars)
	if stars then
		return FEL, FEL
	end
	if type(color) == "string" and #color == 6 and color:lower() ~= "ffffff" then
		return color, color
	end
	return BORDER, TITLE
end

-- The rank-up popup's second line: "Rank 4 of 8 · next: Reaper at 2,500".
function Toast.rankSub(rank)
	local place = "Rank " .. rank.index .. " of " .. rank.count
	if rank.nextName then
		local at = ns.View and ns.View.thousands(rank.nextMin) or tostring(rank.nextMin)
		return place .. " \194\183 next: " .. rank.nextName .. " at " .. at
	end
	return place .. " \194\183 the highest rank"
end

local frames = {}

-- One popup frame resting at `offset` below the top of the screen.
local function build(offset)
	local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:EnableMouse(false)
	if frame.SetClipsChildren then
		frame:SetClipsChildren(true) -- the shine starts and ends outside the frame
	end
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	})
	frame:SetBackdropColor(rgb(BG))
	frame:SetBackdropBorderColor(rgb(BORDER))

	-- A fade of the soul's colour from the left edge, and a solid bar on that edge.
	frame.tint = frame:CreateTexture(nil, "BORDER")
	frame.tint:SetPoint("TOPLEFT", 1, -1)
	frame.tint:SetPoint("BOTTOMLEFT", 1, 1)
	frame.tint:SetWidth(WIDTH * 0.55)
	frame.bar = frame:CreateTexture(nil, "ARTWORK")
	frame.bar:SetWidth(3)
	frame.bar:SetPoint("TOPLEFT", 1, -1)
	frame.bar:SetPoint("BOTTOMLEFT", 1, 1)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(38, 38)
	frame.icon:SetPoint("LEFT", 12, 0)

	frame.pts = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.pts:SetPoint("RIGHT", -10, 4)
	frame.pts:SetJustifyH("RIGHT")
	frame.ptsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.ptsLabel:SetPoint("TOPRIGHT", frame.pts, "BOTTOMRIGHT", 0, -1)
	frame.ptsLabel:SetText("PTS")
	frame.ptsLabel:SetTextColor(0x9a / 255, 0x8f / 255, 0xb0 / 255)

	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, 0)
	frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.name:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -2)
	frame.name:SetPoint("RIGHT", frame.pts, "LEFT", -6, 0)
	frame.name:SetJustifyH("LEFT")
	frame.name:SetWordWrap(false)
	frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
	frame.sub:SetTextColor(0x9a / 255, 0x8f / 255, 0xb0 / 255)

	frame.shine = frame:CreateTexture(nil, "OVERLAY")
	frame.shine:SetSize(SHINE_W, HEIGHT)
	frame.shine:SetColorTexture(1, 1, 1, 0.12)
	frame.shine:Hide()

	frame:SetScript("OnUpdate", function(self, elapsed)
		self.t = (self.t or 0) + elapsed
		local t = self.t
		local y, alpha = offset, 1
		if t < SLIDE_IN then
			local p = t / SLIDE_IN
			y, alpha = offset + SLIDE_DISTANCE * (1 - p), p
		elseif t > SLIDE_IN + HOLD then
			alpha = 1 - (t - SLIDE_IN - HOLD) / FADE_OUT
			if alpha <= 0 then
				self:Hide()
				return
			end
		end
		-- The shine crosses once, right after the slide.
		local s = (t - SLIDE_IN) / SHINE_TIME
		if s >= 0 and s <= 1 then
			self.shine:ClearAllPoints()
			self.shine:SetPoint("LEFT", self, "LEFT", -SHINE_W + (WIDTH + SHINE_W) * s, 0)
			self.shine:Show()
		else
			self.shine:Hide()
		end
		self:ClearAllPoints()
		self:SetPoint("TOP", UIParent, "TOP", 0, y)
		self:SetAlpha(alpha)
	end)
	frame:Hide()
	return frame
end

-- Builds the frames ahead of time, so the first catch of a session doesn't pay for them,
-- their backdrops and the emblem texture file (loaded here by setting the first rank's;
-- show/showRank set the real one) on top of the bag scan (a visible hitch). Run when the
-- world first loads and when the popup is switched on (Capture.prepareFor).
function Toast.prepare()
	if not frames.soul then
		frames.soul = build(TOP_OFFSET)
		frames.rank = build(RANK_OFFSET)
		frames.soul.icon:SetTexture(ns.Ranks.emblem(1))
		frames.rank.icon:SetTexture(ns.Ranks.emblem(1))
	end
end

-- Colours a frame and starts its slide. accent: border, bar and fade; title: the top line.
local function present(frame, accent, title)
	frame:SetBackdropBorderColor(rgb(accent))
	frame.bar:SetColorTexture(rgb(accent))
	if ns.UIList then
		ns.UIList.gradient(frame.tint, "HORIZONTAL", accent, 0.24, accent, 0)
	else
		local r, g, b = rgb(accent)
		frame.tint:SetColorTexture(r, g, b, 0.08)
	end
	frame.title:SetTextColor(rgb(title))
	frame.t = 0
	frame:SetAlpha(0)
	frame:Show()
end

-- result: Dex.record* result; info: the mob/player details; ctx: catch context (needs zone);
-- color: the soul's hex colour (the same one its shard tooltip uses); emblem: the texture
-- path of the rank emblem to show (the first rank's when nil). A second catch replaces
-- the first.
function Toast.show(result, info, ctx, color, emblem)
	Toast.prepare()
	local frame = frames.soul
	frame.icon:SetTexture(emblem or ns.Ranks.emblem(1))
	local border, title = Toast.accent(color, result.stars)
	frame.title:SetText(Toast.title(info, result.stars))
	frame.name:SetText("|cff" .. (color or "ffffff") .. Toast.nameLine(info) .. "|r")
	frame.sub:SetText(Toast.subtitle(result, ctx.zone))
	frame.pts:SetText(Toast.pointsText(result))
	frame.pts:SetTextColor(0x7d / 255, 1, 0x6a / 255)
	present(frame, border, title)
end

-- The rank-up popup, under the soul's: the new rank, what comes next, and the score.
-- rank: ns.Ranks.of / gained; its emblem is shown on the left.
function Toast.showRank(rank)
	Toast.prepare()
	local frame = frames.rank
	frame.icon:SetTexture(rank.emblem or ns.Ranks.emblem(rank.index))
	frame.title:SetText("RANK UP")
	frame.name:SetText("|cff" .. FEL .. rank.name .. "|r")
	frame.sub:SetText(Toast.rankSub(rank))
	frame.pts:SetText(ns.View and ns.View.thousands(rank.score) or tostring(rank.score))
	frame.pts:SetTextColor(0xe8 / 255, 0xe0 / 255, 0xf0 / 255)
	present(frame, FEL, FEL)
end
