extends Node

signal setting_changed(setting_name, value, mod_name)

# Runtime option store for the AutoBattler mod. Values are mirrored as plain vars
# for short reads, persisted to a ConfigFile directly. When the optional
# dami-ModOptions mod is present, EXACTLY two of them -- Enable Bot
# (ENABLE_AUTOBATTLER) and Autoshop (ENABLE_AUTOSHOP), declared in manifest
# config_schema -- are exposed in its panel and kept in sync here; nothing else is
# surfaced. Also toggled via the hotkey below and the per-bot AUTO-SHOP panel toggle.

var enable_autobattler : bool = false
const ENABLE_AUTOBATTLER_OPTION_NAME = "ENABLE_AUTOBATTLER"

# Automatic shopping for the pure-AutoBattler mode (every slot a bot). Default
# OFF; the WaveLab test harness sets it true explicitly. Co-op bot slots do NOT
# use this flag -- each opts in via CoopService.autoshop_by_index (its panel toggle).
var enable_autoshop : bool = false
const ENABLE_AUTOSHOP_OPTION_NAME = "ENABLE_AUTOSHOP"

var enable_ai_visuals : bool = false
const ENABLE_AI_VISUALS_OPTION_NAME = "ENABLE_AI_VISUALS"

# Arbiter weight overrides harvested from --arb-<name>=<value> startup args.
var arb_overrides : Dictionary = {}

var enable_ai_marker : bool = true
const ENABLE_AI_MARKER_OPTION_NAME = "ENABLE_AI_MARKER"

var enable_smoothing : bool = true
const ENABLE_SMOOTHING_OPTION_NAME = "ENABLE_SMOOTHING"

var smoothing_speed : float = 1
const SMOOTHING_SPEED_OPTION_NAME = "SMOOTHING_SPEED"

var item_weight : float = .5
const ITEM_WEIGHT_OPTION_NAME = "ITEM_WEIGHT"

var projectile_weight : float = 2
const PROJECTILE_WEIGHT_OPTION_NAME = "PROJECTILE_WEIGHT"

var tree_weight : float = 2
const TREE_WEIGHT_OPTION_NAME = "TREE_WEIGHT"

var boss_weight : float = 3
const BOSS_WEIGHT_OPTION_NAME = "BOSS_WEIGHT"

var bumper_weight : float = 2
const BUMPER_WEIGHT_OPTION_NAME = "BUMPER_WEIGHT"

var egg_weight : float = 5
const EGG_WEIGHT_OPTION_NAME = "EGG_WEIGHT"

var bumper_distance : float = 300
const BUMPER_DISTANCE_OPTION_NAME = "BUMPER_DISTANCE"

const DEFAULT_COOLDOWN = .2
var _last_ss_ms = 0   # OS.get_ticks_msec of the last Shift+Space toggle (debounce)
var option_cooldown = DEFAULT_COOLDOWN

const MOD_NAME = "Pasha-AutoBattler"
const CONFIG_FILENAME = "user://pasha-botato-options.cfg"
const CONFIG_SECTION = "options"


func _ready():
	reset_defaults()
	load_mod_options()
	# When ModOptions is installed, let its panel own the two exposed toggles: read
	# their current values and listen for live changes. No-op without the mod.
	_connect_modoptions()

	# Benchmarks pick the controller on the command line; it must win over the
	# saved config so a bench run never inherits whatever was toggled by hand.
	var startup_args = Utils.get_startup_arguments()
	for key in startup_args.keys():
		if key.begins_with("arb-"):
			arb_overrides[key.substr(4)] = float(startup_args[key])


# --- Optional dami-ModOptions integration (Enable Bot + Autoshop only) --------
func _modoptions_interface():
	var ml = get_node_or_null("/root/ModLoader")
	if ml == null or not ml.has_node("dami-ModOptions/ModsConfigInterface"):
		return null
	return ml.get_node("dami-ModOptions/ModsConfigInterface")


func _connect_modoptions() -> void:
	var iface = _modoptions_interface()
	if iface == null:
		return
	# Apply the panel's stored values for the two toggles we expose.
	if iface.has_method("get_settings"):
		var s = iface.get_settings(MOD_NAME)
		if typeof(s) == TYPE_DICTIONARY:
			if s.has(ENABLE_AUTOBATTLER_OPTION_NAME):
				enable_autobattler = s[ENABLE_AUTOBATTLER_OPTION_NAME]
			if s.has(ENABLE_AUTOSHOP_OPTION_NAME):
				enable_autoshop = s[ENABLE_AUTOSHOP_OPTION_NAME]
	if not iface.is_connected("setting_changed", self, "setting_changed"):
		var _e = iface.connect("setting_changed", self, "setting_changed")


# Called by ModOptions when a panel toggle changes. We only own two keys.
func setting_changed(key: String, value, mod) -> void:
	if mod != MOD_NAME:
		return
	if key == ENABLE_AUTOBATTLER_OPTION_NAME:
		enable_autobattler = value
		# Re-fire our own signal so the player's ai_icon marker refreshes when the
		# toggle is flipped from the ModOptions panel (not just the hotkey). This
		# does not re-enter here -- this handler listens to ModOptions' signal, not
		# ours; ours drives only the player marker.
		emit_signal("setting_changed", key, value, MOD_NAME)
	elif key == ENABLE_AUTOSHOP_OPTION_NAME:
		enable_autoshop = value


# Push a hotkey/programmatic change back into the ModOptions panel so its checkbox
# reflects the new state. No-op without the mod.
func _push_modoption(key: String, value) -> void:
	var iface = _modoptions_interface()
	if iface == null:
		return
	if ("mod_configs" in iface) and iface.mod_configs.has(MOD_NAME):
		iface.mod_configs[MOD_NAME][key] = value
	if iface.has_method("on_setting_changed"):
		iface.on_setting_changed(key, value, MOD_NAME)


func _input(event):
	# `pressed` + `echo` guards stop a toggle firing twice per press / on auto-repeat.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.shift and event.scancode == KEY_SPACE:
			# Debounce with a wall-clock timestamp -- Shift+Space arrives as a double
			# event per physical press (~0.2-0.3s apart), which the old delta cooldown
			# let slip through, double-toggling to no net change.
			var now = OS.get_ticks_msec()
			if now - _last_ss_ms >= 350:
				_last_ss_ms = now
				enable_autobattler = not enable_autobattler
				# Notify our own listeners (the player's ai_icon marker updates from
				# this) AND reflect into the ModOptions panel.
				emit_signal("setting_changed", ENABLE_AUTOBATTLER_OPTION_NAME, enable_autobattler, MOD_NAME)
				_push_modoption(ENABLE_AUTOBATTLER_OPTION_NAME, enable_autobattler)
				save_configs()


func _process(delta):
	option_cooldown -= delta


func load_mod_options():
	var config = ConfigFile.new()
	if config.load(CONFIG_FILENAME) != OK:
		return
	enable_autobattler = config.get_value(CONFIG_SECTION, ENABLE_AUTOBATTLER_OPTION_NAME, false)
	enable_autoshop    = config.get_value(CONFIG_SECTION, ENABLE_AUTOSHOP_OPTION_NAME, false)
	enable_ai_visuals  = config.get_value(CONFIG_SECTION, ENABLE_AI_VISUALS_OPTION_NAME, false)
	enable_ai_marker   = config.get_value(CONFIG_SECTION, ENABLE_AI_MARKER_OPTION_NAME, true)
	enable_smoothing   = config.get_value(CONFIG_SECTION, ENABLE_SMOOTHING_OPTION_NAME, true)
	smoothing_speed    = config.get_value(CONFIG_SECTION, SMOOTHING_SPEED_OPTION_NAME, 1)
	item_weight        = config.get_value(CONFIG_SECTION, ITEM_WEIGHT_OPTION_NAME, .5)
	projectile_weight  = config.get_value(CONFIG_SECTION, PROJECTILE_WEIGHT_OPTION_NAME, 2)
	tree_weight        = config.get_value(CONFIG_SECTION, TREE_WEIGHT_OPTION_NAME, 2)
	boss_weight        = config.get_value(CONFIG_SECTION, BOSS_WEIGHT_OPTION_NAME, 3)
	bumper_weight      = config.get_value(CONFIG_SECTION, BUMPER_WEIGHT_OPTION_NAME, 2)
	egg_weight         = config.get_value(CONFIG_SECTION, EGG_WEIGHT_OPTION_NAME, 5)
	bumper_distance    = config.get_value(CONFIG_SECTION, BUMPER_DISTANCE_OPTION_NAME, 300)


func save_configs() -> void:
	var config = ConfigFile.new()
	config.set_value(CONFIG_SECTION, ENABLE_AUTOBATTLER_OPTION_NAME, enable_autobattler)
	config.set_value(CONFIG_SECTION, ENABLE_AUTOSHOP_OPTION_NAME    , enable_autoshop)
	config.set_value(CONFIG_SECTION, ENABLE_AI_VISUALS_OPTION_NAME , enable_ai_visuals)
	config.set_value(CONFIG_SECTION, ENABLE_AI_MARKER_OPTION_NAME  , enable_ai_marker)
	config.set_value(CONFIG_SECTION, ENABLE_SMOOTHING_OPTION_NAME  , enable_smoothing)
	config.set_value(CONFIG_SECTION, SMOOTHING_SPEED_OPTION_NAME   , smoothing_speed)
	config.set_value(CONFIG_SECTION, ITEM_WEIGHT_OPTION_NAME       , item_weight)
	config.set_value(CONFIG_SECTION, PROJECTILE_WEIGHT_OPTION_NAME , projectile_weight)
	config.set_value(CONFIG_SECTION, TREE_WEIGHT_OPTION_NAME       , tree_weight)
	config.set_value(CONFIG_SECTION, BOSS_WEIGHT_OPTION_NAME       , boss_weight)
	config.set_value(CONFIG_SECTION, BUMPER_WEIGHT_OPTION_NAME     , bumper_weight)
	config.set_value(CONFIG_SECTION, EGG_WEIGHT_OPTION_NAME        , egg_weight)
	config.set_value(CONFIG_SECTION, BUMPER_DISTANCE_OPTION_NAME   , bumper_distance)
	config.save(CONFIG_FILENAME)


func reset_defaults() -> void:
	enable_autobattler = false
	enable_autoshop = false
	enable_ai_marker = true
	enable_ai_visuals = false
	enable_smoothing = true

	smoothing_speed = 1
	item_weight = 0.5
	projectile_weight = 2.0
	tree_weight = 2.0
	boss_weight = 3.0
	bumper_weight = 2.0
	egg_weight = 5.0
	bumper_distance = 300
