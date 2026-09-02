extends "res://singletons/cursor_manager.gd"
# Keeps the mouse cursor visible when a lone human (player 1) is commanding an
# all-bot team. The base game hides the mouse on every input event in a co-op run
# with >1 player (it assumes co-op == gamepad twin-stick). The natural place to
# counter that per-frame is InputService, but it calls set_process(false) when no
# gamepad is connected, so its _process never runs for a keyboard+mouse player.
# CursorManager always processes, so we enforce visibility here.


func _process(delta) -> void:
	if _only_p1_is_human() and Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	._process(delta)


# True when 2+ players are connected, player 1 (slot 0) is a human, and every
# other slot is a bot.
func _only_p1_is_human() -> bool:
	var coop = get_node_or_null("/root/CoopService")
	if coop == null:
		return false
	var count = coop.connected_players.size()
	if count < 2 or coop.is_bot_by_index.size() < count:
		return false
	if coop.is_bot_by_index[0]:
		return false   # player 1 is itself a bot -> not a human commanding bots
	for i in range(1, count):
		if not coop.is_bot_by_index[i]:
			return false
	return true
