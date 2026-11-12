-- Display rows for the dex window (pure; no WoW API). Turns View rows and details
-- into plain line descriptors the window paints:
--   { text, color, right, rightColor, value, selected, header, hr, big, wrap }
-- `value` is what a click passes back (nil = not clickable); colours are hex "rrggbb".
local _, ns = ...

local F = {}
ns.UIFormat = F

local C = {
	TEXT = "e8e0f0",
	WHITE = "ffffff",
	TITLE = "c9a8ff",
	MUTED = "9a8fb0",
	HEADER = "8a72b8",
	UNKNOWN = "4d4360",
	DIM = "6e6385",
	GREEN = "7dff6a",
	FLAVOUR = "ffd100",
	ELITE = "ffd25a",
	RARE = "c0c0c0",
	BOSS = "ff9a5a",
}
F.COLORS = C

F.DASH = "\226\128\148" -- em dash: a field the dex doesn't have
local TIMES = "\195\151" -- multiplication sign
local DOT = " \194\183 "

-- Markers drawn as textures: the game font has no ★ / ☠ / ✓ glyphs.
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"
local SKULL_DIM = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0:0:0:0:64:64:0:64:0:64:120:85:65|t"
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
F.MARKS = { STAR = STAR, SKULL = SKULL, SKULL_DIM = SKULL_DIM, CHECK = CHECK }

local STYLES = {
	elite = { color = C.ELITE, mark = STAR, label = "Elite" },
	rareelite = { color = C.RARE, mark = STAR, label = "Rare Elite" },
	rare = { color = C.RARE, label = "Rare" },
	worldboss = { color = C.BOSS, mark = SKULL, label = "Boss" },
}

-- Small helpers ----------------------------------------------------------------

function F.hexRGB(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- Joins the non-nil, non-empty parts with sep; nil when nothing is left.
function F.join(parts, sep, n)
	local kept = {}
	for i = 1, n or #parts do
		local part = parts[i]
		if part ~= nil and part ~= "" then
			kept[#kept + 1] = tostring(part)
		end
	end
	if #kept == 0 then
		return nil
	end
	return table.concat(kept, sep)
end

-- "26.4, 89.1", or nil when either coordinate is missing.
function F.coordsText(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return string.format("%.1f, %.1f", x, y)
end

-- "3 Nov 26", or nil without a time. fmt is the game's date() (os.date in tests).
function F.dateText(t, fmt)
	if type(t) ~= "number" then
		return nil
	end
	fmt = fmt or date
	return (fmt("%d %b %y", t):gsub("^0", ""))
end

function F.countText(count)
	if count == nil then
		return nil
	end
	return TIMES .. count
end

function F.titleCase(text)
	return text:sub(1, 1):upper() .. text:sub(2):lower()
end

-- Hex class colour from RAID_CLASS_COLORS (or nil).
function F.classHex(class, classColors)
	local c = class and classColors and classColors[class]
	if not c then
		return nil
	end
	local function byte(v)
		return math.floor(v * 255 + 0.5)
	end
	return string.format("%02x%02x%02x", byte(c.r), byte(c.g), byte(c.b))
end

-- The current selection if a row still has it in `field`, else the first row's, else nil.
function F.pick(rows, field, current)
	local first
	for _, row in ipairs(rows) do
		local value = row[field]
		if value ~= nil then
			if value == current then
				return current
			end
			first = first or value
		end
	end
	return first
end

-- Which lists keep their scroll position for a redraw: "select" (a click on the
-- left list) keeps the left and resets the right; "refresh" (a new catch, a compare
-- change) keeps both; anything else ("open", "tab") resets both.
local KEEP = { select = { true, false }, refresh = { true, true } }

function F.keepScroll(action)
	local keep = KEEP[action]
	if not keep then
		return false, false
	end
	return keep[1], keep[2]
end

function F.note(text)
	return { text = text, color = C.MUTED }
end

-- List rows ---------------------------------------------------------------------

function F.placeRows(rows, selected)
	local out = {}
	for _, row in ipairs(rows) do
		if row.header then
			out[#out + 1] = { text = row.header:upper(), color = C.HEADER, header = true }
		else
			out[#out + 1] = {
				text = row.place,
				right = tostring(row.count),
				value = row.place,
				selected = row.place == selected,
			}
		end
	end
	return out
end

function F.mobRows(rows)
	local out = {}
	for _, row in ipairs(rows) do
		if row.unknown then
			-- Hidden-name catches: muted, no detail pane (no value, not clickable).
			out[#out + 1] = { text = row.name, color = C.MUTED, right = F.countText(row.count) }
		else
			local style = STYLES[row.classification]
			local text = row.name
			if style and style.mark then
				text = text .. " " .. style.mark
			end
			out[#out + 1] = {
				text = text,
				color = row.highlight and C.GREEN or (style and style.color) or C.TEXT,
				right = F.countText(row.count),
				value = row.name,
			}
		end
	end
	return out
end

function F.classRows(rows, selected, classColors, classNames)
	local out = {}
	for _, row in ipairs(rows) do
		local name = classNames and classNames[row.class] or F.titleCase(row.class)
		out[#out + 1] = {
			text = name,
			color = F.classHex(row.class, classColors) or C.TEXT,
			right = tostring(row.count),
			value = row.class,
			selected = row.class == selected,
		}
	end
	return out
end

function F.playerRows(rows)
	local out = {}
	for _, row in ipairs(rows) do
		out[#out + 1] = {
			text = row.name or row.key,
			color = row.highlight and C.GREEN or C.TEXT,
			right = F.countText(row.count),
			value = row.key,
		}
	end
	return out
end

function F.raidRows(rows, selected)
	local out = {}
	for _, row in ipairs(rows) do
		out[#out + 1] = {
			text = row.name,
			right = row.done and CHECK or (row.caught .. "/" .. row.total),
			rightColor = row.done and C.GREEN or nil,
			value = row.instanceID,
			selected = row.instanceID == selected,
		}
	end
	return out
end

-- Uncaught rows are "? ? ?" and not clickable; bosses keep their skull either way.
function F.raidMobRows(rows)
	local out = {}
	for _, row in ipairs(rows) do
		if row.caught then
			out[#out + 1] = {
				text = row.boss and (row.name .. " " .. SKULL) or row.name,
				color = row.highlight and C.GREEN or (row.boss and C.BOSS) or C.TEXT,
				right = F.countText(row.count),
				value = row.npcID,
			}
		else
			out[#out + 1] = {
				text = row.boss and ("? ? ? " .. SKULL_DIM) or "? ? ?",
				color = C.UNKNOWN,
			}
		end
	end
	return out
end

-- Earned: bright, with the date. Not yet: dimmed, with progress/goal.
function F.milestoneRows(items, fmt)
	local out = {}
	for _, item in ipairs(items) do
		if item.earned then
			out[#out + 1] = {
				text = item.text,
				color = C.WHITE,
				right = F.dateText(item.earned, fmt) or "",
			}
		else
			out[#out + 1] = {
				text = item.text,
				color = C.DIM,
				right = math.min(item.progress, item.goal) .. "/" .. item.goal,
				rightColor = C.DIM,
			}
		end
	end
	return out
end

-- The Me tab's key/value lines (View.me): the same look as the detail pane. A line's
-- color names a COLORS key for its value.
function F.meLines(items)
	local out = {}
	for i, item in ipairs(items) do
		out[i] = {
			text = item.label,
			color = C.MUTED,
			right = item.value,
			rightColor = item.color and C[item.color] or C.TEXT,
		}
	end
	return out
end

-- Detail pane lines (spec 5.5) -----------------------------------------------------
-- Any field may be nil (a friend's dex has no dates, coordinates or levels): a
-- labelled line then shows a dash, an unlabelled one is left out.

local HR = { hr = true }

local function kv(label, value)
	return { text = label, color = C.MUTED, right = value or F.DASH, rightColor = C.TEXT }
end

-- Mob and raid-mob detail (View.mobDetail / View.raidDetail).
function F.mobDetailLines(d, fmt)
	local style = STYLES[d.classification]
	local lines = {
		{
			text = d.name or F.DASH,
			color = style and style.color or C.WHITE,
			right = style and style.label or nil,
			rightColor = style and style.color or nil,
			big = true,
		},
	}
	local sub = F.join({ d.levelText, d.typeText }, " ", 2)
	if sub then
		lines[#lines + 1] = { text = sub, color = C.MUTED }
	end
	if d.flavour and d.flavour ~= "" then
		lines[#lines + 1] = { text = "\"" .. d.flavour .. "\"", color = C.FLAVOUR, wrap = true }
	end
	lines[#lines + 1] = HR
	lines[#lines + 1] = kv("Caught", F.countText(d.count))
	local you = d.myLevel and ("you Lv " .. d.myLevel) or nil
	lines[#lines + 1] = kv("First", F.join({ F.dateText(d.first, fmt), you }, DOT, 2))
	lines[#lines + 1] = kv("Where", F.coordsText(d.x, d.y) or d.place)
	lines[#lines + 1] = kv("Last", F.dateText(d.last, fmt))
	if d.points then
		lines[#lines + 1] = HR
		lines[#lines + 1] = { text = d.points .. " pts", color = C.GREEN }
	end
	return lines
end

-- Player detail (View.playerDetail).
function F.playerDetailLines(d, fmt, classColors)
	local lines = {
		{ text = d.name or F.DASH, color = F.classHex(d.class, classColors) or C.WHITE, big = true },
	}
	if d.levelRaceClass and d.levelRaceClass ~= "" then
		lines[#lines + 1] = { text = d.levelRaceClass, color = C.MUTED }
	end
	if d.guild and d.guild ~= "" then
		lines[#lines + 1] = { text = "<" .. d.guild .. ">", color = C.GREEN }
	end
	lines[#lines + 1] = HR
	lines[#lines + 1] = kv("Sharded", F.countText(d.count))
	local firstLv = d.firstLevel and ("Lv " .. d.firstLevel) or nil
	local lastLv = d.lastLevel and ("Lv " .. d.lastLevel) or nil
	lines[#lines + 1] = kv("First", F.join({ F.dateText(d.first, fmt), firstLv }, DOT, 2))
	lines[#lines + 1] = kv("Last", F.join({ F.dateText(d.last, fmt), lastLv }, DOT, 2))
	if d.places and #d.places > 0 then
		lines[#lines + 1] = HR
		for _, p in ipairs(d.places) do
			lines[#lines + 1] = {
				text = p.zone,
				color = C.TEXT,
				right = F.join({ F.coordsText(p.x, p.y), F.countText(p.count) }, "  ", 2) or "",
			}
		end
	end
	if d.points then
		lines[#lines + 1] = HR
		lines[#lines + 1] = { text = d.points .. " pts", color = C.GREEN }
	end
	return lines
end
