class_name PrisonSystem
extends RefCounted

const DEFAULT_GUARDS := 2

func labor_reduces_build_time(prisoner_count: int) -> bool:
	return prisoner_count > 0
