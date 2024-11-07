extends "res://ui/menus/global/focus_emulator.gd"


func _draw() -> void:
	._draw()

func _set_focused_control_with_style(control:Control, emit_signals:bool) -> void:
	print_debug("this is where i should be setting focus? ", control)
	_ensure_control_visible(control)
	if player_index != CoopService.current_player_index:
		return 
	._set_focused_control_with_style(control, emit_signals)


func _update_focus_style_for_players(control:Control) -> bool:
	var base_data = _find_control_base_data(control)
	if base_data == null:
		return false
	
	var player_indices = control.get_meta("focus_player_indices", [])
	if player_indices.empty():
		return false
	
	if player_indices[0] != CoopService.current_player_index:
		return true
	
	print_debug("updating for ", player_indices[0])
	return ._update_focus_style_for_players(control)


func _handle_input(event:InputEvent) -> bool:
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_TAB:
			print_debug("changing active player")
			CoopService.current_player_index = (1 + CoopService.current_player_index) % CoopService.connected_players.size()
			CoopService.emit_signal("selecting_player_changed")
			return true
	return ._handle_input(event)
