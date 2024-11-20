extends "res://singletons/coop_service.gd"

signal selecting_player_changed

var current_player_index = 0


func _ready():
	InputService.set_process_input(false)


func _input(event):
	_input_service_input(event)
	if event is InputEventKey and event.pressed:
#		if event.scancode == KEY_TAB:
#			print_debug("changing active player")
#			CoopService.current_player_index = (1 + CoopService.current_player_index) % CoopService.connected_players.size()
#			emit_signal("selecting_player_changed")
#			update_select_button_for_player()
		if get_tree().current_scene.name == "CharacterSelection":
			if event.scancode == KEY_F1:
				if connected_players.size() < 4:
					current_player_index = connected_players.size()
					_add_player(connected_players.size(), PlayerType.KEYBOARD_AND_MOUSE)


func _input_service_input(event:InputEvent)->void :
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if BugReporter.visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return 

	if RunData.is_coop_run and RunData.get_player_count() > 1:
#		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		return 

	var is_gamepad_input = event is InputEventJoypadButton or Utils.is_valid_joypad_motion_event(event)
	var is_keyboard_input = (event is InputEventKey)

	if InputService.hide_mouse and (is_gamepad_input or is_keyboard_input):
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	elif event is InputEventMouseMotion:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if is_gamepad_input:
		InputService.using_gamepad = true
	elif is_keyboard_input:
		InputService.using_gamepad = false
