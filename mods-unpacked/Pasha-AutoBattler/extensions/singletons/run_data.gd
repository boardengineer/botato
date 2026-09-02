extends "res://singletons/run_data.gd"
# Restore the bot-coop setup (is_bot_by_index + autoshop_by_index, and grow the
# connected-players list) when a saved run is resumed via Continue, so the extra
# slots come back as functioning bots. See CoopService.restore_run_coop_state and
# the ProgressData.save_run_state extension that writes the side-file.

func resume_from_state(state: Dictionary) -> void:
	.resume_from_state(state)
	var coop = get_node_or_null("/root/CoopService")
	if coop != null and coop.has_method("restore_run_coop_state"):
		coop.restore_run_coop_state()
