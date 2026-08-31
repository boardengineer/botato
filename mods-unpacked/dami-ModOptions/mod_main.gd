extends Node



const MOD_DIR = "dami-ModOptions/"
const LOG_NAME = "dami-ModOptions"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init(_modLoader = ModLoader):
	ModLoaderLog.info("Init", LOG_NAME)
	dir = ModLoaderMod.get_unpacked_dir() + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"

	# Add interface
	_add_child_class()

	# Add extensions
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/title_screen/title_screen.gd")
	ModLoaderMod.install_script_extension(ext_dir + "ui/menus/ingame/pause_menu.gd")

	# Add localizations
	ModLoaderMod.add_translation(trans_dir + "modoptions_translations.en.translation")
	ModLoaderMod.add_translation(trans_dir + "modoptions_translations.fr.translation")


func _add_child_class():
	var ModsConfigInterface = load(dir + "mods_config_interface.gd").new()
	ModsConfigInterface.name = "ModsConfigInterface"
	add_child(ModsConfigInterface)
