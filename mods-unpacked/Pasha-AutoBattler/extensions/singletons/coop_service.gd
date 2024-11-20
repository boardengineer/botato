extends "res://singletons/coop_service.gd"

var current_player_index : int = 0
var main_player_device : int = -1
var main_player_index : int = -1
var is_bot_by_index : Array = [false, false, false, false]

func _input(event):
	if event is InputEventKey and event.pressed:
		if get_tree().current_scene.name == "CharacterSelection":
			if event.scancode == KEY_F1 and main_player_device != -1:
				if connected_players.size() < 4:
					current_player_index = connected_players.size()
					is_bot_by_index[current_player_index] = true
					_add_player(connected_players.size(), PlayerType.KEYBOARD_AND_MOUSE)


func get_remapped_player_device(player_index:int) -> int:
	return 7
#	if is_bot_by_index[player_index]:
#		return main_player_device
#	return .get_remapped_player_device(player_index)
