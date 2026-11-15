-- Names the soul on the Soul Shard tooltip (spec 6.3): the item name line becomes
-- "Soul of <name>" and a "<zone> · <date>" line is added. Nothing else changes.
-- Shards are looked up by item GUID in db.shardSouls; every value read from the
-- tooltip is checked for secrets first (ns.Capture's guards).
local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local UNKNOWN_COLOR = "9d9d9d"

-- The two lines for a soul { name, color, zone, time, unknown }: "Soul of <name>" (or a
-- grey "Unknown soul") and "<zone> · <date>".
function Tooltip.lines(soul, dateFn)
	local first
	if soul.unknown then
		first = "|cff" .. UNKNOWN_COLOR .. "Unknown soul|r"
	else
		first = "Soul of |cff" .. (soul.color or "ffffff") .. (soul.name or "?") .. "|r"
	end
	local second = soul.zone or ""
	if soul.time and dateFn then
		second = second .. " \194\183 " .. dateFn("%d %b %Y", soul.time)
	end
	return first, second
end

local function soulFor(guid)
	local db = ns.db
	return db and ns.Shards.soulOf(db.shardSouls, guid)
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

-- TooltipDataProcessor post-call for item tooltips.
function Tooltip.onItem(tip, data)
	local C = ns.Capture
	if type(tip) ~= "table" then
		return
	end
	local forbidden = C.call(tip.IsForbidden, tip)
	if not C.readable(forbidden) or forbidden then
		return
	end
	if not C.readableTable(data) or not C.plainNumber(data.id) or data.id ~= ns.Shards.ITEM_ID then
		return
	end
	local R = C_RestrictedActions
	if R and R.CheckAllowProtectedFunctions then
		local allowed = C.call(R.CheckAllowProtectedFunctions, tip, true)
		if not C.readable(allowed) or not allowed then
			return
		end
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

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
	pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, Tooltip.onItem)
elseif GameTooltip then
	pcall(hooksecurefunc, GameTooltip, "SetBagItem", Tooltip.onSetBagItem)
end
