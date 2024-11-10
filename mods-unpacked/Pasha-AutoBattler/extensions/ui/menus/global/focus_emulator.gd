extends "res://ui/menus/global/focus_emulator.gd"

var focus_by_player_index : Array = [null, null, null, null]


func _ready() -> void:
	var _err = get_viewport().connect("gui_focus_changed", self, "on_focus_changed")


func _draw() -> void:
	._draw()


func _set_focused_control_with_style(control:Control, emit_signals:bool) -> void:
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
	
	return ._update_focus_style_for_players(control)


func _handle_input(event:InputEvent) -> bool:
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_TAB:
			CoopService.current_player_index = (1 + CoopService.current_player_index) % CoopService.connected_players.size()
			CoopService.emit_signal("selecting_player_changed")
			
			if CoopService.focus_by_player_index[CoopService.current_player_index] and is_instance_valid(CoopService.focus_by_player_index[CoopService.current_player_index]):
				focused_control = CoopService.focus_by_player_index[CoopService.current_player_index]
				CoopService.focus_by_player_index[CoopService.current_player_index].grab_focus()
			
			return true
	if Utils.is_maybe_action_pressed(event, "ui_accept_%s" % _device):
		pass
		
		
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
			if focused_control.disabled:
				return true
			if focused_control is OptionButton:
				_open_option_button(focused_control)
			elif focused_control.toggle_mode:
				var toggled = not focused_control.pressed
				focused_control.set_pressed_no_signal(toggled)
				FocusEmulatorSignal.emit(focused_control, "toggled", player_index, toggled)
			else :
				FocusEmulatorSignal.emit(CoopService.focus_by_player_index[CoopService.current_player_index], "pressed", CoopService.current_player_index)
		return true
		
	return ._handle_input(event)


func on_focus_changed(focused_node : Control) -> void:
	CoopService.focus_by_player_index[CoopService.current_player_index] = focused_node


func _is_coop_ui_action(event:InputEvent) -> bool:
	return true
