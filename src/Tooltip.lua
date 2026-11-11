-- Adds the soul name to the Soul Shard tooltip (spec 6.3). Nothing else changes.
-- Shards are looked up by item GUID in db.shardSouls; every value read from the
-- tooltip is checked for secrets first (ns.Capture's guards).
local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local SHARD_ITEM_ID = 6265
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

local function addLines(tip, soul)
	local first, second = Tooltip.lines(soul, date)
	tip:AddLine(first, 0.79, 0.66, 1)
	tip:AddLine(second, 0.6, 0.56, 0.69)
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
	if not C.readableTable(data) or not C.plainNumber(data.id) or data.id ~= SHARD_ITEM_ID then
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
	if not C.plainNumber(itemID) or itemID ~= SHARD_ITEM_ID then
		return
	end
	local soul = soulFor(C.itemGuid(bag, slot))
	if soul then
		addLines(tip, soul)
		tip:Show()
	end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
	pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, Tooltip.onItem)
elseif GameTooltip then
	pcall(hooksecurefunc, GameTooltip, "SetBagItem", Tooltip.onSetBagItem)
end
