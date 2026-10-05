class_name ObservedState
extends RefCounted

var facts: Dictionary = {}
var latest_report_entries: Array[ReportEntry] = []
var latest_report_day := 0


func upsert(fact: KnownFact) -> void:
	if fact != null and not fact.key.is_empty():
		facts[fact.key] = fact.copy()


func get_fact(key: String) -> KnownFact:
	return facts.get(key) as KnownFact


func set_daily_report(day: int, entries: Array[ReportEntry]) -> void:
	latest_report_day = day
	latest_report_entries.clear()
	for entry in entries:
		latest_report_entries.append(entry)