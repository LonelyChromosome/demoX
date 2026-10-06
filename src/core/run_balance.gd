class_name RunBalance
extends RefCounted

# Enough for two planning days; production must cover day three onward.
const STARTING_FOOD := 8
const STARTING_MATERIALS := 3
const EVENT_COOLDOWN := 3
const REINFORCE_COST := 2
const REPAIR_COST := 2
const CRISIS_FIRST_DAY := 9
const CRISIS_LAST_DAY := 28


static func stage(day: int) -> String:
	if day <= 8:
		return "early"
	return "mid" if day <= 22 else "late"


static func roll(seed_value: int, day: int, channel: String, subject := "") -> int:
	var value := posmod(seed_value, 2147483647)
	var key := "%d|%s|%s" % [day, channel, subject]
	for index in range(key.length()):
		value = (value * 31 + key.unicode_at(index)) % 2147483647
	return value
