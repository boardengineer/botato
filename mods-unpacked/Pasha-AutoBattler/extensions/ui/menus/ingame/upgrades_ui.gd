extends "res://ui/menus/ingame/upgrades_ui.gd"
# Automatic level-up choices for the AutoBattler bot. When the bot is enabled,
# whenever the level-up UI shows a player their options we pick the upgrade that
# best fits the character's build plan (ShopAdvisor.pick_upgrade), and auto-take
# any consumable/crate item. Gated by AutobattlerOptions.enable_autobattler.

const ShopAdvisor = preload("res://mods-unpacked/Pasha-AutoBattler/shopping/shop_advisor.gd")
const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")

const PICK_WAIT = 0.3    # pace between picks -- slow enough to watch each selection land
                         # (also must exceed the container's 0.1s ButtonDelayTimer, or a
                         # rapid 2nd pick hits `if _button_pressed: return` and no-ops)

var _auto_busy = false
var _auto_heartbeat = 0        # bumped each pick; the _process watchdog watches it for stalls
var _auto_seen_heartbeat = 0
var _auto_stall_frames = 0
var _plan_cache = {}   # player_index -> plan (co-op players can be different characters)
var _focus_outline = null


func _ready() -> void:
	._ready()
	if Coop.only_p1_is_human():
		# Start on the human's own options; TAB cycles to a still-choosing bot.
		CoopService.current_player_index = 0
		_focus_outline = Coop.make_outline()
		add_child(_focus_outline)

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
	# Outline the TAB-focused player's upgrade panel.
	if _focus_outline != null:
		var fpi = CoopService.current_player_index
		var fc = _get_player_container(fpi) if (fpi >= 0 and fpi < RunData.get_player_count()) else null
		Coop.update_outline_panel(_focus_outline, fc, fpi)
	# Self-healing auto-pick pump. A bot can be left with an unpicked option if the
	# loop ever exits early, or (defensively) if its coroutine dies mid-drain leaving
	# _auto_busy stuck true. Every frame: start the loop when a bot is waiting and
	# none is running; and if a loop is marked busy but has made no progress for
	# ~0.6s while a bot still waits, treat it as dead and reclaim it. Without this a
	# single stall freezes the whole run on the level-up screen.
	if not _bot_is_choosing():
		_auto_stall_frames = 0
		return
	if not _auto_busy:
		_auto_pick_loop()
		return
	if _auto_heartbeat != _auto_seen_heartbeat:
		_auto_seen_heartbeat = _auto_heartbeat
		_auto_stall_frames = 0
	else:
		_auto_stall_frames += 1
		if _auto_stall_frames > 40:
			_auto_busy = false
			_auto_stall_frames = 0


func _bot_is_choosing() -> bool:
	for pi in range(RunData.get_player_count()):
		if pi < _player_is_choosing.size() and _player_is_choosing[pi] and _should_autopick(pi):
			return true
	return false

# The upgrade choose / item take-discard buttons are plain Buttons that do NOT
# receive the GUI click in co-op even with listening_for_inputs held true (the
# same blocker as the shop). So route the mouse to the option under the cursor
# directly: motion moves the selection (highlight follows the mouse), a left-click
# takes it. Only for the lone human (slot 0); bots choose via _auto_pick_loop.
var _upg_hover_ctl = null
func _input(event: InputEvent) -> void:
	if not Coop.only_p1_is_human():
		return
	# TAB cycles the active player. The level-up screen's button focus-navigation
	# consumes TAB before the CoopService global handler sees it, so cycle here too
	# (this node's _input runs before GUI focus handling).
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_TAB:
		var before = CoopService.current_player_index
		Coop.cycle_focus()
		if CoopService.current_player_index != before:
			get_tree().set_input_as_handled()
		return
	# Drive the TAB-focused player's options (CoopService.current_player_index, set
	# by TAB). Only when that slot is actually choosing right now.
	var pi = CoopService.current_player_index
	if pi < 0 or pi >= _player_is_choosing.size() or not _player_is_choosing[pi]:
		return
	var container = _get_player_container(pi)
	if container == null:
		return
	var mouse = get_global_mouse_position()
	if event is InputEventMouseMotion:
		_update_upg_hover(container, mouse, pi)
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return
	# Carousel arrows: switch between upgrades, inventory, and character stats.
	var car = container.carousel if ("carousel" in container) else null
	if car != null:
		if _upg_hit(car.arrow_left, mouse):
			car.index = car.index - 1
			get_tree().set_input_as_handled()
			return
		if _upg_hit(car.arrow_right, mouse):
			car.index = car.index + 1
			get_tree().set_input_as_handled()
			return
	# Reroll the upgrade options.
	if ("_reroll_button" in container) and _upg_hit(container._reroll_button, mouse):
		container._on_RerollButton_pressed()
		get_tree().set_input_as_handled()
		return
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

# Move the keyboard selection to the choose option / item button / tab arrow under
# the cursor.
func _update_upg_hover(container, mouse, pi := 0) -> void:
	var target = null
	var car = container.carousel if ("carousel" in container) else null
	if car != null:
		if _upg_hit(car.arrow_left, mouse):
			target = car.arrow_left
		elif _upg_hit(car.arrow_right, mouse):
			target = car.arrow_right
	if target == null and ("_reroll_button" in container) and _upg_hit(container._reroll_button, mouse):
		target = container._reroll_button
	if target == null and container._upgrades_container.visible:
		for u in [container._upgrade_ui_1, container._upgrade_ui_2, container._upgrade_ui_3, container._upgrade_ui_4]:
			if u != null and is_instance_valid(u) and u.is_visible_in_tree() \
					and u.upgrade_data != null and u.button != null \
					and u.button.get_global_rect().has_point(mouse):
				target = u.button
				break
	elif target == null and container._items_container.visible:
		for btn in [container._take_button, container._discard_button, container._ban_button]:
			if _upg_hit(btn, mouse):
				target = btn
				break
	if target != null and target != _upg_hover_ctl:
		_upg_hover_ctl = target
		# The co-op upgrade container navigates with its OWN focus_emulator (set in
		# _show_next_player_options); focus through it, not the default one.
		var fe = container.focus_emulator if ("focus_emulator" in container) else null
		Utils.focus_player_control(target, pi, fe)

func _should_autopick(pi) -> bool:
	var opts = get_node_or_null("/root/AutobattlerOptions")
	if opts == null:
		return false
	# A co-op bot slot (F1-added) uses its OWN per-slot AUTO-SHOP toggle, checked
	# FIRST -- independent of the global AutoBattler switch, which may be on for the
	# human's own AI assist. This mirrors the combat gate (player_movement_behavior:
	# AI runs when enable_autobattler OR is_bot_by_index[pi]); checking the global
	# flag first here instead would ignore the per-bot toggles in co-op.
	var coop = get_node_or_null("/root/CoopService")
	if coop != null and pi < coop.is_bot_by_index.size() and coop.is_bot_by_index[pi]:
		return pi < coop.autoshop_by_index.size() and coop.autoshop_by_index[pi]
	# Otherwise pure-AutoBattler / WaveLab (every slot a bot): the global
	# enable_autoshop flag decides (default OFF; WaveLab sets it true).
	if opts.enable_autobattler:
		return opts.enable_autoshop
	return false

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
	_auto_stall_frames = 0
	var guard = 0
	while guard < 60:
		guard += 1
		var acted = false
		for pi in range(RunData.get_player_count()):
			if pi >= _player_is_choosing.size() or not _player_is_choosing[pi]:
				continue
			if not _should_autopick(pi):
				continue   # human slot in a mixed run: let the player choose
			var container = _get_player_container(pi)
			yield(get_tree().create_timer(PICK_WAIT), "timeout")
			if not _player_is_choosing[pi]:
				continue   # resolved while we waited
			# A bot IS still waiting on this slot, so mark progress up front: never
			# break out of the drain while any bot has an option, even if a pick is
			# momentarily blocked by the button-delay or the option list is empty.
			acted = true
			_auto_heartbeat += 1
			if container._upgrades_container.visible:
				var ups = container._old_upgrades
				if ups != null and ups.size() > 0:
					var idx = ShopAdvisor.pick_upgrade(ups, _plan_for(pi), pi)
					idx = int(clamp(idx, 0, ups.size() - 1))
					container._on_choose_button_pressed(ups[idx])
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
