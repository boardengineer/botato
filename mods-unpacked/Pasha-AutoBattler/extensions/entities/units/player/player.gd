extends "res://entities/units/player/player.gd"


# Declare member variables here. Examples:
var ai_icon_scene = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/UI/AIScene.tscn")
var ai_icon
var ModsConfigInterface

# var a = 2
# var b = "text"


# Called when the node enters the scene tree for the first time.
func _ready():
	ai_icon = ai_icon_scene.instance()
	add_child(ai_icon)
	
	ModsConfigInterface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
	ModsConfigInterface.connect("setting_changed", self, "on_setting_changed")
	
	check_marker_params()
	check_smoother_params()

func on_setting_changed(setting_name:String, _value, _mod_name):
	if setting_name == "enable_ai_marker" or setting_name == "enable_autobattler":
		check_marker_params()
	if setting_name == "smoothing_speed" or setting_name == "enable_smoothing":
		check_smoother_params()
	

func check_marker_params():
	var ai_enabled = ModsConfigInterface.mod_configs["Pasha-AutoBattler"]["enable_autobattler"]
	var ai_marker_enabled = ModsConfigInterface.mod_configs["Pasha-AutoBattler"]["enable_ai_marker"]	
	if ai_enabled and ai_marker_enabled:
		ai_icon.show()
	else:
		ai_icon.hide()
	
func check_smoother_params():
	var enable_smoothing = ModsConfigInterface.mod_configs["Pasha-AutoBattler"]["enable_smoothing"]
	var smoothing_speed = ModsConfigInterface.mod_configs["Pasha-AutoBattler"]["smoothing_speed"]

	$"/root/Main/Camera".smoothing_enabled = enable_smoothing 
	$"/root/Main/Camera".smoothing_speed = smoothing_speed 
