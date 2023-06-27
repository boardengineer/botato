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
			emit_signal("setting_changed", "enable_autobattler", enable_autobattler, "Pasha-AutoBattler")
			
			if $"/root/ModLoader".has_node("dami-ModOptions"):
				var mod_configs_interface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
				var mod_configs = mod_configs_interface.mod_configs
			
				if mod_configs.has("Pasha-AutoBattler"):
					var config = mod_configs["Pasha-AutoBattler"]
					config["enable_autobattler"] = enable_autobattler
					mod_configs_interface.on_setting_changed("enable_autobattler", enable_autobattler, "Pasha-AutoBattler")
			

func _process(delta):
	option_cooldown -= delta

func load_mod_options():
	if not $"/root/ModLoader".has_node("dami-ModOptions"):
		return
		
	var mod_configs = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface").mod_configs

	if mod_configs.has("Pasha-AutoBattler"):
		var config = mod_configs["Pasha-AutoBattler"]
		
		if config.has("enable_autobattler"):
			enable_autobattler = config["enable_autobattler"]
			
		if config.has("enable_ai_visuals"):
			enable_ai_visuals = config["enable_ai_visuals"]
			
		if config.has("enable_ai_marker"):
			enable_ai_marker = config["enable_ai_marker"]
			
		if config.has("enable_smoothing"):
			enable_smoothing = config["enable_smoothing"]
		
		if config.has("smoothing_speed"):
			smoothing_speed = config["smoothing_speed"]
		
		if config.has("item_weight"):
			item_weight = config["item_weight"]
			
		if config.has("projectile_weight"):
			projectile_weight = config["projectile_weight"]
			
		if config.has("tree_weight"):
			tree_weight = config["tree_weight"]
			
		if config.has("boss_weight"):
			boss_weight = config["boss_weight"]


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
