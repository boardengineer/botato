# Persistent /root service: reads the enemy count, maps it to a vibration
# level, and drives the device over one of two transports:
#
#   MODE_HTTP  Lovense Remote's Game Mode local API (phone on the same LAN),
#              or the Lovense Connect desktop app + Lovense USB dongle at
#              127.0.0.1. POST http://<addr>/command, strength 0..20.
#   MODE_WS    Intiface Central (buttplug.io) on this PC -- the device pairs
#              to the PC's OWN Bluetooth adapter and Intiface exposes
#              ws://127.0.0.1:12345. GDScript has no BLE access, so "direct
#              Bluetooth" is Intiface doing the radio and us doing websocket.
#
# The enemy count comes from the current scene's _entity_spawner, polled at
# 4 Hz -- the same source ai_telemetry reads. No gameplay scripts are
# extended: if this mod breaks, the game and the AutoBattler are untouched.
extends Node

const CONFIG_PATH = "user://pasha-lovense.cfg"
const CONFIG_SECTION = "lovense"

const MODE_HTTP = 0
const MODE_WS = 1

const POLL_SECS = 0.25           # enemy-count sampling and send cadence
const SPECIAL_BONUS = 0.2        # +20% intensity per boss or elite on the map
const KEEPALIVE_SECS = 4.0       # re-assert the level: survives app restarts
const RECONNECT_SECS = 5.0       # websocket retry cadence
const MAX_LEVEL = 20             # Lovense strength scale; ws scales to 0..1

signal status_changed(text)

# -- config, persisted --
var mode = MODE_HTTP
var address = ""                 # "ip[:port]"; defaults filled per mode
var horde_size = 100.0           # enemies on screen that mean "full power"
var enabled = true

var status = "idle"

var _http = null                 # HTTPRequest (MODE_HTTP)
var _http_busy = false
var _http_pending = -1           # level queued while a request is in flight
var _ws = null                   # WebSocketClient (MODE_WS)
var _ws_up = false
var _ws_msg_id = 0
var _ws_devices = []             # [{index, vibes}] from Intiface
var _since_reconnect = 0.0
var _last_sent = -1
var _since_send = 0.0
var _timer = null
var _in_wave = false             # wave timer running; gates both output and HUD
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

	# A previous session that crashed mid-wave leaves the device running
	# (timeSec 0 holds until countermanded). Clear it on startup.
	if enabled and address != "":
		if mode == MODE_HTTP:
			_send_vibrate(0)
		else:
			_ws_connect()


func _process(_delta):
	if _ws != null:
		_ws.poll()


# ---------------------------------------------------------------- level --

func _on_tick():
	_since_send += POLL_SECS
	if mode == MODE_WS and enabled and address != "" and not _ws_up:
		_since_reconnect += POLL_SECS
		if _since_reconnect >= RECONNECT_SECS:
			_since_reconnect = 0.0
			_ws_connect()

	var level = 0
	if enabled and address != "":
		level = _target_level()
	if level != _last_sent or (_since_send >= KEEPALIVE_SECS and level > 0):
		_send_vibrate(level)
	_update_hud(level)


func _update_hud(level):
	if _hud_label == null:
		return
	var show = enabled and address != "" and _in_wave
	_hud_label.visible = show
	if not show:
		return
	var pct = int(round(100.0 * level / MAX_LEVEL))
	var filled = int(round(10.0 * level / MAX_LEVEL))
	var bar = ""
	for i in range(10):
		bar += ("#" if i < filled else "-")
	_hud_label.text = "Lovense [%s] %d%%" % [bar, pct]


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
	if count <= 0:
		return 0
	# Saturating curve, not linear: early enemies each matter, late ones
	# barely add -- which is what makes the difference FELT between a trickle
	# and a swarm. 1 - e^-3 = 0.95, so scaling by horde_size / 3 puts a full
	# horde at raw >= 19, promoted to a clean 20 below. Defaults: 10 enemies
	# = 5, 50 = 16, 100+ = flat out.
	var raw = MAX_LEVEL * (1.0 - exp(-float(count) / max(horde_size / 3.0, 1.0)))
	# Bosses and elites raise the stakes beyond what their headcount says:
	# +20% each, multiplicative on the crowd level. Both flags live on the
	# base enemy class (ItemEnemy), and the shared boss class carries
	# is_elite, so this covers wave bosses and elites alike. Compared with
	# == true on purpose: get() returns null for units lacking the property.
	var special = 0
	for e in spawner.enemies:
		if is_instance_valid(e) and (e.get("is_elite") == true or e.get("is_boss") == true):
			special += 1
	raw *= 1.0 + SPECIAL_BONUS * special
	if raw >= MAX_LEVEL - 1.0:
		return MAX_LEVEL
	return int(round(raw))


func _send_vibrate(level):
	if mode == MODE_HTTP:
		_http_command({"command": "Function", "action": "Vibrate:%d" % level,
				"timeSec": 0, "apiVer": 1}, level)
	else:
		_ws_vibrate(level)


# -------------------------------------------------- public, for the menu --

func test_pulse():
	if mode == MODE_HTTP:
		_http_command({"command": "Function", "action": "Vibrate:12",
				"timeSec": 1, "apiVer": 1}, -1)
	else:
		_ws_vibrate(12)
		# One-shot: the next tick restores whatever the game state implies,
		# which outside a wave is 0.
		_last_sent = -1


func probe():
	if mode == MODE_HTTP:
		_http_command({"command": "GetToys"}, -1)
	else:
		_ws_connect()


func set_mode(m):
	if m == mode:
		return
	_send_vibrate(0)             # stop on the OLD transport before switching
	mode = m
	_last_sent = -1
	if mode == MODE_WS:
		if address == "" or address.begins_with("192.") or address.begins_with("10."):
			address = "127.0.0.1:12345"
		_ws_connect()
	else:
		_ws_teardown()
		if address == "127.0.0.1:12345":
			address = ""
	save_config()


func set_address(a):
	address = a.strip_edges()
	_last_sent = -1
	if mode == MODE_WS:
		_ws_teardown()
	save_config()


# ----------------------------------------------------------- HTTP (Lovense) --

func _split_address(default_port):
	var host = address
	var port = default_port
	if ":" in address:
		var parts = address.split(":")
		host = parts[0]
		port = int(parts[1])
	return [host, port]


func _http_command(payload, level):
	if address == "":
		_set_status("no address set")
		return
	if _http_busy:
		if level >= 0:
			_http_pending = level
		return
	var hp = _split_address(30010)
	var url = "http://%s:%d/command" % [hp[0], hp[1]]
	var err = _http.request(url, ["Content-Type: application/json"], false,
			HTTPClient.METHOD_POST, JSON.print(payload))
	if err != OK:
		_set_status("request failed (err %d)" % err)
		return
	_http_busy = true
	if level >= 0:
		_last_sent = level
		_since_send = 0.0


func _on_http_done(result, code, _headers, _body):
	_http_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("app unreachable -- Game Mode on? same network?")
	elif code == 200:
		_set_status("connected (level %d)" % max(_last_sent, 0))
	else:
		_set_status("app answered HTTP %d" % code)
	if _http_pending >= 0:
		var lv = _http_pending
		_http_pending = -1
		if lv != _last_sent:
			_send_vibrate(lv)


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
	_ws_devices.push_back({"index": idx, "vibes": vibes})
	_set_status("Intiface: %d device(s)" % _ws_devices.size())


func _ws_vibrate(level):
	if not _ws_up:
		return
	var scalar = clamp(float(level) / float(MAX_LEVEL), 0.0, 1.0)
	for d in _ws_devices:
		var scalars = []
		for i in range(d["vibes"]):
			scalars.push_back({"Index": i, "Scalar": scalar, "ActuatorType": "Vibrate"})
		_ws_send([{"ScalarCmd": {"Id": _next_id(),
				"DeviceIndex": d["index"], "Scalars": scalars}}])
	_last_sent = level
	_since_send = 0.0


func _ws_send(msgs):
	if _ws == null:
		return
	_ws.get_peer(1).put_packet(JSON.print(msgs).to_utf8())


func _next_id():
	_ws_msg_id += 1
	return _ws_msg_id


# ---------------------------------------------------------------- plumbing --

func _set_status(s):
	status = s
	emit_signal("status_changed", s)


func _notification(what):
	# Best effort: a quitting process may not flush the request, which is why
	# _ready also clears on the NEXT launch.
	if what == NOTIFICATION_WM_QUIT_REQUEST and _last_sent > 0:
		_send_vibrate(0)


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
