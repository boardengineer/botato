extends "res://ui/menus/pages/main_menu.gd"

const AutobattlerOptions = preload("res://mods-unpacked/Pasha-AutoBattler/autobattler_options.gd")

func _ready():
	var options_node = AutobattlerOptions.new()
	
	options_node.set_name("AutobattlerOptions")
	
	$"/root".add_child(options_node)
