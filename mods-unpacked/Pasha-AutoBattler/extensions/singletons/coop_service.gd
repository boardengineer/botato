extends "res://singletons/coop_service.gd"

const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")

var current_player_index : int = 0
var main_player_device : int = -1
var main_player_index : int = -1
var is_bot_by_index : Array = [false, false, false, false]
# Per-bot auto-shop toggle (shopping + level-ups). Indexed by player_index, one
# entry per slot, default ON (each bot's AUTO-SHOP panel toggle can turn it off).
# Only consulted for bot slots; reset with the bot flags.
var autoshop_by_index : Array = [true, true, true, true]
# Set true while a bot auto-bans its OWN shop (base_shop._apply_bans) so the
# shop_items_container ban-scope guard lets those through -- otherwise the guard
# (which blocks bans on any non-focused player's shop) would reject them too.
var auto_banning : bool = false

func _input(event):
	if event is InputEventKey and event.pressed:
		if get_tree().current_scene.name == "CharacterSelection":
			if event.scancode == KEY_F1 and main_player_device != -1:
				if connected_players.size() < 4:
					current_player_index = connected_players.size()
					is_bot_by_index[current_player_index] = true
					_add_player(connected_players.size(), PlayerType.KEYBOARD_AND_MOUSE)
					# Adding a co-op player normally flips the game into gamepad
					# (mouse-hidden) mode. This is a human commanding bots, so keep
					# the cursor -- InputService._process re-asserts it every frame.
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif event.scancode == KEY_TAB and not event.echo:
			# In-run (arena / shop / level-up): a lone human commanding bots cycles
			# which player's panel is active with TAB, so the mouse and keyboard can
			# drive any of them. cycle_focus() no-ops unless it's a lone-human team.
			var before = current_player_index
			Coop.cycle_focus()
			if current_player_index != before:
				get_tree().set_input_as_handled()


func clear_coop_players() -> void:
	# The base clear empties connected_players (mode switch, leaving a run) but
	# leaves is_bot_by_index set, so a stale bot flag would leak into the next
	# run -- e.g. a fresh solo player 0 inheriting a previous bot's slot flag.
	# Reset the bot flags whenever the player list is cleared.
	.clear_coop_players()
	is_bot_by_index = [false, false, false, false]
	autoshop_by_index = [true, true, true, true]
	current_player_index = 0


func get_remapped_player_device(player_index:int) -> int:
	return 7
#	if is_bot_by_index[player_index]:
#		return main_player_device
#	return .get_remapped_player_device(player_index)


# --- Persist / restore the bot-coop setup across save & Continue --------------
# The base run save stores every player's run data but nothing about which slots
# are bots, so a resumed co-op run would spawn the extra characters uncontrolled.
# We mirror is_bot_by_index + autoshop_by_index to a side-file written at every
# run save (ProgressData.save_run_state extension) and re-apply it when the run is
# resumed (RunData.resume_from_state extension). Keyed by player_count so a
# differently-shaped run never inherits stale bot flags.
const COOP_STATE_PATH = "user://pasha-autobattler-coop.cfg"

func persist_run_coop_state() -> void:
	var any_bot = false
	for b in is_bot_by_index:
		if b:
			any_bot = true
	var cfg = ConfigFile.new()
	cfg.set_value("run", "has_bot_coop", any_bot)
	cfg.set_value("run", "is_bot_by_index", is_bot_by_index)
	cfg.set_value("run", "autoshop_by_index", autoshop_by_index)
	cfg.set_value("run", "player_count", RunData.get_player_count())
	var _e = cfg.save(COOP_STATE_PATH)


func restore_run_coop_state() -> void:
	if not RunData.is_coop_run:
		return
	var cfg = ConfigFile.new()
	if cfg.load(COOP_STATE_PATH) != OK:
		return
	if not cfg.get_value("run", "has_bot_coop", false):
		return
	var count = RunData.get_player_count()
	if int(cfg.get_value("run", "player_count", 0)) != count:
		return   # different run shape -> don't apply stale bot flags
	is_bot_by_index = cfg.get_value("run", "is_bot_by_index", [false, false, false, false])
	autoshop_by_index = cfg.get_value("run", "autoshop_by_index", [true, true, true, true])
	current_player_index = 0
	# Grow connected_players to N slots (append-only, so the human's own entry is
	# never clobbered) so the lone-human mouse / TAB features light up on the
	# resumed run, matching a fresh F1 setup: slot 0 human, the rest bots.
	while connected_players.size() < count:
		connected_players.push_back([connected_players.size(), PlayerType.KEYBOARD_AND_MOUSE])
	emit_signal("connected_players_updated", connected_players)
