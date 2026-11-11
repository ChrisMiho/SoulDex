-- Adds the soul name to the Soul Shard tooltip (spec 6.3). Nothing else changes.
local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local SHARD_ITEM_ID = 6265

-- The two lines for a soul { name, color, zone, time }: "Soul of <name>" and "<zone> · <date>".
function Tooltip.lines(soul, dateFn)
	local color = soul.color or "ffffff"
	local first = "Soul of |cff" .. color .. (soul.name or "?") .. "|r"
	local second = soul.zone or ""
	if soul.time and dateFn then
		second = second .. " \194\183 " .. dateFn("%d %b %Y", soul.time)
	end
	return first, second
end

function Tooltip.onSetBagItem(tip, bag, slot)
	local db = ns.db
	if not db or not db.shardSlots then
		return
	end
	if C_Container.GetContainerItemID(bag, slot) ~= SHARD_ITEM_ID then
		return
	end
	local soul = db.shardSlots[bag .. ":" .. slot]
	if not soul then
		return
	end
	local first, second = Tooltip.lines(soul, date)
	tip:AddLine(first, 0.79, 0.66, 1)
	tip:AddLine(second, 0.6, 0.56, 0.69)
	tip:Show()
end

hooksecurefunc(GameTooltip, "SetBagItem", Tooltip.onSetBagItem)
