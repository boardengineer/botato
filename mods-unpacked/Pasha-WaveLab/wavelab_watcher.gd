extends Node

# WaveLab watcher: when the game was launched with --wavelab=1, drives
# menu -> (auto-Continue) -> shop -> (auto-GO, RNG seed) -> wave, records
# damage, prints one WAVELAB RESULT line, and quits. Without the flag it
# does nothing at all.
#
# Args: --wavelab=1  --wavelab-seed=<int>  --wavelab-speed=<float>

const STATE_MENU = 0
const STATE_SHOP = 1
const STATE_WAVE = 2
const STATE_DONE = 3

var active = false
var rng_seed = 0
var speed = 1.0

var _state = STATE_MENU
var _delay = 0.0
var _hooked_player = null
var _dmg = 0.0
var _elapsed = 0.0
var _last_hp = 0
var _prev_time_left = 1e9


func _ready():
	var args = Utils.get_startup_arguments()
	active = args.has("wavelab")
	if not active:
		set_process(false)
		return
	if args.has("wavelab-seed"):
		rng_seed = int(args["wavelab-seed"])
	if args.has("wavelab-speed"):
		speed = float(args["wavelab-speed"])
	# Test runs must never write to save files (also keeps the injected
	# run_v3_0.json snapshot intact through the death wipe)
	DebugService.disable_saving = true
	print("WAVELAB ACTIVE seed=%d speed=%.1f" % [rng_seed, speed])


func _process(delta):
	if _state == STATE_DONE:
		return
	var scene = get_tree().current_scene
	if scene == null:
		return

	if _state == STATE_MENU and scene.name == "TitleScreen":
		# Let title_screen._ready()/main_menu.init() finish before pressing
		_delay += delta
		if _delay < 0.5:
			return
		var menu = scene.get_node_or_null("Menus/MainMenu")
		if menu == null:
			return
		var options = get_node_or_null("/root/AutobattlerOptions")
		if options != null:
			options.enable_autobattler = true
		if ProgressData.saved_run_state.get("has_run_state", false):
			# saved_run_state is the deserialized state itself (no
			# current_run_state wrapper — that's only the on-disk JSON shape)
			_state = STATE_SHOP
			_delay = 0.0
			print("WAVELAB CONTINUE wave=%d" % (int(ProgressData.saved_run_state.get("current_wave", -1)) + 1))
			menu.testActivity("wavelab")
		else:
			print("WAVELAB ERROR no-run-state")
			_quit()

	elif _state == STATE_SHOP and scene.name == "Shop":
		_delay += delta
		if _delay < 0.4:
			return
		# Seed both generators right before the wave scene loads, so every
		# spawn roll after this point comes from the seed
		if rng_seed != 0:
			Utils.set_rng_seed(rng_seed)
			seed(rng_seed)
		_state = STATE_WAVE
		_delay = 0.0
		# The AutoBattler focus emulator may have toggled Endless on the
		# final-wave shop before we get here — force it back off
		RunData.is_endless_run = false
		scene._on_GoButton_pressed(0)

	elif _state == STATE_WAVE:
		if scene.name == "Main":
			if scene._players.empty():
				return
			var player = scene._players[0]
			if _hooked_player != player:
				_hooked_player = player
				player.connect("took_damage", self, "_on_player_took_damage")
				if speed > 1.0:
					Engine.time_scale = speed
				print("WAVELAB WAVE_START wave=%d char=%s hp=%d/%d" % [
					RunData.current_wave,
					RunData.get_player_character(0).my_id,
					int(player.current_stats.health), int(player.max_stats.health)])
			# max(): the timer resets in the final frames of a won wave — a
			# plain sample would report t=0 at the finish
			_elapsed = max(_elapsed, scene._wave_timer.wait_time - scene._wave_timer.time_left)
			_last_hp = int(player.current_stats.health)
			var tl = scene._wave_timer.time_left
			if player.dead:
				_finish("died")
			elif tl > _prev_time_left + 1.0 and _elapsed > 5.0 \
					and RunData.current_wave < RunData.nb_of_waves:
				# The timer RESET upward = the wave was just won. The scene can
				# stay "Main" indefinitely on end-of-wave screens waiting for
				# input the bot doesn't provide (observed: two survived runs
				# hung until killed by hand, losing their RESULT lines).
				# Enrage only voids timer logic on the FINAL wave.
				_finish("survived")
			_prev_time_left = tl
			# NOTE: no plain timer-expiry survive check — on the final wave the
			# timer ends while the boss fight continues (enrage). Below the
			# final wave the upward-reset check above is safe; scene-leave
			# detection below stays as the fallback.
		elif _hooked_player != null:
			var outcome = "survived"
			if is_instance_valid(_hooked_player) and _hooked_player.dead:
				outcome = "died"
			_finish(outcome)


func _on_player_took_damage(_unit, value, _kb, _is_crit, is_dodge, is_protected, _armor, _args, _hit_type, _one_shot):
	if is_dodge or is_protected:
		return
	_dmg += value


func _finish(outcome):
	_state = STATE_DONE
	var hp_end = 0
	if is_instance_valid(_hooked_player) and not _hooked_player.dead:
		hp_end = int(_hooked_player.current_stats.health)
	elif outcome == "survived":
		hp_end = _last_hp # player node freed by the run-won scene change
	print("WAVELAB RESULT wave=%d outcome=%s dmg=%d hp_end=%d t=%d" % [
		RunData.current_wave, outcome, int(_dmg), hp_end, int(_elapsed)])
	_quit()


func _quit():
	_state = STATE_DONE
	Engine.time_scale = 1.0
	var timer = get_tree().create_timer(0.5)
	timer.connect("timeout", self, "_do_quit")


func _do_quit():
	get_tree().quit()
