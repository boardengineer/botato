extends "res://singletons/progress_data.gd"
# Persist the bot-coop setup (which slots are bots + their autoshop toggles)
# alongside every run save, so a resumed run can restore it. See
# CoopService.persist_run_coop_state and the RunData.resume_from_state extension.

func save_run_state(shop_items := [], reroll_count := [], paid_reroll_count := [], initial_free_rerolls := [], free_rerolls := [], item_steals := []) -> void:
	.save_run_state(shop_items, reroll_count, paid_reroll_count, initial_free_rerolls, free_rerolls, item_steals)
	var coop = get_node_or_null("/root/CoopService")
	if coop != null and coop.has_method("persist_run_coop_state"):
		coop.persist_run_coop_state()
