extends "res://ui/menus/global/focus_emulator.gd"

var focus_by_player_index : Array = [null, null, null, null]


func _ready() -> void:
	var _err = get_viewport().connect("gui_focus_changed", self, "on_focus_changed")


func _draw()->void :
	if focused_control == null:
		return 
	
	var player_indices = focused_control.get_meta("focus_player_indices", [])
	if player_indices.size() == 0 or player_indices[0] != player_index:
		return 


func _set_focused_control_with_style(control:Control, emit_signals:bool) -> void:
	if focused_control: 
		if not focused_control.has_meta("original_stylebox_overrides"):
			var stylebox_overrides = {}
			for name in _stylebox_theme_names():
				if focused_control.has_stylebox_override(name):
					stylebox_overrides[name] = focused_control.get_stylebox(name)
			focused_control.set_meta("original_stylebox_overrides", stylebox_overrides)
	
	_ensure_control_visible(control)
	if player_index != CoopService.current_player_index:
		print_debug("wrong player index")
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
	
	return ._update_focus_style_for_players(control)


func _set_focus_state_for_current_player() -> void:
	_set_focus_for_player(CoopService.current_player_index)


func _set_focus_for_player(coop_player_index : int) -> void:
	if _can_focus_element_for_player(coop_player_index):
		focused_control = CoopService.focus_by_player_index[coop_player_index]
		if focused_control:
			var player_indices = focused_control.get_meta("focus_player_indices", [])
			if not player_indices.has(coop_player_index):
				player_indices.push_back(coop_player_index)
			focused_control.set_meta("focus_player_indices", player_indices)


func _can_focus_current_element() -> bool:
	return _can_focus_element_for_player(CoopService.current_player_index) 


func _can_focus_element_for_player(coop_player_index : int) -> bool:
	return CoopService.focus_by_player_index[coop_player_index] and is_instance_valid(CoopService.focus_by_player_index[coop_player_index])


func _handle_input(event:InputEvent) -> bool:
	if event is InputEventKey and event.pressed:
		print_debug("key registered in focus emulator")
		if event.scancode == KEY_TAB:
			print_debug("pressed tab ")
			# Save the focused state of the players we're leaving behind, maybe?
			
#			for player_index in CoopService.connected_players.size():
#				_set_focus_for_player(player_index)
			
			
			CoopService.current_player_index = (1 + CoopService.current_player_index) % CoopService.connected_players.size()
			CoopService.emit_signal("selecting_player_changed")
			
			if _can_focus_current_element():
				_set_focus_state_for_current_player()
				CoopService.focus_by_player_index[CoopService.current_player_index].grab_focus()
			
			for player_index in CoopService.connected_players.size():
				_set_focus_for_player(player_index)
				
			return true
		
	var modal = get_viewport().get_modal_stack_top()
	if modal is PopupMenu:
		if _find_control_base_data(modal) != null:
			return _handle_popup_menu_input(event, modal)

	if not is_instance_valid(focused_control):
		
		var new = _focused_parent.get_child(_focused_control_index)
		_set_focused_control_with_style(new, false)

	if focused_control is HSlider and _handle_hslider_input(event, focused_control):
		return true

	if Utils.is_maybe_action_pressed(event, "ui_accept_%s" % _device):
		if not focused_control.is_visible_in_tree():
			return true
		if focused_control is BaseButton:
			print_debug("accepted?")
#			print_debug("button?")
			if focused_control.disabled:
#				print_debug("disabled")
				return true
			if focused_control is OptionButton:
				_open_option_button(focused_control)
			elif focused_control.toggle_mode:
				var toggled = not focused_control.pressed
				focused_control.set_pressed_no_signal(toggled)
				FocusEmulatorSignal.emit(focused_control, "toggled", player_index, toggled)
			else :
				var current_focus = CoopService.focus_by_player_index[CoopService.current_player_index]
				if current_focus != null and is_instance_valid(current_focus):
					FocusEmulatorSignal.emit(current_focus, "pressed", CoopService.current_player_index)
				else:
					print_debug("no focus")
		return true
	
	var previous: = focused_control
	var result: = _get_focus_neighbour_for_event(event, previous)
	var new = result.control
	if not (new == null or new == previous):
		CoopService.focus_by_player_index[CoopService.current_player_index] = new
	
	return ._handle_input(event)


func on_focus_changed(focused_node : Control) -> void:
#	print_debug("focus changed?")
	CoopService.focus_by_player_index[CoopService.current_player_index] = focused_node


func _is_coop_ui_action(event:InputEvent) -> bool:
	return true


