class_name LocalizationKeys
extends RefCounted


static func rank_key(rank: int) -> String:
	return ["rank.pawn", "rank.knight", "rank.rook", "rank.bishop", "rank.queen", "rank.king"][rank]


static func rank_name(rank: int) -> String:
	return Localization.text(rank_key(rank))


static func building_key(type: int) -> String:
	return [
		"building.farm",
		"building.workshop",
		"building.prison",
		"building.infirmary",
		"building.barracks",
	][type]


static func building_name(type: int) -> String:
	return Localization.text(building_key(type))


static func faction_name(faction: int) -> String:
	return Localization.text(["faction.player", "faction.enemy", "faction.outsider"][faction])


static func relationship_status(status: String) -> String:
	return Localization.text("relationship.%s" % status)


static func attention_name(level: int) -> String:
	return Localization.text([
		"attention.normal", "attention.notice", "attention.important", "attention.critical"
	][level])


static func rebellion_name(level: int) -> String:
	var keys := {
		GameEnums.RebellionLevel.NONE: "loyalty.stable",
		GameEnums.RebellionLevel.DISSATISFIED: "loyalty.dissatisfied",
		GameEnums.RebellionLevel.LOW_OUTPUT: "loyalty.low_output",
		GameEnums.RebellionLevel.OBJECTS_BUT_OBEYS: "loyalty.objects_but_obeys",
		GameEnums.RebellionLevel.RESISTS: "loyalty.resists",
		GameEnums.RebellionLevel.REVOLT: "loyalty.revolt",
	}
	return Localization.text(str(keys.get(level, "common.unknown")))
