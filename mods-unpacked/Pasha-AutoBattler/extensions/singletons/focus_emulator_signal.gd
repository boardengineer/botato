extends "res://singletons/focus_emulator_signal.gd"

var override_player_index = false

func get_player_index(expected_control : Control) -> int:
	if override_player_index:
		return CoopService.current_player_index
	return .get_player_index(expected_control)
