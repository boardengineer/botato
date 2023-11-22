extends Node 

signal setting_changed(setting_name, value, mod_name)

# This Mirrors Configs to act as a backup and make reads shorter without string lookups
var enable_autobattler
var enable_ai_visuals
var enable_ai_marker
var enable_smoothing
var smoothing_speed
var item_weight
var projectile_weight
var tree_weight
var boss_weight
var bumper_weight
var egg_weight
var bumper_distance

var was_space_pressed = false
var was_shift_pressed = false

const DEFAULT_COOLDOWN = .2
var option_cooldown = DEFAULT_COOLDOWN

func _ready():
	reset_defaults()
	load_mod_options()
	
func _input(event):
	if event is InputEventKey:
		if event.shift and event.scancode == KEY_SPACE and option_cooldown < 0.0:
			option_cooldown = DEFAULT_COOLDOWN
			enable_autobattler = not enable_autobattler
			emit_signal("setting_changed", "ENABLE_AUTOBATTLER", enable_autobattler, "Pasha-AutoBattler")
			
			if $"/root/ModLoader".has_node("dami-ModOptions"):
				var mod_configs_interface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
				var mod_configs = mod_configs_interface.mod_configs
			
				if mod_configs.has("Pasha-AutoBattler"):
					var config = mod_configs["Pasha-AutoBattler"]
					config["ENABLE_AUTOBATTLER"] = enable_autobattler
					mod_configs_interface.on_setting_changed("ENABLE_AUTOBATTLER", enable_autobattler, "Pasha-AutoBattler")
			

func _process(delta):
	option_cooldown -= delta

func load_mod_options():
	
	if not $"/root/ModLoader".has_node("dami-ModOptions"):
		return
		
	var mod_configs = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface").mod_configs

	if mod_configs.has("Pasha-AutoBattler"):
		var config = mod_configs["Pasha-AutoBattler"]
		
		if config.has("ENABLE_AUTOBATTLER"):
			enable_autobattler = config["ENABLE_AUTOBATTLER"]
		
		if config.has("ENABLE_AI_VISUALS"):
			enable_ai_visuals = config["ENABLE_AI_VISUALS"]
		
		if config.has("ENABLE_AI_MARKER"):
			enable_ai_marker = config["ENABLE_AI_MARKER"]
			
		if config.has("ENABLE_SMOOTHING"):
			enable_smoothing = config["ENABLE_SMOOTHING"]
		
		if config.has("SMOOTHING_SPEED"):
			smoothing_speed = config["SMOOTHING_SPEED"]
		
		if config.has("ITEM_WEIGHT"):
			item_weight = config["ITEM_WEIGHT"]
		
		if config.has("PROJECTILE_WEIGHT"):
			projectile_weight = config["PROJECTILE_WEIGHT"]
		
		if config.has("TREE_WEIGHT"):
			tree_weight = config["TREE_WEIGHT"]
		
		if config.has("BOSS_WEIGHT"):
			boss_weight = config["BOSS_WEIGHT"]
		
		if config.has("BUMPER_WEIGHT"):
			bumper_weight = config["BUMPER_WEIGHT"]
		
		if config.has("EGG_WEIGHT"):
			egg_weight = config["EGG_WEIGHT"]
		
		if config.has("BUMPER_DISTANCE"):
			bumper_distance = config["BUMPER_DISTANCE"]


func reset_defaults() -> void:
	enable_autobattler = false
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
	bumper_distance = 50
