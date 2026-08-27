extends Node

# RunLoader: browse and load public brotatotracker.com runs at a chosen wave.
#
# brotatotracker.com is the companion site of the BrotatoRunTracker workshop
# mod. Every run it holds is queryable without a login:
#   GET /api/runs?character=&difficulty=&zone=&outcome=&pageSize=&page=
#                                 the run list (newest first; those four
#                                 filters are honoured server-side, there is
#                                 no sort or search)
#   GET /api/runs/{id}            the run (character, difficulty, zone, elite
#                                 and Nightmare-event schedule, mods, ...)
#   GET /api/runs/{id}/waves/{n}  the build AT wave n: level, gold, items with
#                                 counts/tiers/curses, weapons with tiers, the
#                                 level-up picks made that wave, every stat
# This mod fetches those, assembles the run through RunData -- the same calls
# the character/weapon/shop screens make, so the game computes every effect
# itself -- and continues into wave n's shop as if you had just cleared wave
# n-1 with that exact build. Use the title-screen panel (filter, Search, pick
# a row, pick a wave, Load), or launch the game with
#   --runloader=<run id>:<wave>        load that run at that wave
#   --runloader-query=<character|any>:<difficulty|any>:<zone|any>:<outcome|any>
#                                      list page 1 of that filter (RUNLOADER
#                                      ROW / LIST lines)
#   --runloader-quit=1                 quit after the load or the list (tooling)
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
#   3. Modded runs do not resolve. Ids from other mods are unknown here. The
#      browser HIDES modded runs (the API cannot filter them, so they are
#      dropped client-side and counted); a modded id loaded by hand has its
#      unknown ids skipped and listed.
#   4. Game-version drift. Records carry the version they were played on;
#      items rebalanced or renamed since then load as the CURRENT version.
#   5. Your current saved run is replaced. Loading writes the built run as the
#      saved run (a copy of the previous run save is kept next to it as
#      runloader_previous_run.json); the shop then autosaves normally.
#   6. The shop you land in is fresh: the record does not carry the shop offer,
#      rerolls, locks or bans of that wave.
#   7. Retried and endless runs are listed. A retried wave was died on at least
#      once with that build, and its per-wave stats may mix attempts; endless
#      runs load only up to the zone's last wave (the wave picker caps there).
#      Co-op runs are not supported.
#   8. Stats are matched to the record's snapshot, which the tracker takes at
#      a fixed moment of the wave; items bought and stats gained in the shop
#      after that moment belong to the NEXT wave's record.

const API = "https://brotatotracker.com/api/runs"
const LIMITS_SHORT = "Not seed-exact (spawns, drops, shop and elite species are rolled here). " \
	+ "DLC runs need the DLC. Modded runs are hidden. Retried/endless runs are listed " \
	+ "(endless: waves up to the zone's last). Loading replaces your saved run (backup kept)."
const ELITE_BASE_WAVE = 10          # RunData marks the 10-wave block whose schedule is set
const PAGE_SIZE = 25
const LIST_ROWS = 10

const S_IDLE = 0
const S_RUN = 1
const S_WAVE = 2
const S_UPGRADES = 3
const S_LIST = 4
const S_PREVIEW = 5

var _http: HTTPRequest
var _state = S_IDLE
var _run_id = 0
var _wave = 1
var _run = {}
var _wave_rec = {}
var _upgrades = {}                  # "upgrade_x_<tier+1>" -> count, picks BEFORE the wave
var _upgrade_wave = 1               # next wave record to fetch for the level-up picks
var _cli = ""                       # --runloader=<id>:<wave>
var _cli_query = ""                 # --runloader-query=<char>:<diff>:<zone>:<outcome>
var _cli_quit = false               # --runloader-quit=1
var _cli_started = false

# browser
var _page = 1
var _total = 0
var _hidden_modded = 0
var _rows = []                      # the visible page's unmodded run records
var _preview_key = ""               # "<id>:<wave>" of _preview_rec
var _preview_rec = {}
var _preview_pending = false

# panel
var _panel: Control = null
var _status: Label = null
var _id_edit: LineEdit = null
var _wave_spin: SpinBox = null
var _load_button: Button = null
var _char_opt: OptionButton = null
var _diff_opt: OptionButton = null
var _zone_opt: OptionButton = null
var _outcome_opt: OptionButton = null
var _search_button: Button = null
var _list: ItemList = null
var _list_header: Label = null
var _page_label: Label = null
var _prev_button: Button = null
var _next_button: Button = null
var _preview_label: Label = null


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	var args = Utils.get_startup_arguments()
	if args.has("runloader"):
		_cli = str(args["runloader"])
	if args.has("runloader-query"):
		_cli_query = str(args["runloader-query"])
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
	if not _cli_started and (_cli != "" or _cli_query != ""):
		_cli_started = true
		if _cli_query != "":
			_apply_cli_query(_cli_query)
		elif _cli != "":
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
	_panel.rect_min_size = Vector2(760, 0)
	var box = VBoxContainer.new()
	_panel.add_child(box)

	var title = Label.new()
	title.text = "brotatotracker.com run browser"
	box.add_child(title)

	# Filter row
	var filters = HBoxContainer.new()
	box.add_child(filters)
	_char_opt = OptionButton.new()
	_char_opt.add_item("any character")
	_char_opt.set_item_metadata(0, "")
	var chars = []
	for c in ItemService.characters:
		chars.push_back([c.get_name_text(), c.my_id])
	chars.sort_custom(self, "_by_first")
	for c in chars:
		_char_opt.add_item(c[0])
		_char_opt.set_item_metadata(_char_opt.get_item_count() - 1, c[1])
	filters.add_child(_char_opt)
	_diff_opt = OptionButton.new()
	_diff_opt.add_item("any danger")
	_diff_opt.set_item_metadata(0, -1)
	for d in range(7):
		_diff_opt.add_item("Nightmare" if d == 6 else "Danger %d" % d)
		_diff_opt.set_item_metadata(d + 1, d)
	filters.add_child(_diff_opt)
	_zone_opt = OptionButton.new()
	_zone_opt.add_item("any zone")
	_zone_opt.set_item_metadata(0, -1)
	_zone_opt.add_item("Crash Zone")
	_zone_opt.set_item_metadata(1, 0)
	_zone_opt.add_item("Abyss")
	_zone_opt.set_item_metadata(2, 1)
	filters.add_child(_zone_opt)
	_outcome_opt = OptionButton.new()
	_outcome_opt.add_item("won")
	_outcome_opt.set_item_metadata(0, "Won")
	_outcome_opt.add_item("lost")
	_outcome_opt.set_item_metadata(1, "Lost")
	_outcome_opt.add_item("any outcome")
	_outcome_opt.set_item_metadata(2, "")
	filters.add_child(_outcome_opt)
	_search_button = Button.new()
	_search_button.text = "  Search  "
	filters.add_child(_search_button)
	var _e1 = _search_button.connect("pressed", self, "_on_search_pressed")

	# Results
	_list_header = Label.new()
	_list_header.text = "no search yet"
	box.add_child(_list_header)
	_list = ItemList.new()
	_list.rect_min_size = Vector2(0, LIST_ROWS * 22)
	_list.select_mode = ItemList.SELECT_SINGLE
	box.add_child(_list)
	var _e2 = _list.connect("item_selected", self, "_on_row_selected")
	var paging = HBoxContainer.new()
	box.add_child(paging)
	_prev_button = Button.new()
	_prev_button.text = " < "
	_prev_button.disabled = true
	paging.add_child(_prev_button)
	var _e3 = _prev_button.connect("pressed", self, "_on_prev_pressed")
	_page_label = Label.new()
	_page_label.text = ""
	paging.add_child(_page_label)
	_next_button = Button.new()
	_next_button.text = " > "
	_next_button.disabled = true
	paging.add_child(_next_button)
	var _e4 = _next_button.connect("pressed", self, "_on_next_pressed")

	# Load row
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
	var _e5 = _wave_spin.connect("value_changed", self, "_on_wave_changed")
	_load_button = Button.new()
	_load_button.text = "  Load  "
	row.add_child(_load_button)
	var _e6 = _load_button.connect("pressed", self, "_on_load_pressed")

	_preview_label = Label.new()
	_preview_label.autowrap = true
	_preview_label.text = ""
	box.add_child(_preview_label)

	_status = Label.new()
	_status.autowrap = true
	_status.text = "Pick filters and Search, or type a run id. Loading opens that wave's shop with the recorded build."
	box.add_child(_status)

	var limits = Label.new()
	limits.autowrap = true
	limits.text = LIMITS_SHORT
	limits.modulate = Color(0.8, 0.8, 0.8)
	box.add_child(limits)

	scene.add_child(_panel)


func _by_first(a, b) -> bool:
	return a[0] < b[0]


func _set_status(text: String) -> void:
	print("RUNLOADER " + text)
	if _status != null and is_instance_valid(_status):
		_status.text = text


func _set_busy(busy: bool) -> void:
	for b in [_load_button, _search_button, _prev_button, _next_button]:
		if b != null and is_instance_valid(b):
			b.disabled = busy
	if not busy:
		_update_paging()


# -- Browser ---------------------------------------------------------------

func _on_search_pressed() -> void:
	_search(1)


func _on_prev_pressed() -> void:
	if _page > 1:
		_search(_page - 1)


func _on_next_pressed() -> void:
	if _page < _page_count():
		_search(_page + 1)


func _page_count() -> int:
	return int(max(ceil(float(_total) / float(PAGE_SIZE)), 1))


func _update_paging() -> void:
	if _page_label == null or not is_instance_valid(_page_label):
		return
	_page_label.text = " page %d of %d " % [_page, _page_count()] if _total > 0 else ""
	_prev_button.disabled = _page <= 1
	_next_button.disabled = _page >= _page_count()


func _filter_query(page: int) -> String:
	var parts = ["pageSize=%d" % PAGE_SIZE, "page=%d" % page]
	var character = str(_char_opt.get_selected_metadata())
	if character != "":
		parts.push_back("character=" + character.percent_encode())
	var difficulty = int(_diff_opt.get_selected_metadata())
	if difficulty >= 0:
		parts.push_back("difficulty=%d" % difficulty)
	var zone = int(_zone_opt.get_selected_metadata())
	if zone >= 0:
		parts.push_back("zone=%d" % zone)
	var outcome = str(_outcome_opt.get_selected_metadata())
	if outcome != "":
		parts.push_back("outcome=" + outcome)
	return "&".join(parts)


func _search(page: int) -> void:
	if _state != S_IDLE:
		return
	_page = page
	_state = S_LIST
	_set_busy(true)
	_set_status("searching page %d..." % page)
	_request(API + "?" + _filter_query(page))


func _on_list_received(data: Dictionary) -> void:
	_total = int(data.get("total", 0))
	_rows = []
	_hidden_modded = 0
	_list.clear()
	for r in data.get("items", []):
		if bool(r.get("moddedContent", false)):
			_hidden_modded += 1     # limit 3: the API cannot filter these
			continue
		_rows.push_back(r)
		_list.add_item(_row_text(r))
	_list_header.text = "showing %d of %d run(s)%s" % [_rows.size(), _total,
			" (%d modded hidden on this page)" % _hidden_modded if _hidden_modded > 0 else ""]
	_set_status("%d run(s) match; select one, pick a wave, Load" % _total if _total > 0 else "no runs match")
	_update_paging()
	if _cli_query != "":
		for r in _rows:
			print("RUNLOADER ROW " + _row_text(r))
		print("RUNLOADER LIST total=%d shown=%d hidden_modded=%d page=%d" % [
			_total, _rows.size(), _hidden_modded, _page])
		if _cli_quit:
			get_tree().quit()


func _row_text(r: Dictionary) -> String:
	var flags = ""
	if int(r.get("retries", 0)) > 0:
		flags += "  retries %d" % int(r.get("retries", 0))
	if str(r.get("gameMode", "")) == "endless":
		flags += "  endless"
	return "#%d  %s  %s  w%d/%d  lvl %d  %d kills%s" % [
		int(r.get("id", 0)), str(r.get("playedAtUtc", "")).substr(0, 10),
		str(r.get("playerName", "?")), int(r.get("waveReached", 0)),
		int(r.get("nbOfWaves", 20)), int(r.get("level", 0)),
		int(r.get("totalEnemiesKilled", 0)), flags]


func _on_row_selected(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var r = _rows[index]
	_id_edit.text = str(int(r.get("id", 0)))
	# Endless runs go past the zone's last wave; only waves up to it load (limit 7)
	var last = min(int(r.get("waveReached", 1)), int(r.get("nbOfWaves", 20)))
	_wave_spin.max_value = max(last, 1)
	_wave_spin.value = max(last, 1)
	_request_preview()


func _on_wave_changed(_value: float) -> void:
	_request_preview()


func _request_preview() -> void:
	var id = int(_id_edit.text.strip_edges())
	if id <= 0:
		return
	if _state != S_IDLE:
		_preview_pending = true
		return
	_preview_pending = false
	_preview_key = "%d:%d" % [id, int(_wave_spin.value)]
	_state = S_PREVIEW
	_preview_label.text = "fetching wave %d of run %d..." % [int(_wave_spin.value), id]
	_request("%s/%d/waves/%d" % [API, id, int(_wave_spin.value)])


func _on_preview_received(data: Dictionary) -> void:
	var rec = data.get("wave", {})
	if rec.empty():
		_preview_label.text = "no record for that wave"
		_preview_rec = {}
		return
	_preview_rec = rec
	var weapons = []
	for w in rec.get("weapons", []):
		weapons.push_back(str(w.get("weaponId", "")).replace("weapon_", ""))
	var items = 0
	for it in rec.get("items", []):
		if not str(it.get("itemId", "")).begins_with("character_"):
			items += int(it.get("count", 1))
	_preview_label.text = "%s wave %d: %d HP, level %d, %d gold, weapons: %s, %d items" % [
		str(rec.get("characterId", "")).replace("character_", ""), int(rec.get("waveNumber", 0)),
		int(rec.get("maxHp", 0)), int(rec.get("level", 0)), int(rec.get("gold", 0)),
		" ".join(weapons), items]


func _apply_cli_query(spec: String) -> void:
	var parts = spec.split(":")
	if parts.size() != 4:
		_set_status("--runloader-query expects <character|any>:<difficulty|any>:<zone|any>:<outcome|any>")
		if _cli_quit:
			get_tree().quit()
		return
	_select_metadata(_char_opt, parts[0] if parts[0] != "any" else "")
	_select_metadata(_diff_opt, int(parts[1]) if parts[1] != "any" else -1)
	_select_metadata(_zone_opt, int(parts[2]) if parts[2] != "any" else -1)
	_select_metadata(_outcome_opt, parts[3] if parts[3] != "any" else "")
	_search(1)


func _select_metadata(opt: OptionButton, value) -> void:
	for i in range(opt.get_item_count()):
		if opt.get_item_metadata(i) == value:
			opt.select(i)
			return


# -- Load ------------------------------------------------------------------

func _on_load_pressed() -> void:
	var id = int(_id_edit.text.strip_edges())
	if id <= 0:
		_set_status("enter a numeric run id (the number in brotatotracker.com/run/<id>)")
		return
	_start(id, int(_wave_spin.value))


func _start(run_id: int, wave: int) -> void:
	if _state == S_PREVIEW or _state == S_LIST:
		# A preview (or a page) in flight must not swallow the Load: drop it.
		_http.cancel_request()
		_preview_pending = false
		_state = S_IDLE
	if _state != S_IDLE:
		return
	_run_id = run_id
	_wave = max(wave, 1)
	_run = {}
	_wave_rec = {}
	_upgrades = {}
	_upgrade_wave = 1
	_set_busy(true)
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
		S_LIST:
			_state = S_IDLE
			_set_busy(false)
			_on_list_received(data)
			if _preview_pending:
				_request_preview()
		S_PREVIEW:
			_state = S_IDLE
			_on_preview_received(data)
			if _preview_pending:
				_request_preview()
		S_RUN:
			_run = data
			var reached = int(_run.get("waveReached", 20))
			if _wave > reached:
				_fail("run %d only reached wave %d" % [_run_id, reached])
				return
			if bool(_run.get("moddedContent", false)):
				_set_status("note: this run used mods; unknown ids will be skipped")
			if _preview_key == "%d:%d" % [_run_id, _wave] and not _preview_rec.empty():
				_wave_rec = _preview_rec       # the preview already fetched this wave
				_state = S_UPGRADES
				_next_upgrade_wave()
			else:
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
	var was = _state
	_state = S_IDLE
	_set_busy(false)
	if was == S_PREVIEW:
		_preview_label.text = "preview failed: " + why
		return
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
	if _wave > RunData.nb_of_waves:
		_fail("wave %d is past the zone's last wave (%d); endless waves are not supported" % [_wave, RunData.nb_of_waves])
		return
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
	for m in _run.get("waveModifiers", []):
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
