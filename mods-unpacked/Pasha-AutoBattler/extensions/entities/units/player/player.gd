extends "res://entities/units/player/player.gd"

var ai_icon_scene = preload("res://mods-unpacked/Pasha-AutoBattler/ui/AIScene.tscn")
var ai_icon
var ModsConfigInterface

func _ready():
	ai_icon = ai_icon_scene.instance()
	add_child(ai_icon)
	
	check_marker_params()
	check_smoother_params()
	
	var options_node = $"/root/AutobattlerOptions"
	options_node.connect("setting_changed", self, "on_setting_changed")


func on_setting_changed(_setting_name:String, _value, _mod_name):
	check_marker_params()
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
