extends "res://entities/units/player/player.gd"

var ai_icon_scene = preload("res://mods-unpacked/Pasha-AutoBattler/ui/AIScene.tscn")
var ai_icon
var ModsConfigInterface

func _ready():
	ai_icon = ai_icon_scene.instance()
	add_child(ai_icon)
	
	var direct_signal = true
	
	if $"/root/ModLoader".has_node("dami-ModOptions"):
		var mod_configs = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface").mod_configs
		if mod_configs.has("Pasha-AutoBattler"):
			direct_signal = false
			ModsConfigInterface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
			ModsConfigInterface.connect("setting_changed", self, "on_setting_changed")
	
	if direct_signal:
		var options_node = $"/root/AutobattlerOptions"
		options_node.connect("setting_changed", self, "on_setting_changed")
	
	check_marker_params()
	check_smoother_params()

func on_setting_changed(setting_name:String, _value, _mod_name):
	if setting_name == "enable_ai_marker" or setting_name == "enable_autobattler":
		check_marker_params()
	if setting_name == "smoothing_speed" or setting_name == "enable_smoothing":
		check_smoother_params()

func check_marker_params():
	var options_node = $"/root/AutobattlerOptions"
	
	options_node.load_mod_options()
	
	var ai_enabled = options_node.enable_autobattler
	var ai_marker_enabled = options_node.enable_ai_marker
	
	if ai_enabled and ai_marker_enabled:
		ai_icon.show()
	else:
		ai_icon.hide()
	
func check_smoother_params():
	var options_node = $"/root/AutobattlerOptions"
	
	options_node.load_mod_options()
	
	var enable_smoothing = options_node.enable_smoothing
	var smoothing_speed = options_node.smoothing_speed

	$"/root/Main/Camera".smoothing_enabled = enable_smoothing 
	$"/root/Main/Camera".smoothing_speed = smoothing_speed 
