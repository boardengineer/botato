# Persistent /root service: reads the game state, maps it to vibration
# levels, and drives Lovense devices over one of two transports:
#
#   MODE_HTTP  Lovense Remote's Game Mode local API (phone on the same LAN),
#              or the Lovense Connect desktop app + Lovense USB dongle at
#              127.0.0.1. POST http://<addr>/command, strength 0..20.
#   MODE_WS    Intiface Central (buttplug.io) on this PC -- the device pairs
#              to the PC's OWN Bluetooth adapter and Intiface exposes
#              ws://127.0.0.1:12345. GDScript has no BLE access, so "direct
#              Bluetooth" is Intiface doing the radio and us doing websocket.
#
# TWO SIGNALS, ROUTED BY DEVICE:
#   crowd  enemy count on a saturating curve, plus a flat bonus per boss or
#          elite -- sent to every device EXCEPT a Gemini.
#   death  how close the player is to dying (1 - hp_frac, superlinear) --
#          sent to any device whose name matches "gemini".
# With no Gemini paired, behaviour is exactly the old single-signal mod.
#
# Game state comes from the current scene's _entity_spawner / _players,
# polled at 4 Hz -- the same sources ai_telemetry reads. No gameplay scripts
# are extended: if this mod breaks, the game and the AutoBattler are
# untouched.
extends Node

const CONFIG_PATH = "user://pasha-lovense.cfg"
const CONFIG_SECTION = "lovense"

const MODE_HTTP = 0
const MODE_WS = 1

const POLL_SECS = 0.25           # game-state sampling and send cadence
const SPECIAL_BONUS = 0.2        # +20% of total power per boss or elite on the map
const KEEPALIVE_SECS = 4.0       # re-assert the level: survives app restarts
const HOLD_SECS = 6              # DEAD-MAN'S SWITCH: every vibrate is a finite
                                 # hold, refreshed by the keepalive. If the game
                                 # closes in ANY way -- quit, crash, kill -- the
                                 # device self-stops within this many seconds
                                 # because nothing re-asserts it. Must exceed
                                 # KEEPALIVE_SECS or the device stutters.
const RECONNECT_SECS = 5.0       # websocket retry cadence
const TOYS_REFRESH_SECS = 30.0   # HTTP: re-enumerate toys, catches (dis)connects
const MAX_LEVEL = 20             # Lovense strength scale; ws scales to 0..1
const GEMINI_MATCH = "gemini"    # device-name substring that routes the death signal
const DEATH_GAMMA = 1.5          # superlinear: full HP is silent, 50% HP ~7/20,
                                 # 25% ~13/20, near death pegs at 20

signal status_changed(text)

# -- config, persisted --
var mode = MODE_HTTP
var address = ""                 # "ip[:port]"; defaults filled per mode
var horde_size = 100.0           # enemies on screen that mean "full power"
var enabled = true

var status = "idle"

var _http = null                 # HTTPRequest (MODE_HTTP)
var _http_busy = false
var _http_pending = {}           # target-key -> payload queued while in flight;
                                 # latest per target wins, stale levels drop
var _http_awaiting_toys = false  # the in-flight request is a GetToys
var _toys = []                   # HTTP: [{id, name}] from GetToys
var _since_toys = 999.0
var _ws = null                   # WebSocketClient (MODE_WS)
var _ws_up = false
var _ws_msg_id = 0
var _ws_devices = []             # [{index, vibes, name}] from Intiface
var _since_reconnect = 0.0
var _last_crowd = -1
var _last_hp = -1
var _since_send = 0.0
var _timer = null
var _in_wave = false             # wave timer running; gates both signals and HUD
var _hud_label = null            # on-screen relative-power readout


func _init():
	# Keep ticking while the tree is paused, so pausing zeroes the device
	# instead of freezing it at the last level.
	pause_mode = Node.PAUSE_MODE_PROCESS


func _ready():
	load_config()

	_http = HTTPRequest.new()
	_http.connect("request_completed", self, "_on_http_done")
	add_child(_http)

	_timer = Timer.new()
	_timer.wait_time = POLL_SECS
	_timer.autostart = true
	_timer.connect("timeout", self, "_on_tick")
	add_child(_timer)

	# Small corner readout of the current power, only shown mid-wave. ASCII
	# bar on purpose: the game font is not guaranteed to carry block glyphs.
	var hud = CanvasLayer.new()
	hud.layer = 90
	add_child(hud)
	_hud_label = Label.new()
	_hud_label.rect_position = Vector2(12, 64)
	_hud_label.modulate = Color(1.0, 1.0, 1.0, 0.75)
	_hud_label.visible = false
	hud.add_child(_hud_label)

	# Belt and suspenders: finite holds (HOLD_SECS) mean a dead session
	# cannot leave the device running more than a few seconds, but a clean
	# zero on startup costs nothing and covers any state we did not model.
	if enabled and address != "":
		if mode == MODE_HTTP:
			stop_all()
			probe()          # enumerate toys so Gemini routing works
		else:
			_ws_connect()


func _process(_delta):
	if _ws != null:
		_ws.poll()


# ---------------------------------------------------------------- levels --

func _on_tick():
	_since_send += POLL_SECS
	if enabled and address != "":
		if mode == MODE_HTTP:
			_since_toys += POLL_SECS
			if _since_toys >= TOYS_REFRESH_SECS:
				_since_toys = 0.0
				probe()
		elif not _ws_up:
			_since_reconnect += POLL_SECS
			if _since_reconnect >= RECONNECT_SECS:
				_since_reconnect = 0.0
				_ws_connect()

	var crowd = 0
	var hp = 0
	if enabled and address != "":
		crowd = _target_level()      # also refreshes _in_wave
		hp = _death_level()
	var stale = _since_send >= KEEPALIVE_SECS and (crowd > 0 or hp > 0)
	if crowd != _last_crowd or hp != _last_hp or stale:
		_send_levels(crowd, hp)
	_update_hud(crowd, hp)


func _target_level():
	_in_wave = false
	var tree = get_tree()
	if tree.paused:
		return 0
	var scene = tree.current_scene
	if scene == null:
		return 0
	# Only the wave scene has an _entity_spawner; menus and the shop read as
	# null and the device idles. Same source ai_telemetry counts from.
	var spawner = scene.get("_entity_spawner")
	if spawner == null or not is_instance_valid(spawner):
		return 0
	# HARD STOP AT WAVE END. Enemy count alone is not enough: stragglers can
	# linger on screen through the end-of-wave sequence and would keep the
	# device running into the upgrade screen. The wave Timer expires the
	# moment the wave is over, whatever is still standing.
	var wt = scene.get("_wave_timer")
	if wt == null or not is_instance_valid(wt) or wt.is_stopped():
		return 0
	_in_wave = true
	var count = spawner.enemies.size()
	var raw = 0.0
	if count > 0:
		# Saturating curve, not linear: early enemies each matter, late ones
		# barely add -- which is what makes the difference FELT between a
		# trickle and a swarm. 1 - e^-3 = 0.95, so scaling by horde_size / 3
		# puts a full horde at raw >= 19, promoted to a clean 20 below.
		raw = MAX_LEVEL * (1.0 - exp(-float(count) / max(horde_size / 3.0, 1.0)))
	# Bosses and elites raise the stakes beyond what their headcount says:
	# each adds 20% OF TOTAL POTENTIAL POWER (+4 on the 0..20 scale), flat.
	# Counted from the spawner's separate `bosses` array -- NOT `enemies`,
	# which does not contain them (and unit flags are a trap: is_elite is
	# false on true bosses, is_boss does not exist on units). Same source
	# vanilla trusts for get_nb_bosses_and_elites_alive().
	var boss_list = spawner.get("bosses")
	if boss_list != null:
		raw += SPECIAL_BONUS * MAX_LEVEL * boss_list.size()
	if raw <= 0.0:
		return 0
	if raw >= MAX_LEVEL - 1.0:
		return MAX_LEVEL
	return int(round(raw))


func _death_level():
	# Gemini signal: how close the player is to dying. Shares every gate the
	# crowd signal has (_in_wave covers pause/menu/shop/wave end), so it
	# stops in all the same places.
	if not _in_wave:
		return 0
	var scene = get_tree().current_scene
	var players = scene.get("_players")
	if players == null or players.empty():
		return 0
	var p = players[0]
	if not is_instance_valid(p):
		return 0
	var mx = max(float(p.max_stats.health), 1.0)
	var frac = clamp(float(p.current_stats.health) / mx, 0.0, 1.0)
	var raw = MAX_LEVEL * pow(1.0 - frac, DEATH_GAMMA)
	if raw >= MAX_LEVEL - 1.0:
		return MAX_LEVEL
	return int(round(raw))


# ---------------------------------------------------------------- sending --

func _send_levels(crowd, hp):
	_last_crowd = crowd
	_last_hp = hp
	_since_send = 0.0
	if mode == MODE_HTTP:
		var geminis = []
		var others = []
		for t in _toys:
			if GEMINI_MATCH in t["name"].to_lower():
				geminis.push_back(t)
			else:
				others.push_back(t)
		if geminis.empty():
			# No Gemini known (or toys not enumerated yet): broadcast the
			# crowd signal to everything -- the old behaviour, exactly.
			_http_vibrate(crowd, "")
		else:
			for t in geminis:
				_http_vibrate(hp, t["id"])
			for t in others:
				_http_vibrate(crowd, t["id"])
	else:
		for d in _ws_devices:
			var lvl = hp if (GEMINI_MATCH in d["name"].to_lower()) else crowd
			_ws_vibrate_device(d, lvl)


func stop_all():
	_last_crowd = -1
	_last_hp = -1
	if mode == MODE_HTTP:
		_http_vibrate(0, "")
	else:
		for d in _ws_devices:
			_ws_vibrate_device(d, 0)


# -------------------------------------------------- public, for the menu --

func test_pulse():
	if mode == MODE_HTTP:
		_http_command({"command": "Function", "action": "Vibrate:12",
				"timeSec": 1, "apiVer": 1}, "")
	else:
		for d in _ws_devices:
			_ws_vibrate_device(d, 12)
	# One-shot: force the next tick to re-assert whatever the game state
	# implies, which outside a wave is 0.
	_last_crowd = -1
	_last_hp = -1


func probe():
	if mode == MODE_HTTP:
		_http_command({"command": "GetToys"}, null)
	else:
		_ws_connect()


func set_mode(m):
	if m == mode:
		return
	stop_all()                   # stop on the OLD transport before switching
	mode = m
	_last_crowd = -1
	_last_hp = -1
	_toys = []
	if mode == MODE_WS:
		if address == "" or address.begins_with("192.") or address.begins_with("10."):
			address = "127.0.0.1:12345"
		_ws_connect()
	else:
		_ws_teardown()
		if address == "127.0.0.1:12345":
			address = ""
		_since_toys = 999.0      # enumerate toys promptly on the new address
	save_config()


func set_address(a):
	address = a.strip_edges()
	_last_crowd = -1
	_last_hp = -1
	_toys = []
	_since_toys = 999.0
	if mode == MODE_WS:
		_ws_teardown()
	save_config()


func has_gemini():
	if mode == MODE_HTTP:
		for t in _toys:
			if GEMINI_MATCH in t["name"].to_lower():
				return true
		return false
	for d in _ws_devices:
		if GEMINI_MATCH in d["name"].to_lower():
			return true
	return false


# ----------------------------------------------------------- HTTP (Lovense) --

func _split_address(default_port):
	var host = address
	var port = default_port
	if ":" in address:
		var parts = address.split(":")
		host = parts[0]
		port = int(parts[1])
	return [host, port]


func _http_vibrate(level, toy_id):
	# timeSec is FINITE on purpose (see HOLD_SECS): an indefinite hold
	# (timeSec 0) would keep running after a crash. A zero still goes out
	# as an immediate stop rather than waiting for a hold to lapse.
	var hold = 0 if level == 0 else HOLD_SECS
	var payload = {"command": "Function", "action": "Vibrate:%d" % level,
			"timeSec": hold, "apiVer": 1}
	if toy_id != "":
		payload["toy"] = toy_id
	_http_command(payload, toy_id)


# key: "" = broadcast slot, a toy id = that toy's slot, null = unqueued
# (a dropped GetToys is retried by the periodic refresh anyway).
func _http_command(payload, key):
	if address == "":
		_set_status("no address set")
		return
	if _http_busy:
		if key != null:
			_http_pending[key] = payload
		return
	var hp = _split_address(30010)
	var url = "http://%s:%d/command" % [hp[0], hp[1]]
	var err = _http.request(url, ["Content-Type: application/json"], false,
			HTTPClient.METHOD_POST, JSON.print(payload))
	if err != OK:
		_set_status("request failed (err %d)" % err)
		return
	_http_busy = true
	_http_awaiting_toys = payload.get("command", "") == "GetToys"


func _on_http_done(result, code, _headers, body):
	_http_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("app unreachable -- Game Mode on? same network?")
	elif code != 200:
		_set_status("app answered HTTP %d" % code)
	elif _http_awaiting_toys:
		_parse_toys(body)
	else:
		_set_status("connected (crowd %d, death %d)" % [max(_last_crowd, 0), max(_last_hp, 0)])
	_http_awaiting_toys = false
	if not _http_pending.empty():
		var k = _http_pending.keys()[0]
		var pl = _http_pending[k]
		_http_pending.erase(k)
		_http_command(pl, k)


func _parse_toys(body):
	# GetToys nests a JSON-encoded STRING of toys inside the JSON response
	# on most app versions; some return it as an object. Handle both.
	var parsed = JSON.parse(body.get_string_from_utf8())
	if parsed.error != OK or not parsed.result is Dictionary:
		return
	var data = parsed.result.get("data", {})
	if not data is Dictionary:
		return
	var toys_raw = data.get("toys", {})
	if toys_raw is String:
		var inner = JSON.parse(toys_raw)
		toys_raw = (inner.result if inner.error == OK else {})
	if not toys_raw is Dictionary:
		return
	_toys = []
	for id in toys_raw.keys():
		var info = toys_raw[id]
		var toy_name = ""
		if info is Dictionary:
			toy_name = str(info.get("name", ""))
		_toys.push_back({"id": str(id), "name": toy_name})
	var g = 0
	for t in _toys:
		if GEMINI_MATCH in t["name"].to_lower():
			g += 1
	_set_status("connected: %d toy(s), %d gemini" % [_toys.size(), g])


# ------------------------------------------------------ websocket (Intiface) --

func _ws_connect():
	_ws_teardown()
	if address == "":
		address = "127.0.0.1:12345"
	_ws = WebSocketClient.new()
	_ws.connect("connection_established", self, "_on_ws_open")
	_ws.connect("connection_closed", self, "_on_ws_closed")
	_ws.connect("connection_error", self, "_on_ws_closed")
	_ws.connect("data_received", self, "_on_ws_data")
	var hp = _split_address(12345)
	var err = _ws.connect_to_url("ws://%s:%d" % [hp[0], hp[1]])
	if err != OK:
		_set_status("Intiface connect failed (err %d)" % err)
		_ws = null


func _ws_teardown():
	if _ws != null:
		_ws.disconnect_from_host()
		_ws = null
	_ws_up = false
	_ws_devices = []


func _on_ws_open(_proto):
	_ws.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	_ws_send([{"RequestServerInfo": {"Id": _next_id(),
			"ClientName": "BrotatoLovenseLink", "MessageVersion": 3}}])


func _on_ws_closed(_arg = null):
	_ws_up = false
	_ws_devices = []
	_set_status("Intiface disconnected")


func _on_ws_data():
	var pkt = _ws.get_peer(1).get_packet().get_string_from_utf8()
	var parsed = JSON.parse(pkt)
	if parsed.error != OK or not parsed.result is Array:
		return
	for msg in parsed.result:
		if msg.has("ServerInfo"):
			_ws_up = true
			_ws_send([{"RequestDeviceList": {"Id": _next_id()}}])
			_ws_send([{"StartScanning": {"Id": _next_id()}}])
		elif msg.has("DeviceList"):
			_ws_devices = []
			for d in msg["DeviceList"].get("Devices", []):
				_ws_track_device(d)
		elif msg.has("DeviceAdded"):
			_ws_track_device(msg["DeviceAdded"])
		elif msg.has("DeviceRemoved"):
			var idx = msg["DeviceRemoved"].get("DeviceIndex", -1)
			for i in range(_ws_devices.size() - 1, -1, -1):
				if _ws_devices[i]["index"] == idx:
					_ws_devices.remove(i)
			_set_status("Intiface: %d device(s)" % _ws_devices.size())
		elif msg.has("Error"):
			_set_status("Intiface error: %s" % str(msg["Error"].get("ErrorMessage", "?")))


func _ws_track_device(d):
	var vibes = 0
	var msgs = d.get("DeviceMessages", {})
	for actuator in msgs.get("ScalarCmd", []):
		if actuator.get("ActuatorType", "") == "Vibrate":
			vibes += 1
	if vibes == 0:
		return
	var idx = d.get("DeviceIndex", -1)
	for known in _ws_devices:
		if known["index"] == idx:
			return
	_ws_devices.push_back({"index": idx, "vibes": vibes,
			"name": str(d.get("DeviceName", ""))})
	_set_status("Intiface: %d device(s)" % _ws_devices.size())


func _ws_vibrate_device(d, level):
	# No duration parameter exists in buttplug, and none is needed: Intiface
	# stops all devices itself when the client socket drops, and the OS
	# closes the socket however the process dies. The websocket path gets
	# its dead-man's switch from the server.
	if not _ws_up:
		return
	var scalar = clamp(float(level) / float(MAX_LEVEL), 0.0, 1.0)
	var scalars = []
	for i in range(d["vibes"]):
		scalars.push_back({"Index": i, "Scalar": scalar, "ActuatorType": "Vibrate"})
	_ws_send([{"ScalarCmd": {"Id": _next_id(),
			"DeviceIndex": d["index"], "Scalars": scalars}}])


func _ws_send(msgs):
	if _ws == null:
		return
	_ws.get_peer(1).put_packet(JSON.print(msgs).to_utf8())


func _next_id():
	_ws_msg_id += 1
	return _ws_msg_id


# ---------------------------------------------------------------- plumbing --

func _bar(level):
	var filled = int(round(10.0 * level / MAX_LEVEL))
	var s = ""
	for i in range(10):
		s += ("#" if i < filled else "-")
	return s


func _update_hud(crowd, hp):
	if _hud_label == null:
		return
	var show = enabled and address != "" and _in_wave
	_hud_label.visible = show
	if not show:
		return
	var txt = "Lovense [%s] %d%%" % [_bar(crowd), int(round(100.0 * crowd / MAX_LEVEL))]
	if has_gemini():
		txt += "\nGemini  [%s] %d%%" % [_bar(hp), int(round(100.0 * hp / MAX_LEVEL))]
	_hud_label.text = txt


func _set_status(s):
	status = s
	emit_signal("status_changed", s)


func _notification(what):
	# Best effort: a quitting process may not flush the request. HOLD_SECS
	# bounds the damage regardless, and _ready clears on the next launch.
	if what == NOTIFICATION_WM_QUIT_REQUEST and (_last_crowd > 0 or _last_hp > 0):
		stop_all()


func load_config():
	var cfg = ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	mode = int(cfg.get_value(CONFIG_SECTION, "mode", MODE_HTTP))
	address = str(cfg.get_value(CONFIG_SECTION, "address", ""))
	horde_size = float(cfg.get_value(CONFIG_SECTION, "horde_size", 100.0))
	enabled = bool(cfg.get_value(CONFIG_SECTION, "enabled", true))


func save_config():
	var cfg = ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, "mode", mode)
	cfg.set_value(CONFIG_SECTION, "address", address)
	cfg.set_value(CONFIG_SECTION, "horde_size", horde_size)
	cfg.set_value(CONFIG_SECTION, "enabled", enabled)
	cfg.save(CONFIG_PATH)
