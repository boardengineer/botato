extends Node

const MOD_DIR = "Pasha-LovenseLink/"


func _init():
	var dir = ModLoaderMod.get_unpacked_dir() + MOD_DIR
	# One extension, UI-only. The service node is spawned from the menu
	# extension's _ready (the AutobattlerOptions pattern), and gameplay is
	# read by polling -- no gameplay scripts are extended, so a failure here
	# cannot take the AutoBattler down with it.
	ModLoaderMod.install_script_extension(dir + "extensions/ui/menus/pages/main_menu.gd")
