extends "res://singletons/input_service.gd"
# The base InputService force-hides the mouse in any co-op run with >1 player
# (it assumes co-op == gamepad twin-stick). But when player 1 is the only human
# and every other slot is a bot (F1-added bots), P1 still plays with the mouse,
# so the cursor must stay visible. We let the base logic run, then override the
# mouse mode back to VISIBLE for that specific case.


func _input(event: InputEvent) -> void:
	._input(event)
	if _only_p1_is_human():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# Per-event handling alone leaves a window where the cursor is hidden (e.g. right
# after F1, or while cycling slots with the keyboard). Re-assert visibility every
# frame while a lone human is commanding an all-bot team, so it never vanishes.
func _process(delta: float) -> void:
	._process(delta)
	if _only_p1_is_human() and Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# True when this is a co-op run with 2+ players and every slot other than
# player 1 is a bot -- i.e. a lone human commanding an all-bot team.
func _only_p1_is_human() -> bool:
	if not RunData.is_coop_run:
		return false
	var count = RunData.get_player_count()
	if count < 2:
		return false
	var coop = get_node_or_null("/root/CoopService")
	if coop == null:
		return false
	for i in range(1, count):
		if i >= coop.is_bot_by_index.size() or not coop.is_bot_by_index[i]:
			return false
	return true
