extends Node

# RunLoader: load a public brotatotracker.com run at a chosen wave.
#
# brotatotracker.com is the companion site of the BrotatoRunTracker workshop
# mod. Every run it holds is queryable without a login:
#   GET /api/runs/{id}            the run (character, difficulty, zone, elite
#                                 and Nightmare-event schedule, mods, ...)
#   GET /api/runs/{id}/waves/{n}  the build AT wave n: level, gold, items with
#                                 counts/tiers/curses, weapons with tiers, the
#                                 level-up picks made that wave, every stat
# This mod fetches those, assembles the run through RunData -- the same calls
# the character/weapon/shop screens make, so the game computes every effect
# itself -- and continues into wave n's shop as if you had just cleared wave
# n-1 with that exact build. Use it from the title-screen panel, or launch
# the game with  --runloader=<run id>:<wave>  (add  --runloader-quit=1  to
# build, save, print a RUNLOADER line and quit -- for tooling).
#
# WHAT IS REPRODUCED EXACTLY
#   character, difficulty, zone, wave, level, xp, gold, every item (count,
#   tier, cursed with the recorded curse factor), every weapon (tier, slot
#   order), the level-up upgrades taken before the wave, the run's elite /
#   horde / fog-of-war / bullet-hell / boss schedule, and every stat_* value
#   the record holds (the per-level max-HP gain and harvesting growth are
#   applied; whatever still differs -- cursed rolls, curse from shop prices --
#   is applied as a plain stat delta so the sheet matches the record).
#
# LIMITS  (also shown in the panel; keep this list honest when changing code)
#   1. Not seed-exact. Spawns, drops, shop rolls and elite SPECIES are rolled
#      by your game; the record only says which waves are elite/horde waves.
#      You get the same build facing the same wave TYPE, not the same fight.
#   2. DLC content needs the DLC. Abyss runs (zone 1), Nightmare (difficulty 6)
#      and every Abyssal Terrors item/weapon/character require the DLC to be
#      installed and enabled; the loader refuses such runs otherwise.
#   3. Modded runs do not resolve. Ids from other mods are unknown here; they
#      are skipped and listed. The record's `moddedContent` flag is shown.
#   4. Game-version drift. Records carry the version they were played on;
#      items rebalanced or renamed since then load as the CURRENT version.
#   5. Your current saved run is replaced. Loading writes the built run as the
#      saved run (a copy of the previous run save is kept next to it as
#      runloader_previous_run.json); the shop then autosaves normally.
#   6. The shop you land in is fresh: the record does not carry the shop offer,
#      rerolls, locks or bans of that wave.
#   7. Endless waves (21+) and co-op runs are not supported; the record's
#      wave range is what the API serves (typically 1 .. waveReached).
#   8. Stats are matched to the record's snapshot, which the tracker takes at
#      a fixed moment of the wave; items bought and stats gained in the shop
#      after that moment belong to the NEXT wave's record.

const API = "https://brotatotracker.com/api/runs"
const LIMITS_SHORT = "Not seed-exact (spawns, drops, shop and elite species are rolled here). " \
	+ "DLC runs need the DLC. Modded ids are skipped. Replaces your saved run (backup kept)."
const ELITE_BASE_WAVE = 10          # RunData marks the 10-wave block whose schedule is set

const S_IDLE = 0
const S_RUN = 1
const S_WAVE = 2
const S_UPGRADES = 3

var _http: HTTPRequest
var _state = S_IDLE
var _run_id = 0
var _wave = 1
var _run = {}
var _wave_rec = {}
var _upgrades = {}                  # "upgrade_x_<tier+1>" -> count, picks BEFORE the wave
var _upgrade_wave = 1               # next wave record to fetch for the level-up picks
var _cli = ""                       # --runloader=<id>:<wave>
var _cli_quit = false               # --runloader-quit=1
var _cli_started = false
var _panel: Control = null
var _status: Label = null
var _id_edit: LineEdit = null
var _wave_spin: SpinBox = null
var _load_button: Button = null


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	var args = Utils.get_startup_arguments()
	if args.has("runloader"):
		_cli = str(args["runloader"])
	if args.has("runloader-quit"):
		_cli_quit = str(args["runloader-quit"]) != "0"
	_http = HTTPRequest.new()
	_http.name = "RunLoaderHTTP"
	_http.timeout = 30
	add_child(_http)
	var _e = _http.connect("request_completed", self, "_on_request_completed")


func _process(_delta: float) -> void:
	var scene = get_tree().current_scene
	if scene == null or scene.name != "TitleScreen":
		if _panel != null and not is_instance_valid(_panel):
			_panel = null
		return
	if _panel == null or not is_instance_valid(_panel):
		_attach_panel(scene)
	if _cli != "" and not _cli_started:
		_cli_started = true
		var parts = _cli.split(":")
		if parts.size() == 2:
			_id_edit.text = parts[0]
			_wave_spin.value = int(parts[1])
			_start(int(parts[0]), int(parts[1]))
		else:
			_set_status("--runloader expects <run id>:<wave>")


# -- Panel ------------------------------------------------------------------

func _attach_panel(scene: Node) -> void:
	_panel = PanelContainer.new()
	_panel.name = "RunLoaderPanel"
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.margin_left = 24
	_panel.margin_top = 24
	_panel.rect_min_size = Vector2(520, 0)
	var box = VBoxContainer.new()
	_panel.add_child(box)

	var title = Label.new()
	title.text = "brotatotracker.com run loader"
	box.add_child(title)

	var row = HBoxContainer.new()
	box.add_child(row)
	var id_label = Label.new()
	id_label.text = "run id"
	row.add_child(id_label)
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "e.g. 31194"
	_id_edit.rect_min_size = Vector2(120, 0)
	row.add_child(_id_edit)
	var wave_label = Label.new()
	wave_label.text = "  wave"
	row.add_child(wave_label)
	_wave_spin = SpinBox.new()
	_wave_spin.min_value = 1
	_wave_spin.max_value = 20
	_wave_spin.value = 1
	row.add_child(_wave_spin)
	_load_button = Button.new()
	_load_button.text = "  Load  "
	row.add_child(_load_button)
	var _e = _load_button.connect("pressed", self, "_on_load_pressed")

	_status = Label.new()
	_status.autowrap = true
	_status.text = "Loads the recorded build of that run at that wave and opens its shop."
	box.add_child(_status)

	var limits = Label.new()
	limits.autowrap = true
	limits.text = LIMITS_SHORT
	limits.modulate = Color(0.8, 0.8, 0.8)
	box.add_child(limits)

	scene.add_child(_panel)


func _set_status(text: String) -> void:
	print("RUNLOADER " + text)
	if _status != null and is_instance_valid(_status):
		_status.text = text


func _on_load_pressed() -> void:
	var id = int(_id_edit.text.strip_edges())
	if id <= 0:
		_set_status("enter a numeric run id (the number in brotatotracker.com/run/<id>)")
		return
	_start(id, int(_wave_spin.value))


# -- Fetch -----------------------------------------------------------------

func _start(run_id: int, wave: int) -> void:
	if _state != S_IDLE:
		return
	_run_id = run_id
	_wave = max(wave, 1)
	_run = {}
	_wave_rec = {}
	_upgrades = {}
	_upgrade_wave = 1
	if _load_button != null:
		_load_button.disabled = true
	_state = S_RUN
	_set_status("fetching run %d..." % _run_id)
	_request("%s/%d" % [API, _run_id])


func _request(url: String) -> void:
	var err = _http.request(url, ["Accept: application/json", "User-Agent: Brotato-RunLoader"])
	if err != OK:
		_fail("request failed to start (%d)" % err)


func _on_request_completed(result: int, code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("tracker request failed (result %d, http %d)" % [result, code])
		return
	var parsed = JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or not (parsed.result is Dictionary):
		_fail("tracker returned something that is not JSON")
		return
	var data = parsed.result
	match _state:
		S_RUN:
			_run = data
			var reached = int(_run.get("waveReached", 20))
			if _wave > reached:
				_fail("run %d only reached wave %d" % [_run_id, reached])
				return
			if bool(_run.get("moddedContent", false)):
				_set_status("note: this run used mods; unknown ids will be skipped")
			_state = S_WAVE
			_request("%s/%d/waves/%d" % [API, _run_id, _wave])
		S_WAVE:
			_wave_rec = data.get("wave", {})
			if _wave_rec.empty():
				_fail("no record for wave %d" % _wave)
				return
			_state = S_UPGRADES
			_next_upgrade_wave()
		S_UPGRADES:
			# The level-up picks listed on wave k are the ones made at the end
			# of wave k, so the build entering wave n carries waves 1..n-1.
			for u in data.get("wave", {}).get("levelUpStats", []):
				var key = "%s_%d" % [str(u.get("upgradeId", "")), int(u.get("tier", 0)) + 1]
				_upgrades[key] = int(_upgrades.get(key, 0)) + int(u.get("count", 0))
			_upgrade_wave += 1
			_next_upgrade_wave()


func _next_upgrade_wave() -> void:
	if _upgrade_wave < _wave:
		_set_status("fetching level-ups (wave %d of %d)..." % [_upgrade_wave, _wave - 1])
		_request("%s/%d/waves/%d" % [API, _run_id, _upgrade_wave])
	else:
		_state = S_IDLE
		_build_and_enter()


func _fail(why: String) -> void:
	_state = S_IDLE
	if _load_button != null:
		_load_button.disabled = false
	_set_status("failed: " + why)
	if _cli_quit:
		get_tree().quit()


# -- Build -----------------------------------------------------------------

func _build_and_enter() -> void:
	var character_id = str(_run.get("characterId", ""))
	var difficulty = int(_run.get("difficulty", 0))
	var zone = int(_run.get("currentZone", 0))
	if bool(_run.get("isCoop", false)) or int(_run.get("playerCount", 1)) > 1:
		_fail("co-op runs are not supported")
		return
	var needs_dlc = zone == 1 or difficulty > 5
	var has_dlc = ProgressData.is_dlc_available_and_active("abyssal_terrors")
	if needs_dlc and not has_dlc:
		_fail("this run needs the Abyssal Terrors DLC (zone %d, difficulty %d)" % [zone, difficulty])
		return
	var character = ItemService.get_element_safe(ItemService.characters, character_id)
	if character == null:
		_fail("unknown character %s (modded or missing DLC)" % character_id)
		return

	var missing = []
	RunData.reset()
	RunData.current_zone = zone
	RunData.current_difficulty = difficulty
	RunData.constant_projectile = 1
	RunData.enabled_dlcs = ProgressData.get_active_dlc_ids()
	ZoneService.current_zone = ZoneService.get_zone_data(zone).duplicate()
	RunData.nb_of_waves = ZoneService.current_zone.waves_data.size()
	RunData.reset_background()
	RunData.add_character(character, 0)

	# Weapons in slot order. Starting weapons are part of the record, so the
	# character's starting loadout is NOT added on top.
	var weapons = _wave_rec.get("weapons", [])
	weapons.sort_custom(self, "_by_slot")
	for w in weapons:
		var weapon = ItemService.get_element_safe(ItemService.weapons, str(w.get("weaponId", "")))
		if weapon == null:
			missing.push_back(str(w.get("weaponId", "")))
			continue
		var _w = RunData.add_weapon(weapon, 0)

	var dlc = ProgressData.get_dlc_data("abyssal_terrors") if has_dlc else null
	for entry in _wave_rec.get("items", []):
		var item_id = str(entry.get("itemId", ""))
		if item_id.begins_with("character_"):
			continue    # the character is its own item; added above
		var item = ItemService.get_element_safe(ItemService.items, item_id)
		if item == null:
			missing.push_back(item_id)
			continue
		for _i in int(entry.get("count", 1)):
			var inst = item
			if bool(entry.get("cursed", false)) and dlc != null:
				inst = dlc.curse_item(item, 0, true, float(entry.get("curseFactor", 0.0)))
			RunData.add_item(inst, 0)

	for key in _upgrades:
		var upgrade = ItemService.get_element_safe(ItemService.upgrades, key)
		if upgrade == null:
			missing.push_back(key)
			continue
		for _i in int(_upgrades[key]):
			RunData.add_item(upgrade, 0)

	var diff_data = ItemService.get_element(ItemService.difficulties, Keys.empty_hash, difficulty)
	if diff_data != null:
		for effect in diff_data.effects:
			effect.apply(0)

	var pdata = RunData.players_data[0]
	pdata.gold = int(_wave_rec.get("gold", 0))
	pdata.current_level = int(_wave_rec.get("level", 0))
	pdata.current_xp = float(_wave_rec.get("currentXp", 0.0))
	# Two permanent gains happen outside items: +1 max HP per level-up
	# (main.gd on level up) and harvesting growth at every wave end.
	if pdata.current_level > 0:
		RunData.add_stat(Keys.stat_max_hp_hash, pdata.current_level, 0)
	# Whatever still differs from the record (cursed rolls, curse from shop
	# prices, growth) is a plain additive stat: apply the delta.
	var mismatches = 0
	for s in _wave_rec.get("stats", []):
		var name = str(s.get("name", ""))
		if not name.begins_with("stat_"):
			continue
		var hsh = Keys.generate_hash(name)
		var delta = int(s.get("value", 0)) - int(Utils.get_stat(hsh, 0))
		if delta > 0:
			RunData.add_stat(hsh, delta, 0)
		elif delta < 0:
			RunData.remove_stat(hsh, -delta, 0)
		if delta != 0:
			mismatches += 1
	pdata.current_health = int(Utils.get_stat(Keys.stat_max_hp_hash, 0))

	# Schedules from the record. The record only says elite-or-horde per
	# wave, so the elite species is drawn like the game does (without
	# replacement from the zone's pool) -- limit 1.
	RunData.reset_elites_spawn()
	RunData.reset_events_nightmare()
	var pool = ItemService.get_elites_from_zone(zone).duplicate()
	var mods = _run.get("waveModifiers", [])
	for m in mods:
		var w = int(m.get("wave", 0))
		var t = str(m.get("type", ""))
		if t == "elite" or t == "horde":
			var type = EliteType.HORDE if t == "horde" else EliteType.ELITE
			var elite_id = Keys.empty_hash
			if type == EliteType.ELITE and pool.size() > 0:
				var elite = Utils.get_rand_element(pool)
				pool.erase(elite)
				elite_id = elite.my_id_hash
			RunData.elites_spawn.push_back([w, type, elite_id])
		elif t == "fog_of_war":
			RunData.events_fog_of_war.push_back(w)
			RunData.events_spawn.push_back([w, "fog_of_war"])
		elif t == "bullet_hell":
			RunData.events_bullet_hell.push_back(w)
			RunData.events_spawn.push_back([w, "bullet_hell"])
	RunData.check_elite_generation.append(ELITE_BASE_WAVE)
	RunData.check_nightmare_event_generation.push_back(ELITE_BASE_WAVE)
	RunData.init_bosses_spawn()

	# Saved as the post-shop state of the previous wave -- what Continue expects
	RunData.current_wave = _wave - 1
	_backup_run_save()
	ProgressData.save_run_state()

	var summary = "loaded %s run %d at wave %d: level %d, %d HP, %d gold, %d weapons, %d items" % [
		character.my_id.replace("character_", ""), _run_id, _wave, pdata.current_level,
		pdata.current_health, pdata.gold, pdata.weapons.size(), pdata.items.size()]
	if missing.size() > 0:
		summary += "; skipped unknown ids: " + str(missing)
	_set_status(summary)
	print("RUNLOADER BUILT run=%d wave=%d char=%s stat_deltas=%d missing=%d" % [
		_run_id, _wave, character.my_id, mismatches, missing.size()])
	if _cli_quit:
		get_tree().quit()
		return

	# Into the shop, the way the main menu's Continue does it
	ProgressData.start_activity()
	RunData.continue_current_run_in_shop()
	var _err = get_tree().change_scene("res://ui/menus/shop/shop.tscn")


func _by_slot(a, b) -> bool:
	return int(a.get("slot", 0)) < int(b.get("slot", 0))


# Limit 5: the built run replaces the saved run; keep the previous one.
func _backup_run_save() -> void:
	var dir = Directory.new()
	var src = ProgressData.SAVE_DIR + "/run_v3_0.json"
	if dir.file_exists(src):
		# Not "run_v3_0*.bak": the game's own backup rotation scans that pattern
		# and chokes on a name it did not number itself.
		var _e = dir.copy(src, ProgressData.SAVE_DIR + "/runloader_previous_run.json")
