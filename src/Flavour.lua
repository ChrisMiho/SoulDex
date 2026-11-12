-- Silly one-line flavour text for dex entries (pure; no WoW API).
-- Templates use {name}, {family}, {type} and {zone}. A template is only eligible when every
-- placeholder it uses has a value, so no line ever shows a blank or "nil".
local _, ns = ...

local Flavour = {}
ns.Flavour = Flavour

local TEMPLATES = {
	Beast = {
		"A {family} of {zone}. Bites first, howls later.",
		"{name} never asked to be a soul shard. Nobody does.",
		"Wild {family} spotted in {zone}. Now spotted in your bag.",
		"{name} had a very good coat. You ruined it.",
		"Fur, claws, regret. {name} of {zone}.",
	},
	Humanoid = {
		"{name} of {zone} had plans for the weekend.",
		"A humanoid with opinions. Now a humanoid with a shard.",
		"{name} picked a fight with a warlock. Bold.",
		"Somebody in {zone} is missing a {name}.",
		"{name} swore it was just a misunderstanding.",
	},
	Undead = {
		"{name} was already dead. You made it more official.",
		"Rest in pieces, {name} of {zone}.",
		"Twice dead, once collected.",
		"{name} rose from the grave. You sent it back with a receipt.",
		"Bones, rags, a grudge. {name} of {zone}.",
	},
	Demon = {
		"{name} thought it was the scary one in the room.",
		"A demon of {zone}. Your shard is its new home.",
		"{name} looked at you and saw a colleague. Awkward.",
		"Professional courtesy was not extended to {name}.",
		"Brimstone and bad manners. {name} of {zone}.",
	},
	Elemental = {
		"{name} of {zone}, now bottled.",
		"An elemental with a temper. The shard has a lid.",
		"{name} was mostly angry air. Now it is a shard.",
		"Raw elemental fury, filed under {zone}.",
		"{name} fizzled out. Dramatically.",
	},
	Dragonkin = {
		"{name} had the wings. You had the shard.",
		"A dragonkin of {zone} with a lot to say and no lungs left.",
		"Scales, smugness, and now a shard. {name}.",
		"{name} breathed fire. You breathed on its soul.",
		"Dragon-adjacent and shard-adjacent. {name}.",
	},
	Giant = {
		"{name} was big. The shard does not care.",
		"Tall in {zone}, tiny in a soul shard.",
		"{name} fell over. Loudly.",
		"A giant mistake, collected in {zone}.",
		"The bigger they are, the more room they take in the Dex.",
	},
	Mechanical = {
		"{name} powered down. Souls were not included, but you found one.",
		"Gears, grease, one stolen soul. {name} of {zone}.",
		"{name} has been turned off and on again, permanently off.",
		"A mechanical oddity of {zone}. Warranty void.",
		"Beep boop, {name} is now a shard.",
	},
	Critter = {
		"{name} was just trying to live in {zone}. Sorry.",
		"A critter. A very small soul. A very big feeling of guilt.",
		"{name} never saw it coming. It is a critter.",
		"One tiny {name}, one tiny shard of shame.",
		"Technically still counts. {name} of {zone}.",
	},
	["Not specified"] = {
		"{name} of {zone}. Nobody is quite sure what it was.",
		"Unclassified, uncategorised, and now unemployed. {name}.",
		"{name} defies description. You defied {name}.",
		"The Dex has a page for {name}, and a shrug.",
		"Mystery meat of {zone}: {name}.",
	},
}

-- Lines for one beast family, tried before the creature type's (spec 6.5). Keyed by the
-- English family name; other client languages fall back to the type's lines.
local FAMILIES = {
	Wolf = {
		"{name} howled at the moon. The moon did not help.",
		"A wolf of {zone}. The pack will notice the gap.",
		"{name} was all bark, then all bite, then all shard.",
	},
	Spider = {
		"{name} spun a lovely web in {zone}. Nobody will clean it up now.",
		"Eight legs, eight eyes, one soul. {name}.",
		"{name} was more scared of you than you were of it. Correctly.",
	},
	Boar = {
		"{name} charged first and thought never.",
		"A boar of {zone}. Somebody's dinner, now somebody's shard.",
		"{name} had tusks, a temper and no plan.",
	},
	Cat = {
		"{name} landed on its feet. Then on its side.",
		"A cat of {zone}. Nine lives, one shard.",
		"{name} stalked you for a mile. Bad choice of prey.",
	},
	Bear = {
		"{name} wanted a hug. You wanted a soul.",
		"A bear of {zone}, now hibernating in your bag.",
		"{name} was big, brown and briefly furious.",
	},
	Raptor = {
		"{name} was clever enough to open doors. Not shards.",
		"A raptor of {zone}. It hunted in packs; it was collected alone.",
		"{name} screeched. The shard did not.",
	},
	Crocolisk = {
		"{name} lay in wait in {zone}. You waited better.",
		"All teeth and no patience. {name}.",
		"{name} would have made a lovely pair of boots.",
	},
	Bat = {
		"{name} flapped around {zone} like it owned the place.",
		"A bat with sonar and no sense. {name}.",
		"{name} hung upside down. Now it hangs in your bag.",
	},
	Owl = {
		"{name} asked who. You answered.",
		"A wise owl of {zone}. Not wise enough.",
		"{name} saw everything coming, except you.",
	},
	Gorilla = {
		"{name} beat its chest. You beat its chest too, sort of.",
		"A gorilla of {zone}. Strong arms, weak soul.",
		"{name} threw something at you. You threw a curse back.",
	},
	Hyena = {
		"{name} laughed at you. Who's laughing now?",
		"A hyena of {zone}. The joke was on it.",
		"{name} cackled until the shard closed.",
	},
	Scorpid = {
		"{name} had a stinger and a bad attitude.",
		"A scorpid of {zone}. Pinch, sting, shard.",
		"{name} raised its tail in warning. Warning ignored.",
	},
	Turtle = {
		"{name} hid in its shell. The shell was not soul-proof.",
		"A turtle of {zone}. Slow to anger, slower to flee.",
		"{name} lived a hundred years and met you on the last one.",
	},
	["Carrion Bird"] = {
		"{name} circled the dead of {zone}. Now it is one of them.",
		"A vulture with ambitions. {name}.",
		"{name} was waiting for you to drop. Rude.",
	},
	Tallstrider = {
		"{name} had long legs and no reason to stay.",
		"A tallstrider of {zone}. Tall, striding, shard.",
		"{name} ran away very fast. Not fast enough.",
	},
	Crab = {
		"{name} scuttled sideways into your bag.",
		"A crab of {zone}. Snappy to the end.",
		"{name} was crabby. Understandably.",
	},
}

local GENERIC = {
	"{name} of {zone}. Another soul for the pile.",
	"{name} has been entered into the Dex. It did not consent.",
	"Gotta collect 'em all. This one was {name}.",
	"A wild {name} appeared, briefly.",
	"{name} is now a very small part of you.",
	"{name}: seen, smitten, shard-ed.",
	"The Dex remembers {name}, even if {name} would rather not.",
}

local function hash(text)
	local sum = 0
	for i = 1, #text do
		sum = sum + text:byte(i) * i
	end
	return sum
end

local function usable(template, values)
	for key in template:gmatch("{(%w+)}") do
		if not values[key] then
			return false
		end
	end
	return true
end

local function eligible(list, values)
	local result = {}
	for _, template in ipairs(list) do
		if usable(template, values) then
			result[#result + 1] = template
		end
	end
	return result
end

local function present(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function Flavour.line(name, creatureType, family, zone)
	name = present(name) or "Something"
	local values = {
		name = name,
		type = present(creatureType),
		family = present(family),
		zone = present(zone),
	}

	local candidates = eligible(values.family and FAMILIES[values.family] or {}, values)
	if #candidates == 0 then
		candidates = eligible(TEMPLATES[creatureType] or {}, values)
	end
	if #candidates == 0 then
		candidates = eligible(GENERIC, values)
	end

	local template = candidates[hash(name) % #candidates + 1]
	if values.zone and not template:find("{zone}", 1, true) then
		template = template .. " Found in {zone}."
	end
	return (template:gsub("{(%w+)}", function(key)
		return values[key]
	end))
end
