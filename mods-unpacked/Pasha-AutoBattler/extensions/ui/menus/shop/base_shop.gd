extends "res://ui/menus/shop/base_shop.gd"
# Automatic shopping for the AutoBattler bot. When the bot is enabled, on shop
# entry it scores the offering with ShopAdvisor and buys / rerolls / leaves the
# shop on its own. Gated by AutobattlerOptions.enable_autobattler so ordinary
# human runs are completely untouched.

const ShopAdvisor = preload("res://mods-unpacked/Pasha-AutoBattler/shopping/shop_advisor.gd")

const SETUP_WAIT = 0.35   # let _ready() finish populating the offering + UI
const BUY_WAIT = 0.09     # container enforces a 0.05s buy lockout; clear it
const REROLL_WAIT = 0.12
const GO_WAIT = 0.15
const MAX_ACTIONS = 250   # hard stop against any pathological loop (buys + rerolls, incl. surplus-spend)
const LOCK_MIN_SCORE = 28.0  # only save for a weapon at least this good (tier 2+ on-plan, or a combine)
const LOCK_REACH = 70        # only save if its price is within ~one wave's income of current gold
const SURPLUS_KEEP = 120     # spend_surplus: keep rerolling while gold stays above this
const SURPLUS_MAX_REROLLS = 45  # spend_surplus: hard cap on total rerolls per shop

func _ready() -> void:
	._ready()
	if _any_autoshop():
		call_deferred("_auto_shop")

# Should the bot auto-shop for this player slot? Mirrors the combat AI's dispatch
# (player_movement_behavior.gd): the global enable_autobattler toggle makes EVERY
# slot a bot (pure AutoBattler / WaveLab), while CoopService.is_bot_by_index[pi]
# flags an individual co-op slot added with F1. Gated by enable_autoshop so the
# shop layer can be turned off independently of combat.
func _should_autoshop(pi) -> bool:
	var opts = get_node_or_null("/root/AutobattlerOptions")
	if opts == null or not opts.enable_autoshop:
		return false
	if opts.enable_autobattler:
		return true
	var coop = get_node_or_null("/root/CoopService")
	return coop != null and pi < coop.is_bot_by_index.size() and coop.is_bot_by_index[pi]

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
		if _reroll_price.size() > pi and (free or can_pay or surplus_spend):
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

# Does the weapon match this plan's weapon class (set, or melee/ranged type)?
func _on_plan_weapon(wdata, plan, pi):
	var want_set = plan.get("weapon_set", "")
	if want_set != "":
		return ShopAdvisor.weapon_in_set(wdata, want_set)
	var wt = plan.get("weapon_type", "any")
	return wt == "any" or ShopAdvisor.weapon_type_str(wdata) == wt
