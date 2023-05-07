extends Node

const MOD_DIR = "Pasha-AutoBattler/"
const AnyWeapon_LOG = "Pasha-AutoBattler"

var dir = ""
var ext_dir = ""
var trans_dir = ""

func _init(modLoader = ModLoader):
	ModLoaderUtils.log_info("Init", AnyWeapon_LOG)
	dir = modLoader.UNPACKED_DIR + MOD_DIR
	ext_dir = dir + "extensions/"
	trans_dir = dir + "translations/"
	
	# Add extensions
	modLoader.install_script_extension(ext_dir + "main.gd")
	modLoader.install_script_extension(ext_dir + "entities/units/movement_behaviors/player_movement_behavior.gd")

	modLoader.add_translation_from_resource(trans_dir + "autobattler_options.en.translation")

