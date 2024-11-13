extends "res://ui/menus/ingame/upgrades_ui.gd"


func _on_choose_button_pressed(upgrade_data:UpgradeData, player_index:int)->void :
	._on_choose_button_pressed(upgrade_data, player_index)
	var _all_player_containers : Array = [_player_container1, _player_container2, _player_container3, _player_container4]
	print_debug("(outer) pressed choose button for player ", player_index, " ", _player_is_choosing)
	var num_players = _player_is_choosing.size()
	var iterating_player_index = (player_index + 1) % num_players
	while iterating_player_index != player_index:
		print_debug("iterating player ", iterating_player_index, " ", _player_is_choosing[iterating_player_index])
		if _player_is_choosing[iterating_player_index]:
			CoopService.current_player_index = iterating_player_index
			CoopService.emit_signal("selecting_player_changed")
			_all_player_containers[iterating_player_index].focus()
			break
		
		iterating_player_index = (iterating_player_index + 1) % num_players
		
	print_debug("completed choose button extension")
