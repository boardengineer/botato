extends "res://singletons/coop_service.gd"

var current_player_index : int = 0
var main_player_device : int = -1
var main_player_index : int = -1
var is_bot_by_index : Array = [false, false, false, false]
# Per-bot auto-shop toggle (shopping + level-ups). Indexed by player_index, one
# entry per slot, default OFF (opt-in via each bot's AUTO-SHOP panel toggle). Only
# consulted for bot slots; reset with the bot flags.
var autoshop_by_index : Array = [false, false, false, false]

func _input(event):
	if event is InputEventKey and event.pressed:
		if get_tree().current_scene.name == "CharacterSelection":
			if event.scancode == KEY_F1 and main_player_device != -1:
				if connected_players.size() < 4:
					current_player_index = connected_players.size()
					is_bot_by_index[current_player_index] = true
					_add_player(connected_players.size(), PlayerType.KEYBOARD_AND_MOUSE)
					# Adding a co-op player normally flips the game into gamepad
					# (mouse-hidden) mode. This is a human commanding bots, so keep
					# the cursor -- InputService._process re-asserts it every frame.
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func clear_coop_players() -> void:
	# The base clear empties connected_players (mode switch, leaving a run) but
	# leaves is_bot_by_index set, so a stale bot flag would leak into the next
	# run -- e.g. a fresh solo player 0 inheriting a previous bot's slot flag.
	# Reset the bot flags whenever the player list is cleared.
	.clear_coop_players()
	is_bot_by_index = [false, false, false, false]
	autoshop_by_index = [false, false, false, false]
	current_player_index = 0


func get_remapped_player_device(player_index:int) -> int:
	return 7
#	if is_bot_by_index[player_index]:
#		return main_player_device
#	return .get_remapped_player_device(player_index)
