extends Node

const MOD_DIR = "Pasha-AutoBattler/"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init():
	dir = ModLoaderMod.get_unpacked_dir() + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"
	
	# Add extensions
	ModLoaderMod.install_script_extension(ext_dir + "main.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/movement_behaviors/player_movement_behavior.gd")
	ModLoaderMod.install_script_extension(ext_dir + "entities/units/player/player.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/pages/main_menu.gd")
	ModLoaderMod.add_translation(trans_dir + "autobattler_options.en.translation")
