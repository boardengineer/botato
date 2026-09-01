extends "res://ui/menus/ingame/upgrades_ui.gd"
# Automatic level-up choices for the AutoBattler bot. When the bot is enabled,
# whenever the level-up UI shows a player their options we pick the upgrade that
# best fits the character's build plan (ShopAdvisor.pick_upgrade), and auto-take
# any consumable/crate item. Gated by AutobattlerOptions.enable_autobattler.

const ShopAdvisor = preload("res://mods-unpacked/Pasha-AutoBattler/shopping/shop_advisor.gd")
const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")

const PICK_WAIT = 0.06   # let the container's button-delay timer clear between picks

var _auto_busy = false
var _plan_cache = {}   # player_index -> plan (co-op players can be different characters)

# Should THIS player slot's level-up be auto-picked by the bot? Mirrors the shop
# dispatch in base_shop._should_autoshop so combat, shopping and level-ups all
# agree on which slots are bot-controlled: global enable_autobattler makes every
# slot a bot (pure AutoBattler/WaveLab), otherwise it is the per-slot co-op flag
# (F1-added bots). Each bot slot's per-bot autoshop toggle (CoopService.
# autoshop_by_index, default on) then gates shopping AND level-ups for that slot.
# A human slot in a mixed run returns false so the player picks it.
# The level-up / crate-pickup UI runs with CoopService.listening_for_inputs =
# false, so the FocusEmulators swallow the human's mouse clicks on the choose /
# take / discard buttons. Hold it true (when a lone human commands bots) so those
# buttons are mouse-clickable. Harmless mid-wave (those emulators focus nothing).
func _process(_delta: float) -> void:
	Coop.keep_mouse_enabled()

# The upgrade choose / item take-discard buttons are plain Buttons that do NOT
# receive the GUI click in co-op even with listening_for_inputs held true (the
# same blocker as the shop). So route a left-click to the option under the cursor
# directly. Only for the lone human (slot 0); bots choose via _auto_pick_loop.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return
	if not Coop.only_p1_is_human() or _player_is_choosing.size() <= 0 or not _player_is_choosing[0]:
		return
	var container = _get_player_container(0)
	if container == null:
		return
	var mouse = get_global_mouse_position()
	if container._upgrades_container.visible:
		for u in [container._upgrade_ui_1, container._upgrade_ui_2, container._upgrade_ui_3, container._upgrade_ui_4]:
			if u != null and is_instance_valid(u) and u.is_visible_in_tree() \
					and u.upgrade_data != null and u.button != null \
					and u.button.get_global_rect().has_point(mouse):
				container._on_choose_button_pressed(u.upgrade_data)
				get_tree().set_input_as_handled()
				return
	elif container._items_container.visible:
		if _upg_hit(container._take_button, mouse):
			container._on_TakeButton_pressed()
			get_tree().set_input_as_handled()
		elif _upg_hit(container._discard_button, mouse):
			container._on_DiscardButton_pressed()
			get_tree().set_input_as_handled()

func _upg_hit(btn, mouse) -> bool:
	return btn != null and btn.is_visible_in_tree() and not btn.disabled and btn.get_global_rect().has_point(mouse)

func _should_autopick(pi) -> bool:
	var opts = get_node_or_null("/root/AutobattlerOptions")
	if opts == null:
		return false
	# Pure-AutoBattler / WaveLab: gated by the global enable_autoshop flag (default
	# OFF; WaveLab sets it true).
	if opts.enable_autobattler:
		return opts.enable_autoshop
	# Co-op: each F1-added bot opts in via its AUTO-SHOP toggle (default OFF).
	var coop = get_node_or_null("/root/CoopService")
	if coop == null or pi >= coop.is_bot_by_index.size() or not coop.is_bot_by_index[pi]:
		return false
	return pi < coop.autoshop_by_index.size() and coop.autoshop_by_index[pi]

func _any_autopick() -> bool:
	for pi in range(RunData.get_player_count()):
		if _should_autopick(pi):
			return true
	return false

func _plan_for(player_index):
	if not _plan_cache.has(player_index):
		var c = RunData.get_player_character(player_index)
		_plan_cache[player_index] = ShopAdvisor.get_plan(c.my_id if c != null else "")
	return _plan_cache[player_index]

func _show_next_player_options() -> bool:
	var r = ._show_next_player_options()
	if r and _any_autopick() and not _auto_busy:
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
			if not _should_autopick(pi):
				continue   # human slot in a mixed run: let the player choose
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
				# A crate/consumable item is shown. Items are free stats -- take
				# them. But an off-plan WEAPON (wrong set/type, e.g. a plank for
				# elemental Mage) does ~0 damage and would waste a weapon slot, so
				# recycle it for gold instead.
				var idata = container._item_data
				if idata is WeaponData and ShopAdvisor.score_weapon(idata, _plan_for(pi), pi) < 0.0:
					container._on_DiscardButton_pressed()
				else:
					container._on_TakeButton_pressed()
				acted = true
		if not acted:
			break
	_auto_busy = false
