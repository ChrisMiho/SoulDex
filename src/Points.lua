-- Soul point values: what a first claim scores, and what claiming a soul again is
-- worth (pure; no WoW API).
local _, ns = ...

local Points = {}
ns.Points = Points

Points.PLAYER = 10

local BY_CLASSIFICATION = {
	normal = 1,
	minus = 1,
	elite = 5,
	rare = 10,
	rareelite = 10,
	worldboss = 25,
}

local RAID_BOSS = 25

function Points.forMob(classification, isRaidBoss)
	if isRaidBoss then
		return RAID_BOSS
	end
	return BY_CLASSIFICATION[classification] or 1
end

-- Repeat claims (spec 6.1) ---------------------------------------------------------------
-- A first claim scores the values above. What a repeat is worth depends on the soul:
--   "boss"     the same points again, every claim (raid lockouts are the limit)
--   "daily"    rares and players: a small bonus, at most once a day each
--   "mastery"  everything else: stars at claim counts, each star worth points once

Points.BOSS = RAID_BOSS
Points.DAILY_RARE = 2
Points.DAILY_PLAYER = 3

-- Claims of one mob that earn its first eight stars; after the last, one more star
-- every STAR_EVERY claims, with no end.
Points.STAR_STEPS = { 10, 25, 50, 100, 250, 500, 750, 1000 }
Points.STAR_EVERY = 500
-- Points for each of those stars, and for every star after them. Elites earn double.
local STAR_POINTS = { 1, 1, 2, 3, 5, 8, 8, 10 }
local STAR_POINTS_AFTER = 5

-- entry: a saved mob or raid entry (needs classification and its first-claim points).
-- flat: the entry is from a friend's dex, where points is its full worth and says nothing.
function Points.rule(entry, flat)
	local c = entry.classification
	if c == "worldboss" or (not flat and (entry.points or 0) >= RAID_BOSS) then
		return "boss"
	elseif c == "rare" or c == "rareelite" then
		return "daily"
	end
	return "mastery"
end

function Points.stars(count)
	local steps = Points.STAR_STEPS
	local n = 0
	for i, step in ipairs(steps) do
		if count >= step then
			n = i
		end
	end
	if n == #steps then
		n = n + math.floor((count - steps[n]) / Points.STAR_EVERY)
	end
	return n
end

-- The claim counts the current star was earned at (0 with no star) and the next comes at.
function Points.starSpan(count)
	local steps = Points.STAR_STEPS
	local last = steps[#steps]
	if count >= last then
		local from = last + math.floor((count - last) / Points.STAR_EVERY) * Points.STAR_EVERY
		return from, from + Points.STAR_EVERY
	end
	local from = 0
	for _, step in ipairs(steps) do
		if count < step then
			return from, step
		end
		from = step
	end
end

-- Every point a mob's stars have earned it.
function Points.starPoints(stars, classification)
	local total = 0
	for i = 1, stars do
		total = total + (STAR_POINTS[i] or STAR_POINTS_AFTER)
	end
	if classification == "elite" then
		total = total * 2
	end
	return total
end

-- Days since the epoch (UTC): two claims on the same day share a number.
function Points.day(t)
	return math.floor((t or 0) / 86400)
end

-- How many times a saved mob (per-place counts) or raid/player entry (one count) was claimed.
function Points.count(entry)
	if type(entry.places) == "table" and entry.count == nil then
		local n = 0
		for _, place in pairs(entry.places) do
			n = n + (place.count or 0)
		end
		return n
	end
	return entry.count or 0
end

-- Everything a saved mob or raid entry has scored: its first claim plus its repeats.
function Points.mobWorth(entry)
	local base = entry.points or 0
	local rule = Points.rule(entry)
	if rule == "boss" then
		return base * math.max(1, Points.count(entry))
	elseif rule == "daily" then
		return base + (entry.bonus or 0)
	end
	return base + Points.starPoints(Points.stars(Points.count(entry)), entry.classification)
end

function Points.playerWorth(entry)
	return (entry.points or 0) + (entry.bonus or 0)
end

-- Points for claiming a soul again. entry: as saved, already counting this claim;
-- before: its claim count before it; prevLast: when it was last claimed; now: this claim.
-- Adds daily bonuses to entry.bonus. Returns the points, and the mob's star count when
-- this claim earned a star.
function Points.again(entry, before, prevLast, now, isPlayer)
	local rule = isPlayer and "daily" or Points.rule(entry)
	if rule == "boss" then
		return entry.points or 0
	elseif rule == "daily" then
		if not (prevLast and now) or Points.day(now) <= Points.day(prevLast) then
			return 0
		end
		local gain = isPlayer and Points.DAILY_PLAYER or Points.DAILY_RARE
		entry.bonus = (entry.bonus or 0) + gain
		return gain
	end
	local was, is = Points.stars(before), Points.stars(Points.count(entry))
	if is > was then
		return Points.starPoints(is, entry.classification) - Points.starPoints(was, entry.classification), is
	end
	return 0
end
