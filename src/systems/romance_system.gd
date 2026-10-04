class_name RomanceSystem
extends RefCounted

const PAWN_NIGHTS := 3
const ENEMY_QUEEN_NIGHTS := 5

enum RouteKind { NONE, PAWN, ENEMY_QUEEN_OFFERS, KING_PURSUITS_ENEMY_QUEEN }

var route: RouteKind = RouteKind.NONE
var target_unit_id := ""
var night_index := 0
var route_score := 0

func start(new_route: RouteKind, target_id: String) -> void:
	route = new_route
	target_unit_id = target_id
	night_index = 0
	route_score = 0

func choose(delta: int) -> void:
	route_score += delta
	night_index += 1

func required_nights() -> int:
	return PAWN_NIGHTS if route == RouteKind.PAWN else ENEMY_QUEEN_NIGHTS
