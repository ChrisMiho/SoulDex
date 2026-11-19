-- Display rows for the dex window (pure; no WoW API except the date() fallback in
-- F.dateText when no formatter is passed). Turns View rows and details
-- into plain line descriptors the window paints:
--   { text, color, right, rightColor, value, selected, header, hr, big, wrap, bar, stripe }
-- `bar` is 0..1: a thin progress bar along the bottom of the row.
-- `value` is what a click passes back (nil = not clickable); colours are hex "rrggbb".
local _, ns = ...

local F = {}
ns.UIFormat = F

-- The window's colours by slot name (see src/Themes.lua), filled from the active theme by
-- F.applyTheme. Always this one table, refilled in place, so every file reading it follows
-- a theme change. ELITE / RARE / BOSS are the rarity colours, the same in every theme.
local C = {}
F.COLORS = C

F.DASH = ns.View.DASH
local TIMES = ns.View.TIMES
local DOT = " \194\183 "

-- Markers drawn as textures: the game font has no ★ / ☠ / ✓ glyphs.
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
local SKULL = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"
local SKULL_DIM = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0:0:0:0:64:64:0:64:0:64:120:85:65|t"
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t"
F.MARKS = { STAR = STAR, SKULL = SKULL, SKULL_DIM = SKULL_DIM, CHECK = CHECK }

-- A mastery star: the same star tinted in the theme's accent, so it isn't read as the
-- elite mark. Rebuilt by F.applyTheme as F.MARKS.ACCENT_STAR.
local function accentStar(hex)
	return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0:0:0:0:64:64:0:64:0:64:"
		.. tonumber(hex:sub(1, 2), 16) .. ":" .. tonumber(hex:sub(3, 4), 16) .. ":" .. tonumber(hex:sub(5, 6), 16) .. "|t"
end

-- Fills F.COLORS (in place) and the accent star from a theme (an id; unknown ids get the
-- default theme). Returns the id now in use.
function F.applyTheme(id)
	local Themes = ns.Themes
	id = Themes.id(id)
	for slot, hex in pairs(Themes.palette(id)) do
		C[slot] = hex
	end
	C.ELITE, C.RARE, C.BOSS = ns.Rarity.ELITE, ns.Rarity.RARE, ns.Rarity.BOSS
	F.MARKS.ACCENT_STAR = accentStar(C.ACCENT)
	Themes.current = id
	return id
end
F.applyTheme(ns.Themes.DEFAULT)

-- "3<star> ×212": a row's claim count with its mastery stars in front (none: just the count).
function F.masteryCount(stars, count)
	local text = F.countText(count)
	if stars and stars > 0 then
		return stars .. F.MARKS.ACCENT_STAR .. " " .. (text or "")
	end
	return text
end


local R = ns.Rarity
local STYLES = {
	elite = { color = R.color("elite"), mark = STAR, label = R.label("elite") },
	rareelite = { color = R.color("rareelite"), mark = STAR, label = R.label("rareelite") },
	rare = { color = R.color("rare"), label = R.label("rare") },
	worldboss = { color = R.color("worldboss"), mark = SKULL, label = R.label("worldboss") },
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

-- A class token ("ROGUE") as a name: the client's LOCALIZED_CLASS_NAMES_MALE when given.
function F.className(class, classNames)
	return classNames and classNames[class] or F.titleCase(class)
end

-- Hex class colour from RAID_CLASS_COLORS (or nil).
F.classHex = ns.Rarity.classHex

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
	return { text = text, color = C.MUTED, wrap = true }
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
				color = row.highlight and C.GOOD or (style and style.color) or C.TEXT,
				right = F.masteryCount(row.stars, row.count),
				stripe = style and style.color or C.DIVIDER, -- an ordinary soul's row; rarer ones use their colour
				value = row.name,
			}
		end
	end
	return out
end

function F.classRows(rows, selected, classColors, classNames)
	local out = {}
	for _, row in ipairs(rows) do
		local name = F.className(row.class, classNames)
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
			color = row.highlight and C.GOOD or C.TEXT,
			right = F.countText(row.count),
			value = row.key,
		}
	end
	return out
end

-- Rows are keyed by raid key (a TBD raid may have no instance id yet). A TBD raid shows
-- "TBD", or "N / ?" once souls were claimed there; it has no total, so no bar and no tick.
function F.raidRows(rows, selected)
	local out = {}
	for _, row in ipairs(rows) do
		local right = row.done and CHECK or (row.caught .. "/" .. row.total)
		if row.tbd then
			right = row.caught == 0 and "TBD" or (row.caught .. " / ?")
		end
		out[#out + 1] = {
			text = row.name,
			right = right,
			rightColor = (row.tbd and C.MUTED) or (row.done and C.GOOD) or nil,
			bar = (not row.done and row.total > 0) and (row.caught / row.total) or nil,
			value = row.key,
			selected = row.key == selected,
		}
	end
	return out
end

-- The first right-pane row of a raid whose creature list is not known yet.
function F.tbdNote(raid)
	if raid.bossCount then
		return F.note("Roster still sealed: " .. raid.bossCount
			.. " bosses wait inside. Every soul you claim here is kept.")
	end
	return F.note("Roster still sealed. Every soul you claim here is kept.")
end

-- Uncaught rows are "? ? ?" and not clickable; bosses keep their skull either way.
function F.raidMobRows(rows)
	local out = {}
	for _, row in ipairs(rows) do
		if row.caught then
			out[#out + 1] = {
				text = row.boss and (row.name .. " " .. SKULL) or row.name,
				color = row.highlight and C.GOOD or (row.boss and C.BOSS) or C.TEXT,
				right = F.masteryCount(row.stars, row.count),
				stripe = row.boss and C.BOSS or C.DIVIDER,
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

-- Earned: its name in fel green, the goal beside it, and the date. Not yet: dimmed, with
-- progress/goal and a progress bar.
function F.milestoneRows(items, fmt)
	local out = {}
	for _, item in ipairs(items) do
		local goal = item.title and (DOT .. item.text) or item.text
		if item.earned then
			out[#out + 1] = {
				text = item.title and ("|cff" .. C.ACCENT .. item.title .. "|r" .. goal) or goal,
				color = item.title and C.MUTED or C.WHITE,
				right = F.dateText(item.earned, fmt) or "",
			}
		else
			local progress = math.min(item.progress, item.goal)
			out[#out + 1] = {
				text = (item.title or "") .. goal,
				color = C.DIM,
				right = progress .. "/" .. item.goal,
				rightColor = C.DIM,
				bar = item.goal > 0 and (progress / item.goal) or nil,
			}
		end
	end
	return out
end

-- The trophy card (spec 5.5) ----------------------------------------------------------------
-- A card is what the detail pane draws:
--   { title, color, sub, badge, quote, icon, stars = { lit, total, extra, text, bar },
--     cells = { { label, value } x4 }, lines = { list line descriptors } }
-- Any field of the detail may be nil (a friend's dex has no dates, coordinates or levels):
-- a cell then shows a dash; sub, badge, quote and stars are left out.

-- An icon for each creature type, from the game's own icons. Keyed by the English type
-- name; unknown types and other client languages have none, and the window shows the
-- rank emblem instead.
local ICONS = "Interface\\Icons\\"
local TYPE_ICONS = {
	Beast = "Ability_Hunter_BeastTaming",
	Humanoid = "Ability_Rogue_Disguise",
	Undead = "Spell_Shadow_RaiseDead",
	Demon = "Spell_Shadow_SummonImp",
	Elemental = "Spell_Fire_Elemental_Totem",
	Dragonkin = "INV_Misc_Head_Dragon_01",
	Giant = "Spell_Nature_Earthquake",
	Mechanical = "INV_Gizmo_01",
	Critter = "Spell_Nature_Polymorph",
}
F.PLAYER_ICON = ICONS .. "Ability_DualWield"
F.CARD_STARS = 8

-- The icon path for a creature type, or nil when it has none.
function F.typeIcon(creatureType)
	local icon = creatureType and TYPE_ICONS[creatureType]
	return icon and (ICONS .. icon) or nil
end

local function cell(label, value)
	return { label = label, value = value or F.DASH }
end

-- The row of stars: `lit` of `total` are lit; stars past the row show as "+N".
local function starRow(m)
	if not m then
		return nil
	end
	local total = F.CARD_STARS
	return {
		lit = math.min(m.stars, total),
		total = total,
		extra = m.stars > total and (m.stars - total) or nil,
		text = m.count .. " / " .. m.to .. " to next star",
		bar = (m.count - m.from) / (m.to - m.from),
	}
end

-- Mob and raid-mob card (View.mobDetail / View.raidDetail).
function F.mobCard(d, fmt)
	local style = STYLES[d.classification]
	local sub = F.join({ style and style.label, F.join({ d.levelText, d.typeText }, " ", 2) }, DOT, 2)
	local you = d.myLevel and ("Lv " .. d.myLevel) or nil
	return {
		title = d.name or F.DASH,
		color = style and style.color or C.WHITE,
		sub = sub,
		badge = d.points and (d.points .. " pts") or nil,
		quote = d.flavour ~= "" and d.flavour or nil,
		icon = F.typeIcon(d.creatureType),
		stars = starRow(d.mastery),
		cells = {
			cell("Claimed", F.countText(d.count)),
			cell("First", F.join({ F.dateText(d.first, fmt), you }, DOT, 2)),
			cell("Where", F.coordsText(d.x, d.y) or d.place),
			cell("Last", F.dateText(d.last, fmt)),
		},
		lines = {},
	}
end

-- Player card (View.playerDetail). classNames: LOCALIZED_CLASS_NAMES_MALE (or nil).
function F.playerCard(d, fmt, classColors, classNames)
	local className = d.class and d.class ~= "" and F.className(d.class, classNames) or nil
	local firstLv = d.firstLevel and ("Lv " .. d.firstLevel) or nil
	local lastLv = d.lastLevel and ("Lv " .. d.lastLevel) or nil
	local lines = {}
	for _, p in ipairs(d.places or {}) do
		lines[#lines + 1] = {
			text = p.zone,
			color = C.TEXT,
			right = F.join({ F.coordsText(p.x, p.y), F.countText(p.count) }, "  ", 2) or "",
		}
	end
	return {
		title = d.name or F.DASH,
		color = F.classHex(d.class, classColors) or C.WHITE,
		sub = F.join({ d.levelRace, className }, " ", 2),
		badge = d.points and (d.points .. " pts") or nil,
		icon = F.PLAYER_ICON,
		cells = {
			cell("Sharded", F.countText(d.count)),
			cell("Guild", d.guild and d.guild ~= "" and ("<" .. d.guild .. ">") or nil),
			cell("First", F.join({ F.dateText(d.first, fmt), firstLv }, DOT, 2)),
			cell("Last", F.join({ F.dateText(d.last, fmt), lastLv }, DOT, 2)),
		},
		lines = lines,
	}
end

-- The stars of a card as text: lit ones fel green, the rest dark, then "+N" past the row.
local DARK_STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0:0:0:0:64:64:0:64:0:64:60:48:84|t"
function F.starText(stars)
	local text = string.rep(F.MARKS.ACCENT_STAR, stars.lit) .. string.rep(DARK_STAR, stars.total - stars.lit)
	if stars.extra then
		text = text .. " +" .. stars.extra
	end
	return text
end

-- Milestones, grouped (spec 5.6) ---------------------------------------------------------
-- Under each group's header ("MOBS", with "4 of 6"): the milestones still to earn, then
-- one row that opens and closes the earned ones (value "group:<name>"), so the next
-- goals sit on top. expanded: { [group] = true } for the groups whose earned rows show.
function F.milestoneGroups(items, groups, expanded, fmt)
	local out = {}
	for _, group in ipairs(groups) do
		local earned, open = {}, {}
		for _, item in ipairs(items) do
			if item.group == group then
				local list = item.earned and earned or open
				list[#list + 1] = item
			end
		end
		if #earned + #open > 0 then
			out[#out + 1] = {
				text = group:upper(),
				color = C.HEADER,
				header = true,
				right = #earned .. " of " .. (#earned + #open),
				rightColor = C.HEADER,
			}
			for _, row in ipairs(F.milestoneRows(open, fmt)) do
				row.text = "  " .. row.text
				out[#out + 1] = row
			end
			if #earned > 0 then
				local shown = expanded and expanded[group]
				out[#out + 1] = {
					text = CHECK .. " " .. #earned .. " earned",
					color = C.ACCENT,
					right = shown and "hide" or "show",
					rightColor = C.MUTED,
					value = "group:" .. group,
				}
				if shown then
					table.sort(earned, function(a, b)
						return a.earned > b.earned
					end)
					for _, row in ipairs(F.milestoneRows(earned, fmt)) do
						row.text = "  " .. row.text
						out[#out + 1] = row
					end
				end
			end
		end
	end
	return out
end

-- The Me tab (spec 5.8) ------------------------------------------------------------------

-- "today", "yesterday" or the date. Days are the player's local calendar days, read
-- through fmt (the game's date), so they agree with the dates shown beside them.
function F.whenText(t, now, fmt)
	if type(t) ~= "number" then
		return nil
	end
	if type(now) == "number" then
		fmt = fmt or date
		local day = fmt("%Y%j", t)
		if day == fmt("%Y%j", now) then
			return "today"
		end
		-- Around noon of the day before `now`: an hour either way (clock changes) is still that day.
		local hour = tonumber(fmt("%H", now)) or 0
		if day == fmt("%Y%j", now - (hour + 12) * 3600) then
			return "yesterday"
		end
	end
	return F.dateText(t, fmt)
end

-- The window title while browsing someone's dex: their name, or, for a saved copy
-- that may be out of date (savedAt: when it arrived), their first name and when the
-- copy is from, short enough that the date isn't cut off.
function F.browseTitle(owner, savedAt, now, fmt)
	local when = F.whenText(savedAt, now, fmt)
	if not when then
		return owner
	end
	return (owner:match("^%S+") or owner) .. " \194\183 saved " .. when
end

-- View.meCard's records as list lines. A record: { label, name, count, time, souls,
-- class, classification, text }.
function F.recordLines(records, now, fmt, classColors)
	local out = {}
	for i, r in ipairs(records) do
		local value, color = r.text, C.TEXT
		if r.souls then
			value = F.join({ r.souls .. " souls", F.dateText(r.time, fmt) }, DOT, 2)
		elseif r.name then
			value = r.name
			if r.count then
				value = value .. " " .. F.countText(r.count)
			end
			if r.time then
				value = F.join({ value, F.whenText(r.time, now, fmt) }, DOT, 2)
			end
			color = F.classHex(r.class, classColors) or (STYLES[r.classification] or {}).color or C.TEXT
		end
		out[i] = { text = r.label, color = C.MUTED, right = value or F.DASH, rightColor = color }
	end
	return out
end
