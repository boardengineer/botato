extends "res://ui/menus/ingame/upgrades_ui.gd"
# Automatic level-up choices for the AutoBattler bot. When the bot is enabled,
# whenever the level-up UI shows a player their options we pick the upgrade that
# best fits the character's build plan (ShopAdvisor.pick_upgrade), and auto-take
# any consumable/crate item. Gated by AutobattlerOptions.enable_autobattler.

const ShopAdvisor = preload("res://mods-unpacked/Pasha-AutoBattler/shopping/shop_advisor.gd")

const PICK_WAIT = 0.06   # let the container's button-delay timer clear between picks

var _auto_busy = false
var _plan_cache = null

func _ab_enabled() -> bool:
	var opts = get_node_or_null("/root/AutobattlerOptions")
	return opts != null and opts.enable_autobattler

func _plan_for(player_index):
	if _plan_cache == null:
		var c = RunData.get_player_character(player_index)
		_plan_cache = ShopAdvisor.get_plan(c.my_id if c != null else "")
	return _plan_cache

func _show_next_player_options() -> bool:
	var r = ._show_next_player_options()
	if r and _ab_enabled() and not _auto_busy:
		_auto_pick_loop()
	return r

# Drains the whole level-up queue: pick for every player currently choosing,
# then let each choice surface the next option (which re-enters here, guarded by
# _auto_busy) until nobody is choosing.
func _auto_pick_loop() -> void:
	_auto_busy = true
	var guard = 0
	while guard < 40:
		guard += 1
		var acted = false
		for pi in range(RunData.get_player_count()):
			if not _player_is_choosing[pi]:
				continue
			var container = _get_player_container(pi)
			yield(get_tree().create_timer(PICK_WAIT), "timeout")
			if not _player_is_choosing[pi]:
				continue   # resolved while we waited
			if container._upgrades_container.visible:
				var ups = container._old_upgrades
				if ups != null and ups.size() > 0:
					var idx = ShopAdvisor.pick_upgrade(ups, _plan_for(pi), pi)
					container._on_choose_button_pressed(ups[idx])
					acted = true
			elif container._items_container.visible:
				container._on_TakeButton_pressed()   # take the crate item / consumable
				acted = true
		if not acted:
			break
	_auto_busy = false
