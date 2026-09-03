extends "res://ui/menus/global/focus_emulator.gd"


# A plain solo run (not a co-op run -- no F1 bots, no other humans) must not route input
# through the co-op FocusEmulator at all. Vanilla leaves this emulator dormant in solo
# (connected_players is empty, so _device stays -1); but the mod populates connected_players
# via the device-add on the select screens, which activates it. An active emulator then
# swallows the lone human's non-whitelisted keys in the shop -- ui_ban is whitelisted, but
# ui_select ('e' / lock) is not, which is why ban worked and lock didn't -- and hijacks the
# mouse's focus. So in a solo run, do nothing here and let vanilla Control focus + the shop's
# own input handle everything, exactly as an unmodded game does.
func _input(event: InputEvent) -> void:
	if not RunData.is_coop_run:
		return
	._input(event)


# Disable "wrong" players from using input
# Process player change action
func _handle_input(event:InputEvent) -> bool:
	if player_index != CoopService.current_player_index and not get_tree().current_scene.name == "DifficultySelection":
		return false
		
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_QUOTELEFT:
			CoopService.current_player_index = (CoopService.current_player_index + 1) % CoopService.connected_players.size()
			if get_tree().current_scene.name == "Main":
				update_player_index()
			return true
		
	var result = ._handle_input(event)
	if result and Utils.is_maybe_action_pressed(event, "ui_accept_%s" % _device):
		if get_tree().current_scene.name == "Main":
			update_player_index()
	return result


# Set all devices to the main player's device
func _on_connected_players_updated(connected_players:Array)->void :
	._on_connected_players_updated(connected_players)
	if CoopService.main_player_device == -1:
		CoopService.main_player_device = _device
		CoopService.main_player_index = player_index
	elif CoopService.is_bot_by_index[player_index] or player_index == -1:
		# TODO explains the player_index == -1 check that seems to be load-bearing
		_device = CoopService.main_player_device


# Enable the player change action to bypass is_coop_ui_action check
func _is_coop_ui_action(event:InputEvent)->bool:
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_QUOTELEFT:
			return true
	return ._is_coop_ui_action(event)


# After hitting accept, the focus controller might no longer accept input,
# In crement the current player to make sure a valid player has focus
func update_player_index() -> void:
	var choosing_players =  $"/root/Main/UI/CoopUpgradesUI"._player_is_choosing
	if not choosing_players[CoopService.current_player_index]:
		for index in choosing_players.size():
			if choosing_players[index]:
				CoopService.current_player_index = index
				return
