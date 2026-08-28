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
const MAX_ACTIONS = 150   # hard stop against any pathological loop (buys + up to ~15 rerolls)

func _ready() -> void:
	._ready()
	if _ab_enabled():
		call_deferred("_auto_shop")

func _ab_enabled() -> bool:
	var opts = get_node_or_null("/root/AutobattlerOptions")
	return opts != null and opts.enable_autobattler and opts.enable_autoshop

func _auto_shop() -> void:
	var pi = 0
	yield(get_tree().create_timer(SETUP_WAIT), "timeout")
	var character = RunData.get_player_character(pi)
	var plan = ShopAdvisor.get_plan(character.my_id if character != null else "")
	var gold_in = RunData.get_player_gold(pi)
	var rerolls = 0
	var buys = 0
	var bought = []
	var tried = {}   # ShopItem instance_id -> true, so a failed buy is not retried
	var actions = 0
	while actions < MAX_ACTIONS:
		actions += 1
		var gold = RunData.get_player_gold(pi)
		var container = _get_shop_items_container(pi)
		var nodes = container._shop_items
		# Pick the best affordable, buyable, not-yet-tried node.
		var best_node = null
		var best_score = plan["min_buy"]
		for node in nodes:
			if node == null or not node.active or node.locked:
				continue
			if tried.has(node.get_instance_id()):
				continue
			if node.value > gold:
				continue
			var sc = ShopAdvisor.score_shop_entry([node.item_data, node.wave_value], plan, pi)
			if sc > best_score:
				best_score = sc
				best_node = node
		if best_node != null:
			tried[best_node.get_instance_id()] = true
			bought.push_back("%s@%d(%.0f)" % [best_node.item_data.my_id, int(best_node.value), best_score])
			buys += 1
			container.on_shop_item_buy_button_pressed(best_node)
			yield(get_tree().create_timer(BUY_WAIT), "timeout")
			continue
		# Nothing worth buying. Reroll if it is free, or affordable within budget.
		var price = _reroll_price[pi]
		var free = price <= 0 or _free_rerolls[pi] > 0 or _has_bonus_free_reroll[pi]
		var can_pay = gold - price >= plan["reroll_keep"] and rerolls < plan["max_rerolls"]
		if _reroll_price.size() > pi and (free or can_pay):
			rerolls += 1
			tried.clear()   # a reroll replaces the offering
			_on_RerollButton_pressed(pi)
			yield(get_tree().create_timer(REROLL_WAIT), "timeout")
			continue
		break
	print("BOTLOG SHOP wave=%d gold_in=%d gold_out=%d buys=%d rerolls=%d bought=%s" % [
		RunData.current_wave, gold_in, RunData.get_player_gold(pi), buys, rerolls, str(bought)])
	yield(get_tree().create_timer(GO_WAIT), "timeout")
	if _ab_enabled():
		_on_GoButton_pressed(pi)
