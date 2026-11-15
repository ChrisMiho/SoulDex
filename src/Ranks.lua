-- Warlock ranks: a title earned from the dex score (pure; no WoW API). Shown on the Me
-- tab, the Friends tab, the login line and the new-soul popup when a claim ranks you up.
local _, ns = ...

local Ranks = {}
ns.Ranks = Ranks

-- Ascending by `min`, the score a rank starts at. The first must start at 0.
Ranks.LIST = {
	{ min = 0, name = "Initiate" },
	{ min = 50, name = "Acolyte" },
	{ min = 250, name = "Soul Thief" },
	{ min = 1000, name = "Shardbinder" },
	{ min = 2500, name = "Reaper" },
	{ min = 5000, name = "Soul Harvester" },
	{ min = 10000, name = "Soul Tyrant" },
	{ min = 25000, name = "Lord of Souls" },
}

-- Rank-ups from this rank on go to guild chat (when announcements are on).
Ranks.ANNOUNCE_FROM = 5

-- The rank a score holds: { index, count, name, min, score, nextName, nextMin, toNext,
-- progress }. progress is 0..1 of the way to the next rank; at the highest rank it is 1
-- and the next* fields are nil. A score that isn't a number counts as 0.
function Ranks.of(score)
	if type(score) ~= "number" or score < 0 then
		score = 0
	end
	local list = Ranks.LIST
	local index = 1
	for i, rank in ipairs(list) do
		if score >= rank.min then
			index = i
		end
	end
	local rank, nextRank = list[index], list[index + 1]
	local out = { index = index, count = #list, name = rank.name, min = rank.min, score = score, progress = 1 }
	if nextRank then
		out.nextName, out.nextMin = nextRank.name, nextRank.min
		out.toNext = nextRank.min - score
		out.progress = (score - rank.min) / (nextRank.min - rank.min)
	end
	return out
end

-- The new rank when going from one score to another crossed a threshold, else nil.
function Ranks.gained(before, after)
	local was, now = Ranks.of(before), Ranks.of(after)
	if now.index > was.index then
		return now
	end
	return nil
end
