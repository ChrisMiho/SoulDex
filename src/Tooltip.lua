-- Names the soul on the Soul Shard tooltip (spec 6.3): the item name line becomes
-- "Soul of <name>" and a "<zone> · <date>" line is added. Nothing else changes.
-- Shards are looked up by item GUID in db.shardSouls. A creature or player whose soul
-- is in the dex gets one "Soul collected" line on its own tooltip (6.3a); one never
-- caught gets nothing. Every value read from a tooltip or unit is checked for secrets
-- first (ns.Capture's guards).
local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local UNKNOWN_COLOR = "9d9d9d"

-- The two lines for a soul { name, color, zone, time, unknown, pending }: "Soul of <name>"
-- (or a grey "Unknown soul") and "<zone> · <date>" ("<zone> · name pending" for a shard
-- still waiting for its soul's name).
function Tooltip.lines(soul, dateFn)
	local first
	if soul.unknown then
		first = "|cff" .. UNKNOWN_COLOR .. "Unknown soul|r"
	else
		first = "Soul of |cff" .. (soul.color or "ffffff") .. (soul.name or "?") .. "|r"
	end
	local second = soul.zone or ""
	if soul.pending then
		second = second ~= "" and (second .. " \194\183 name pending") or "name pending"
	elseif soul.time and dateFn then
		second = second .. " \194\183 " .. dateFn("%d %b %Y", soul.time)
	end
	return first, second
end

-- The shard's soul; a shard held for its soul's name shows as an Unknown soul for now.
local function soulFor(guid)
	local db = ns.db
	if not db then
		return nil
	end
	local soul = ns.Shards.soulOf(db.shardSouls, guid)
	if soul then
		return soul
	end
	local held = ns.Shards.pendingOf(db.shardSouls, guid)
	if held then
		local ctx = type(held.ctx) == "table" and held.ctx or {}
		local zone = type(ctx.zone) == "string" and ctx.zone or nil
		return { name = ns.Capture.UNKNOWN_SOUL, unknown = true, pending = true, zone = zone }
	end
	return nil
end

-- The tooltip's first line (the item name), or nil if it can't be found.
local function titleOf(tip)
	local fs = tip.TextLeft1
	if not fs then
		local name = ns.Capture.call(tip.GetName, tip)
		if ns.Capture.plainString(name) then
			fs = _G[name .. "TextLeft1"]
		end
	end
	if type(fs) == "table" and fs.SetText then
		return fs
	end
	return nil
end

-- "Soul of <name>" replaces the item name ("Soul Shard"), then the zone and date line.
-- If the name line can't be found, the soul line is added below instead.
local function addLines(tip, soul)
	local first, second = Tooltip.lines(soul, date)
	local title = titleOf(tip)
	if title then
		title:SetText(first)
		title:SetTextColor(0.79, 0.66, 1)
	else
		tip:AddLine(first, 0.79, 0.66, 1)
	end
	tip:AddLine(second, 0.6, 0.56, 0.69)
	tip:Show() -- re-fit the width to the longer name line
end

-- The hovered shard's GUID: the tooltip data's own, else the bag slot it was set from.
local function guidOf(tip, data)
	local C = ns.Capture
	if C.plainString(data.guid) then
		return data.guid
	end
	local info = C.call(tip.GetPrimaryTooltipInfo, tip)
	if not C.readableTable(info) or not C.readable(info.getterName) or info.getterName ~= "GetBagItem" then
		return nil
	end
	local args = info.getterArgs
	if not C.readableTable(args) then
		return nil
	end
	local bag, slot = args[1], args[2]
	if C.plainNumber(bag) and C.plainNumber(slot) then
		return C.itemGuid(bag, slot)
	end
	return nil
end

-- True when the tooltip may be changed: not forbidden, not protected right now.
local function changeable(tip)
	local C = ns.Capture
	if type(tip) ~= "table" then
		return false
	end
	local forbidden = C.call(tip.IsForbidden, tip)
	if not C.readable(forbidden) or forbidden then
		return false
	end
	local R = C_RestrictedActions
	if R and R.CheckAllowProtectedFunctions then
		local allowed = C.call(R.CheckAllowProtectedFunctions, tip, true)
		if not C.readable(allowed) or not allowed then
			return false
		end
	end
	return true
end

-- TooltipDataProcessor post-call for item tooltips.
function Tooltip.onItem(tip, data)
	local C = ns.Capture
	if not C.readableTable(data) or not C.plainNumber(data.id) or data.id ~= ns.Shards.ITEM_ID then
		return
	end
	if not changeable(tip) then
		return
	end
	local soul = soulFor(guidOf(tip, data))
	if soul then
		addLines(tip, soul)
	end
end

-- Fallback for clients without TooltipDataProcessor: GameTooltip:SetBagItem(bag, slot).
function Tooltip.onSetBagItem(tip, bag, slot)
	local C = ns.Capture
	if not C.plainNumber(bag) or not C.plainNumber(slot) then
		return
	end
	local itemID = C.call(C_Container.GetContainerItemID, bag, slot)
	if not C.plainNumber(itemID) or itemID ~= ns.Shards.ITEM_ID then
		return
	end
	local soul = soulFor(C.itemGuid(bag, slot))
	if soul then
		addLines(tip, soul)
	end
end

-- Unit tooltips ----------------------------------------------------------------------

-- The line under a caught soul's unit tooltip, or nil for one never caught.
function Tooltip.caughtLine(count)
	if type(count) ~= "number" or count < 1 then
		return nil
	end
	if count == 1 then
		return "Soul collected"
	end
	return "Soul collected \195\151" .. count
end

-- How many times the unit's soul is in the dex, or nil (never, or its name is hidden).
local function caughtCount(unit)
	local C, dex = ns.Capture, ns.dex
	if not dex then
		return nil
	end
	local name, second = C.call(UnitName, unit)
	if not C.plainString(name) or (UNKNOWNOBJECT ~= nil and name == UNKNOWNOBJECT)
		or (UNKNOWN ~= nil and name == UNKNOWN) then
		return nil
	end
	local guid = C.call(UnitGUID, unit)
	guid = C.plainString(guid) and guid or nil
	local isPlayer = C.call(UnitIsPlayer, unit)
	if not C.readable(isPlayer) then
		return nil
	end
	if isPlayer then
		-- Joined and keyed as the dex keys players (spec 4.3).
		local realm = C.call(GetRealmName)
		local full = ns.Friends.fullName(name, C.plainString(second) and second or nil)
		return dex:playerCaught(full, C.plainString(realm) and realm or nil)
	end
	return dex:mobCaught(name, C.npcIdFromGuid(guid))
end

local function addCaughtLine(tip, unit)
	local line = Tooltip.caughtLine(caughtCount(unit))
	if line then
		tip:AddLine(line, 0.79, 0.66, 1)
		tip:Show() -- re-fit the height to the new line
	end
end

-- The tooltip's unit token, or nil.
local function unitOf(tip)
	local C = ns.Capture
	local _, unit = C.call(tip.GetUnit, tip)
	if C.plainString(unit) then
		return unit
	end
	return nil
end

-- TooltipDataProcessor post-call for unit tooltips (and OnTooltipSetUnit without it).
function Tooltip.onUnit(tip)
	if not changeable(tip) then
		return
	end
	local unit = unitOf(tip)
	if unit then
		addCaughtLine(tip, unit)
	end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
	pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, Tooltip.onItem)
	if Enum.TooltipDataType.Unit ~= nil then
		pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, Tooltip.onUnit)
	end
elseif GameTooltip then
	pcall(hooksecurefunc, GameTooltip, "SetBagItem", Tooltip.onSetBagItem)
	pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", Tooltip.onUnit)
end
