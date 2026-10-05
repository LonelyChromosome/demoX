class_name PerimeterLayout
extends RefCounted

# Presentation slots are intentionally semantic. A skin decides where each slot
# is drawn; gameplay never assumes that a compass direction belongs to a system.
var city_gate_anchor := "gate"
var rear_anchor := "rear"
var refugee_anchor := "refugee"
var forest_anchor := "forest"
var wasteland_anchor := "wasteland"
var slot_order: Array[String] = ["forest", "refugee", "wasteland"]


func anchor_for(location_id: String) -> String:
	match location_id:
		"refugee":
			return refugee_anchor
		"forest":
			return forest_anchor
		"wasteland":
			return wasteland_anchor
		"gate":
			return city_gate_anchor
		_:
			return rear_anchor
