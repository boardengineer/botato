extends "res://ui/menus/shop/base_shop.gd"
# Automatic shopping for the AutoBattler bot. When the bot is enabled, on shop
# entry it scores the offering with ShopAdvisor and buys / rerolls / leaves the
# shop on its own. Gated by AutobattlerOptions.enable_autobattler so ordinary
# human runs are completely untouched.

const ShopAdvisor = preload("res://mods-unpacked/Pasha-AutoBattler/shopping/shop_advisor.gd")
const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")

const SETUP_WAIT = 0.35   # let _ready() finish populating the offering + UI
const BUY_WAIT = 0.09     # container enforces a 0.05s buy lockout; clear it
const REROLL_WAIT = 0.12
const GO_WAIT = 0.15
const MAX_ACTIONS = 250   # hard stop against any pathological loop (buys + rerolls, incl. surplus-spend)
const LOCK_MIN_SCORE = 28.0  # only save for a weapon at least this good (tier 2+ on-plan, or a combine)
const LOCK_REACH = 70        # only save if its price is within ~one wave's income of current gold
const SURPLUS_KEEP = 120     # spend_surplus: keep rerolling while gold stays above this
const SURPLUS_MAX_REROLLS = 45  # spend_surplus: hard cap on total rerolls per shop
const HUNT_KEEP = 30         # reroll-to-find (prefer_weapons): keep at least this much gold to buy the weapon once found (30 surfaced tasers + a taser_4 win; 60 was too passive to find any)
const HUNT_MAX_REROLLS = 15  # reroll-to-find: hard cap on hunt rerolls per shop

var _focus_outline = null
var _prev_ban_cur = -1   # last slot whose ban buttons were restored on TAB focus change

func _ready() -> void:
	._ready()
	Coop.keep_mouse_enabled()
	if Coop.only_p1_is_human():
		# Start each shop on the human's own panel; TAB cycles to a bot's shop.
		CoopService.current_player_index = 0
		_focus_outline = Coop.make_outline()
		add_child(_focus_outline)
	if _any_autoshop():
		call_deferred("_auto_shop")

# The co-op shop container (panel) for slot pi, or null. _get_coop_player_container
# is CoopShop-only, so invoke it dynamically to satisfy the BaseShop parser.
func _shop_panel(pi):
	if not has_method("_get_coop_player_container"):
		return null
	return call("_get_coop_player_container", pi)

# The shop enters with CoopService.listening_for_inputs = false, which makes the
# FocusEmulators swallow the human's mouse clicks. Hold it true (when a lone human
# is commanding bots) so buy / reroll / go and owned-gear clicks work by mouse.
func _process(_delta: float) -> void:
	Coop.keep_mouse_enabled()
	# Outline the TAB-focused player's shop panel. current_player_index (set by TAB,
	# CoopService._input) is the slot the human's mouse + keyboard drive; the base
	# FocusEmulators already process that slot, so no pin is needed here anymore.
	if _focus_outline != null:
		var pi = CoopService.current_player_index
		Coop.update_outline_panel(_focus_outline, _shop_panel(pi), pi)
	# Suppress the cross-player ban flicker at the source. The device-7 remap can
	# fire a non-focused player's ban button (banning their selected item; the
	# on_shop_item_banned guard then undoes it -- a visible blip). A disabled ban
	# button makes _on_BanButton_button_down early-return, so keep every non-focused
	# player's ban buttons disabled. The focused slot keeps the base's own handling
	# (so the human can still ban there); bots auto-ban via _apply_bans, which calls
	# the container directly and never touches these buttons.
	if Coop.only_p1_is_human():
		var cur = CoopService.current_player_index
		# On a TAB focus change, restore the newly-focused player's ban buttons (they
		# were held disabled while another slot was focused) via the base's own logic.
		if cur != _prev_ban_cur:
			_prev_ban_cur = cur
			var ccont = _get_shop_items_container(cur)
			if ccont != null:
				for cit in ccont._shop_items:
					if cit != null and is_instance_valid(cit) and cit.has_method("manage_ban_button_visibility"):
						cit.manage_ban_button_visibility()
		for p in range(RunData.get_player_count()):
			if p == cur:
				continue
			var cont = _get_shop_items_container(p)
			if cont == null:
				continue
			for it in cont._shop_items:
				if it != null and is_instance_valid(it) and ("_ban_button" in it) and it._ban_button != null:
					it._ban_button.disabled = true

# The shop's buy / reroll / go buttons are plain Buttons that do NOT receive the
# GUI click in co-op even with listening_for_inputs held true. Route the mouse to
# the item / button under the cursor directly (same hit-test as the level-up
# screen): motion drives hover (item popup + highlight), a left-click buys / rerolls
# / goes. Only for the lone human (slot 0); bots shop via _auto_shop_player.
var _shop_hover_item = null
func _input(event: InputEvent) -> void:
	# TAB cycles the active player. Intercept it BEFORE the base _input (the shop's
	# carousel / focus navigation consumes TAB before the CoopService global handler).
	if Coop.only_p1_is_human() and event is InputEventKey and event.pressed \
			and not event.echo and event.scancode == KEY_TAB:
		var before = CoopService.current_player_index
		Coop.cycle_focus()
		if CoopService.current_player_index != before:
			get_tree().set_input_as_handled()
		return
	# Coop-ban scoping. The base _input loop drives the ban on EVERY player whose
	# is_player_ui_coop_ban_pressed is true, and the device-7 remap makes that true
	# for all players from one key -- so a ban press starts the ban on every focused
	# item at once (every open ban dialog fires). Handle the ban ONLY for the TAB-
	# focused player and consume it, so the base loop never bans the others.
	if Coop.only_p1_is_human():
		var bpi = CoopService.current_player_index
		if bpi >= 0 and bpi < RunData.get_player_count():
			if Utils.is_player_ui_coop_ban_pressed(event, bpi):
				_shop_ban_press(bpi)
				get_tree().set_input_as_handled()
				return
			if Utils.is_player_ui_coop_ban_released(event, bpi):
				_shop_ban_release(bpi)
				get_tree().set_input_as_handled()
				return
	._input(event)
	if not Coop.only_p1_is_human():
		return
	# Act on the TAB-focused player's shop region (their items/buttons are hit-tested
	# under the cursor). Defaults to slot 0 (the human) until TAB cycles.
	var pi = CoopService.current_player_index
	if pi < 0 or pi >= RunData.get_player_count():
		pi = 0
	# When the owned-gear actions popup is OPEN (its cancel button is showing --
	# buttons_enabled is always true in the scene, so gate on real visibility),
	# its combine / discard / cancel buttons take the mouse.
	var popup = _get_item_popup(pi)
	if popup != null and popup._cancel_button != null and popup._cancel_button.is_visible_in_tree():
		_handle_shop_popup(popup, event)
		return
	if pi < _player_pressed_go_button.size() and _player_pressed_go_button[pi]:
		return   # this slot already pressed GO -- done shopping
	if event is InputEventMouseMotion:
		_update_shop_hover(pi)
		return
	# Lock ('e' / ui_select) the item under the cursor -- the base uses the
	# device-specific ui_select_<device> action, which does not fire for the
	# remapped keyboard slot, so handle the raw action here.
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("ui_select"):
		_shop_lock_hovered(pi)
		return
	# Space / ui_accept opens the actions popup on the hovered OWNED weapon/item --
	# the device-specific ui_accept never fires for the remapped keyboard slot, so
	# press the hovered gear element ourselves (its press emits element_pressed,
	# which the popup manager routes to the actions handler).
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("ui_accept"):
		if _shop_hover_item != null and is_instance_valid(_shop_hover_item) and _shop_hover_item is InventoryElement:
			_shop_hover_item._on_InventoryElement_pressed()
			get_tree().set_input_as_handled()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return
	var mouse = get_global_mouse_position()
	# Tab arrows: switch the carousel between the shop and the character stats.
	var car = _shop_carousel(pi)
	if car != null:
		if _shop_hit(car.arrow_left, mouse):
			car.index = car.index - 1
			get_tree().set_input_as_handled()
			return
		if _shop_hit(car.arrow_right, mouse):
			car.index = car.index + 1
			get_tree().set_input_as_handled()
			return
	# Buy the shop item under the cursor.
	var over = _shop_item_at(pi, mouse)
	if over != null:
		_get_shop_items_container(pi).on_shop_item_buy_button_pressed(over)
		get_tree().set_input_as_handled()
		return
	# Reroll / Go.
	if _shop_hit(_get_reroll_button(pi), mouse):
		_on_RerollButton_pressed(pi)
		get_tree().set_input_as_handled()
		return
	if _shop_hit(_get_go_button(pi), mouse):
		_on_GoButton_pressed(pi)
		get_tree().set_input_as_handled()

# Toggle the lock on the shop item under the cursor (or the focused one).
func _shop_lock_hovered(pi) -> void:
	var target = _shop_item_at(pi, get_global_mouse_position())
	if target == null and pi < _focused_shop_item.size():
		target = _focused_shop_item[pi]
	if target == null or not is_instance_valid(target) or target.item_data == null:
		return
	if not target.item_data.is_lockable or RunData.get_player_effect_bool(Keys.disable_item_locking_hash, pi):
		return
	target.change_lock_status(not target.locked)
	get_tree().set_input_as_handled()

# Drive the ban press / release on ONLY player pi's focused shop item, mirroring
# the base _input loop's conditions -- so the human's single ban key bans just the
# TAB-focused player, never every player's focused item at once.
func _shop_ban_target(pi):
	if pi < 0 or pi >= _focused_shop_item.size():
		return null
	var item = _focused_shop_item[pi]
	if item == null or not is_instance_valid(item) or item.item_data == null or item.item_data is WeaponData:
		return null
	var pdata = RunData.players_data[pi]
	if pdata.remaining_ban_token <= 0 or pdata.banned_items.has(item.item_data.my_id_hash):
		return null
	return item

func _shop_ban_press(pi) -> void:
	if not ChallengeService.is_challenge_completed(ChallengeService.chal_banned_items_hash) \
			or not RunData.is_ban_active_in_current_run():
		return
	# Cancel any ban HOLD still filling on another player before starting this one.
	# The device-7 remap lets a single key start a hold on any focused item; if one
	# was left open on a different player it would complete on its own (a second
	# ban). Clearing ban_button_presed stops that fill loop WITHOUT banning.
	for other in range(RunData.get_player_count()):
		if other != pi and other < _focused_shop_item.size():
			var oitem = _focused_shop_item[other]
			if oitem != null and is_instance_valid(oitem) and ("ban_button_presed" in oitem) and oitem.ban_button_presed:
				oitem.ban_button_presed = false
	var item = _shop_ban_target(pi)
	if item != null:
		item._on_BanButton_button_down()

func _shop_ban_release(pi) -> void:
	var item = _shop_ban_target(pi)
	if item != null:
		item._release_BanButton()

# DIAGNOSTIC: fires for every ban regardless of path -- if one ban action logs
# multiple players, the multi-ban is happening (and via what index).
func on_shop_item_banned(shop_item, player_index) -> void:
	# Ban-scope guard (catch-all). The device-7 remap lets one ban key reach every
	# player's focused item, so a single ban can land on a slot other than the TAB-
	# focused one. Every ban -- whatever triggered it -- funnels through here, so if
	# it hit a NON-focused player (and it isn't a bot auto-banning its own shop),
	# reverse it: restore the token, drop it from the banned list, re-activate the
	# item, and DON'T remove it from the offering.
	if Coop.only_p1_is_human() and not CoopService.auto_banning \
			and player_index != CoopService.current_player_index:
		var pdata = RunData.players_data[player_index]
		pdata.banned_items.erase(shop_item.item_data.my_id_hash)
		pdata.remaining_ban_token += 1
		if shop_item.has_method("activate"):
			shop_item.activate()
		return
	.on_shop_item_banned(shop_item, player_index)

# The shop item under the cursor for slot pi, or null.
func _shop_item_at(pi, mouse):
	var container = _get_shop_items_container(pi)
	if container == null:
		return null
	for item in container._shop_items:
		if item != null and is_instance_valid(item) and item.active \
				and item.is_visible_in_tree() and item.get_global_rect().has_point(mouse):
			return item
	return null

# Move the keyboard selection to whatever the cursor is over as it moves --
# shop item, reroll/go button, or an owned weapon/item -- so the highlight and
# popup follow the mouse like an up/down nav (and lock/ban act on the hovered
# shop item). Focusing the control drives the same focus_entered chain the
# FocusEmulator uses.
func _update_shop_hover(pi) -> void:
	var target = _shop_hover_target(pi, get_global_mouse_position())
	if target == null or target == _shop_hover_item:
		return
	_shop_hover_item = target
	Utils.focus_player_control(target, pi)

# The carousel (shop <-> stats tabs) for slot pi, or null.
func _shop_carousel(pi):
	# _get_coop_player_container is CoopShop-only (not declared on BaseShop), so
	# invoke it dynamically to satisfy the parser.
	if not has_method("_get_coop_player_container"):
		return null
	var c = call("_get_coop_player_container", pi)
	return c.carousel if (c != null and ("carousel" in c)) else null

# The focusable control under the cursor for slot pi (its focus target), or null.
func _shop_hover_target(pi, mouse):
	var car = _shop_carousel(pi)
	if car != null:
		if _shop_hit(car.arrow_left, mouse):
			return car.arrow_left
		if _shop_hit(car.arrow_right, mouse):
			return car.arrow_right
	var items = _get_shop_items_container(pi)
	if items != null:
		for item in items._shop_items:
			if item != null and is_instance_valid(item) and item.active \
					and item.is_visible_in_tree() and item.get_global_rect().has_point(mouse):
				return item._button
	if _shop_hit(_get_reroll_button(pi), mouse):
		return _get_reroll_button(pi)
	if _shop_hit(_get_go_button(pi), mouse):
		return _get_go_button(pi)
	var gear = _get_gear_container(pi)
	if gear != null:
		for src in [gear.weapons_container, gear.items_container]:
			# The elements live under the InventoryContainer's inner Inventory
			# (_elements), not as its direct children.
			if src == null or not ("_elements" in src) or src._elements == null:
				continue
			for e in src._elements.get_children():
				if e is Control and e.is_visible_in_tree() and e.get_global_rect().has_point(mouse):
					return e
	return null

func _shop_hit(btn, mouse) -> bool:
	return btn != null and btn.is_visible_in_tree() and not btn.disabled and btn.get_global_rect().has_point(mouse)

# Mouse hover + click for the owned-gear actions popup (combine / discard / cancel).
func _handle_shop_popup(popup, event) -> void:
	var mouse = get_global_mouse_position()
	var buttons = [popup._combine_button, popup._discard_button, popup._cancel_button]
	if event is InputEventMouseMotion:
		for btn in buttons:
			if _shop_hit(btn, mouse):
				if btn != _shop_hover_item:
					_shop_hover_item = btn
					Utils.focus_player_control(btn, 0)
				break
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return
	if _shop_hit(popup._combine_button, mouse):
		popup.emit_signal("item_combine_button_pressed", popup._item_data)
		get_tree().set_input_as_handled()
	elif _shop_hit(popup._discard_button, mouse):
		popup.emit_signal("item_discard_button_pressed", popup._item_data)
		get_tree().set_input_as_handled()
	elif _shop_hit(popup._cancel_button, mouse):
		popup.emit_signal("item_cancel_button_pressed", popup._item_data)
		get_tree().set_input_as_handled()

# Should the bot auto-shop for this player slot? Mirrors the combat AI's dispatch
# (player_movement_behavior.gd): the global enable_autobattler toggle makes EVERY
# slot a bot (pure AutoBattler / WaveLab), while CoopService.is_bot_by_index[pi]
# flags an individual co-op slot added with F1. Then each bot slot's per-bot
# autoshop toggle (CoopService.autoshop_by_index[pi], default on) gates its shop +
# level-ups, so the shop layer can be turned off per bot, independently of combat.
func _should_autoshop(pi) -> bool:
	var opts = get_node_or_null("/root/AutobattlerOptions")
	if opts == null:
		return false
	# A co-op bot slot (F1-added) uses its OWN per-slot AUTO-SHOP toggle, checked
	# FIRST -- independent of the global AutoBattler switch, which may be on for the
	# human's own AI assist. Mirrors the combat gate (player_movement_behavior: AI
	# runs when enable_autobattler OR is_bot_by_index[pi]); checking the global flag
	# first here instead would ignore the per-bot toggles in co-op.
	var coop = get_node_or_null("/root/CoopService")
	if coop != null and pi < coop.is_bot_by_index.size() and coop.is_bot_by_index[pi]:
		return pi < coop.autoshop_by_index.size() and coop.autoshop_by_index[pi]
	# Otherwise pure-AutoBattler / WaveLab (every slot a bot): the global
	# enable_autoshop flag decides. Default OFF; WaveLab sets it true explicitly.
	if opts.enable_autobattler:
		return opts.enable_autoshop
	return false

func _any_autoshop() -> bool:
	for pi in range(RunData.get_player_count()):
		if _should_autoshop(pi):
			return true
	return false

# One shop scene serves all co-op players (per-player containers). Drive each
# bot-controlled slot's shop in turn, then leave human slots to shop manually --
# the wave only starts once every player (bots via _on_GoButton_pressed below,
# humans by hand) has pressed GO.
func _auto_shop() -> void:
	yield(get_tree().create_timer(SETUP_WAIT), "timeout")
	for pi in range(RunData.get_player_count()):
		if _should_autoshop(pi):
			yield(_auto_shop_player(pi), "completed")

# Auto-shop a single player: score the offering, buy / reroll / lock-and-save, GO.
func _auto_shop_player(pi) -> void:
	var character = RunData.get_player_character(pi)
	var plan = ShopAdvisor.get_plan(character.my_id if character != null else "")
	var gold_in = RunData.get_player_gold(pi)
	var rerolls = 0
	var buys = 0
	var bought = []
	# Permanent per-character hold: Saver gains +1% damage per 25 materials KEPT,
	# a SOFT bonus that must not starve the build (the guide funds survival first
	# and keeps the rest). So the hold ramps in: nothing before wave 5, then a
	# modest slice of the bank rising with the waves, capped by the plan's floor.
	# Default 0 = the usual spend-everything economy.
	var gold_floor = 0
	if int(plan.get("gold_floor", 0)) > 0:
		var ramp = clamp((RunData.current_wave - 4) * 0.05, 0.0, 0.35)
		gold_floor = int(min(float(plan["gold_floor"]), ramp * gold_in))
	var save_floor = gold_floor   # gold reserved: floor + any locked weapon's price
	var saved_note = ""
	var tried = {}   # ShopItem instance_id -> true, so a failed buy is not retried
	# Proactive bans: spend the run's ban tokens to permanently remove items this
	# character never wants (e.g. medical guns on a glass cannon) -- they leave BOTH
	# this shop and all future ones (added to banned_items). Done once up front so the
	# buy loop and every later reroll are already clean.
	_apply_bans(pi, plan)
	var actions = 0
	while actions < MAX_ACTIONS:
		actions += 1
		var gold = RunData.get_player_gold(pi)
		var container = _get_shop_items_container(pi)
		var nodes = container._shop_items
		# Pick the best affordable, buyable, not-yet-tried node -- but never dip
		# below save_floor (the gold held for a weapon we locked to buy later).
		# Locked nodes ARE considered here: a weapon we locked (this wave or a past
		# one) should be bought once affordable. A locked buy is exempt from
		# save_floor -- it IS the thing we were saving for.
		var best_node = null
		var best_score = plan["min_buy"]
		for node in nodes:
			if node == null or not node.active:
				continue
			if tried.has(node.get_instance_id()):
				continue
			if node.value > gold:
				continue
			if not node.locked and gold - int(node.value) < save_floor:
				continue
			var sc = ShopAdvisor.score_shop_entry([node.item_data, node.wave_value], plan, pi)
			if node.locked:
				sc += 1000.0   # buy what we committed to first
			if sc > best_score:
				best_score = sc
				best_node = node
		if best_node != null:
			tried[best_node.get_instance_id()] = true
			if best_node.locked:
				best_node.change_lock_status(false)   # clear the lock registration before buying
				save_floor = gold_floor                # target acquired -> back to the plan's floor
			bought.push_back("%s@%d(%.0f)" % [best_node.item_data.my_id, int(best_node.value), best_score])
			buys += 1
			container.on_shop_item_buy_button_pressed(best_node)
			yield(get_tree().create_timer(BUY_WAIT), "timeout")
			continue
		# Nothing affordable to buy. If a strong weapon is on offer that we cannot
		# afford yet, LOCK it and save for it (locked items survive rerolls and
		# carry to the next wave's shop), then stop -- do not reroll it away or
		# spend the saved gold.
		if save_floor == gold_floor:
			var target = _weapon_to_save_for(nodes, gold, plan, pi)
			if target != null:
				if not target.locked:
					target.change_lock_status(true)
				save_floor = gold_floor + int(target.value)
				saved_note = " lock=%s@%d" % [target.item_data.my_id, int(target.value)]
				continue   # re-loop: keep shopping with the rest of the gold
		# Keep shopping even while saving: reroll if free, or affordable while
		# still preserving save_floor (the gold held for the locked weapon).
		var price = _reroll_price[pi]
		var free = price <= 0 or _free_rerolls[pi] > 0 or _has_bonus_free_reroll[pi]
		var keep = plan["reroll_keep"]
		if save_floor > keep:
			keep = save_floor
		var can_pay = gold - price >= keep and rerolls < plan["max_rerolls"]
		# Weaponless / single-weapon characters (Bull, Beast Master, One-Armed) can
		# never spend gold on weapons, so once the shop's items thin out they bank a
		# huge surplus (300-450g = wasted damage/survival). With spend_surplus set,
		# keep rerolling past max_rerolls while a big surplus remains, to surface more
		# items/pets to buy. Bounded by SURPLUS_KEEP and a hard reroll cap.
		var surplus_spend = plan.get("spend_surplus", false) \
			and gold - price >= SURPLUS_KEEP and rerolls < SURPLUS_MAX_REROLLS
		# Reroll-to-find: a character whose survival hinges on a specific weapon
		# (Pacifist's taser STUN -- its only crowd control at -100% damage) can't
		# rely on whatever the RNG offers. While no preferred weapon is on the board
		# and a weapon slot is still open, keep rerolling (down to HUNT_KEEP) to
		# surface one. No-op for every plan without prefer_weapons.
		var hunting = not plan.get("prefer_weapons", []).empty() \
			and RunData.get_player_weapons(pi).size() < int(plan.get("max_weapons", 6)) \
			and not _offering_has_preferred(nodes, plan) \
			and gold - price >= HUNT_KEEP and rerolls < HUNT_MAX_REROLLS
		if _reroll_price.size() > pi and (free or can_pay or surplus_spend or hunting):
			rerolls += 1
			tried.clear()   # a reroll replaces the offering
			_on_RerollButton_pressed(pi)
			yield(get_tree().create_timer(REROLL_WAIT), "timeout")
			continue
		break
	print("BOTLOG SHOP player=%d wave=%d gold_in=%d gold_out=%d buys=%d rerolls=%d bought=%s%s" % [
		pi, RunData.current_wave, gold_in, RunData.get_player_gold(pi), buys, rerolls, str(bought), saved_note])
	yield(get_tree().create_timer(GO_WAIT), "timeout")
	if _should_autoshop(pi):
		_on_GoButton_pressed(pi)

# The weapon on offer worth saving for: a strong weapon (tier 2+ / combine) we
# cannot afford this wave but could next wave. Already-locked weapons always
# qualify (we committed to them last wave and must keep reserving), and are
# exempt from the reach cap. Returns the ShopItem node, or null.
# Is any offered weapon one of the plan's prefer_weapons (matched by my_id
# substring)? Used by reroll-to-find to stop rerolling once a taser is on the
# board (the buy loop / lock-and-save then handles acquiring it).
func _offering_has_preferred(nodes, plan) -> bool:
	var prefs = plan.get("prefer_weapons", [])
	if prefs.empty():
		return false
	for node in nodes:
		if node == null or not node.active or not (node.item_data is WeaponData):
			continue
		for pref in prefs:
			if pref in node.item_data.my_id:
				return true
	return false

func _weapon_to_save_for(nodes, gold, plan, pi):
	var best = null
	var best_sc = LOCK_MIN_SCORE
	for node in nodes:
		if node == null or not node.active:
			continue
		if not (node.item_data is WeaponData):
			continue
		if node.value <= gold:
			continue   # affordable now -> the buy loop handles it
		if not node.locked and node.value > gold + LOCK_REACH:
			continue   # a NEW lock must be reachable next wave; a kept one is not dropped
		if not node.locked and not _on_plan_weapon(node.item_data, plan, pi):
			continue   # only save for on-plan weapons -- never hold gold for an off-plan combine
		var sc = ShopAdvisor.score_weapon(node.item_data, plan, pi)
		if node.locked:
			sc += 1000.0
		if sc > best_sc:
			best_sc = sc
			best = node
	return best

# Proactive item bans. If the run has ban mode active (settings ban_mode_toggled ->
# players_data.uses_ban) and tokens remain, ban every offered shop item whose my_id is
# in the plan's ban_items list. ban_item() adds it to banned_items, so ItemService also
# filters it out of every future shop and reroll this run -- a hard, permanent version
# of avoid_weapons that never fires unless the player opted into ban mode. Fixes e.g.
# the medical-gun overrank diluting glass-cannon boards, without a scoring hack.
func _apply_bans(pi, plan) -> void:
	var bans = plan.get("ban_items", [])
	if bans.empty() or not RunData.is_ban_active_in_current_run():
		return
	var container = _get_shop_items_container(pi)
	var pdata = RunData.players_data[pi]
	# The ban-scope guard (shop_items_container) blocks bans on any non-focused
	# player's shop; this bot is legitimately banning its OWN shop, so flag it.
	CoopService.auto_banning = true
	for node in Array(container._shop_items):   # copy: banning mutates the offering
		if node == null or not node.active:
			continue
		if pdata.remaining_ban_token <= 0:
			break
		if bans.has(node.item_data.my_id) and not pdata.banned_items.has(node.item_data.my_id_hash):
			container.on_shop_item_ban_button_pressed(node)
			print("BOTLOG BAN player=%d wave=%d item=%s tokens_left=%d" % [
				pi, RunData.current_wave, node.item_data.my_id, pdata.remaining_ban_token])
	CoopService.auto_banning = false

# Does the weapon match this plan's weapon class (set, or melee/ranged type)?
func _on_plan_weapon(wdata, plan, pi):
	var want_set = plan.get("weapon_set", "")
	if want_set != "":
		return ShopAdvisor.weapon_in_set(wdata, want_set)
	var wt = plan.get("weapon_type", "any")
	return wt == "any" or ShopAdvisor.weapon_type_str(wdata) == wt
