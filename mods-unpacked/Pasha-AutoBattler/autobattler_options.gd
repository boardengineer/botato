extends Node

signal setting_changed(setting_name, value, mod_name)

# Runtime option store for the AutoBattler mod. Values are mirrored as plain vars
# for short reads. Persisted to a ConfigFile directly -- no dami-ModOptions
# dependency (removed for a clean, standalone export). Toggled via the hotkeys
# below and, for co-op bots, the per-bot AUTO-SHOP panel toggle.

var enable_autobattler : bool = false
const ENABLE_AUTOBATTLER_OPTION_NAME = "ENABLE_AUTOBATTLER"

# Automatic shopping for the pure-AutoBattler mode (every slot a bot). Default
# OFF; the WaveLab test harness sets it true explicitly. Co-op bot slots do NOT
# use this flag -- each opts in via CoopService.autoshop_by_index (its panel toggle).
var enable_autoshop : bool = false
const ENABLE_AUTOSHOP_OPTION_NAME = "ENABLE_AUTOSHOP"

var enable_ai_visuals : bool = false
const ENABLE_AI_VISUALS_OPTION_NAME = "ENABLE_AI_VISUALS"

# Steering controller select: false = potential field, true = candidate-action
# arbiter. Benchmarks set it with --arbiter=1; Shift+A toggles it live. Defaults
# ON (the controller under development). Not persisted -- startup arg or hotkey only.
var use_arbiter : bool = true

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
var option_cooldown = DEFAULT_COOLDOWN

const MOD_NAME = "Pasha-AutoBattler"
const CONFIG_FILENAME = "user://pasha-botato-options.cfg"
const CONFIG_SECTION = "options"


func _ready():
	reset_defaults()
	load_mod_options()

	# Benchmarks pick the controller on the command line; it must win over the
	# saved config so a bench run never inherits whatever was toggled by hand.
	var startup_args = Utils.get_startup_arguments()
	if startup_args.has("arbiter"):
		use_arbiter = int(startup_args["arbiter"]) != 0
		print("ARBITER %s (startup arg)" % ("on" if use_arbiter else "off"))
	for key in startup_args.keys():
		if key.begins_with("arb-"):
			arb_overrides[key.substr(4)] = float(startup_args[key])


func _input(event):
	# `pressed` + `echo` guards stop a toggle firing twice per press / on auto-repeat.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.shift and event.scancode == KEY_A and option_cooldown < 0.0:
			option_cooldown = DEFAULT_COOLDOWN
			use_arbiter = not use_arbiter
			print("ARBITER %s" % ("on" if use_arbiter else "off"))
		if event.shift and event.scancode == KEY_SPACE and option_cooldown < 0.0:
			option_cooldown = DEFAULT_COOLDOWN
			enable_autobattler = not enable_autobattler
			emit_signal("setting_changed", ENABLE_AUTOBATTLER_OPTION_NAME, enable_autobattler, MOD_NAME)
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
	use_arbiter = true

	smoothing_speed = 1
	item_weight = 0.5
	projectile_weight = 2.0
	tree_weight = 2.0
	boss_weight = 3.0
	bumper_weight = 2.0
	egg_weight = 5.0
	bumper_distance = 300
