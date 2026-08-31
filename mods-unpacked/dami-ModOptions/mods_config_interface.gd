class_name ModsConfigInterface
extends Node


signal setting_changed(setting_name, value, mod_name)

const LOG_NAME = "dami-ModOptions"

var mod_configs := {}
var color_regex := RegEx.new()

const COLOR_HEX_EXPRESSION = "#?([a-fA-F0-9]{2}){3,4}"


func _ready():
	ModLoaderLog.info("Loading mod configs", LOG_NAME)
	var _err_regex_compile = color_regex.compile(COLOR_HEX_EXPRESSION)
	var _nb_configs := 0

	for mod_id in ModLoaderStore.mod_data:
		var mod = ModLoaderStore.mod_data[mod_id]
		if mod.configs.empty():
			load_legacy_config(mod)
		else:
			load_config(mod)


func load_config(mod: ModData) -> void:
	var current_config := ModLoaderConfig.get_current_config(mod.dir_name)
	mod_configs[mod.dir_name] = flatten_properties(current_config if current_config else ModLoaderConfig.get_default_config(mod.dir_name))


func load_legacy_config(mod:ModData) -> void:
	var manifest_path = mod.get_required_mod_file_path(mod.required_mod_files.MANIFEST)
	var manifest_dict: = _ModLoaderFile.get_json_as_dict(manifest_path)

	if manifest_dict.extra.godot.has("config_defaults"):
		mod_configs[mod.dir_name] = manifest_dict.extra.godot.config_defaults

func _add_default_keys_if_needed(config:Dictionary, defaults:Dictionary):
	for default_key in defaults.keys():

		if not config.has(default_key):
			config[default_key] = defaults[default_key]


func on_setting_changed(setting_name:String, value, mod_name:String):
	var current_config = mod_configs[mod_name]
	current_config[setting_name] = value

#	TODO, something with this
#	for mod in ModLoader.mod_load_order:
#		if mod is ModData and mod.dir_name == mod_name:
#			mod.config = current_config

	emit_signal("setting_changed", setting_name, value, mod_name)


func flatten_properties(config: ModConfig) -> Dictionary:
	var result = {}
	var properties: Dictionary = config.schema.properties
	var config_data := config.data

	for key in properties:
		var value = properties[key]
		if value.has("tooltip"):
			result[key + "_tooltip"] = value.tooltip

		if value.type == "object":
			result.merge(flatten_properties(value.properties))
		elif value.has("enum"):
				result["enum_" + key] = config_data[key]
				result["enum_" + key + "_options"] = value.enum
		elif value.type == "number":
			result[key] = config_data[key]
			if value.has("maximum"):
				result[key + "_max"] = value.maximum
			if value.has("minimum"):
				result[key + "_min"] = value.minimum
			if value.has("multipleOf"):
				result[key + "_step"] = value.multipleOf
			if value.has("format"):
				result[key + "_format"] = value.format

		elif value.type == "boolean":
			result[key] = config_data[key]

		elif value.type == "string":
			if value.has("format") and value.format == "color":
				result[key] = config_data[key]
			elif not value.has("enum"):
				ModLoaderLog.warning(str("Unsupported string for key: ", key), LOG_NAME)
		else:
			ModLoaderLog.warning(str("Unsupported type for key: ", key), LOG_NAME)

		if value.has("title"):
			# TODO: Figure something better out here
			var key_prefix := "enum_" if value.has("enum") else ""
			var key_suffix := "_options" if value.has("enum") else ""
			result[ key_prefix + key + key_suffix + "_title"] = value.title

	return result


func is_color_string(setting_value:String) -> bool:

	var results = color_regex.search_all(setting_value)

	if results.size() > 0:
		var result = results.pop_front().get_string()
		if result == setting_value:
			return true

	return false


func get_settings(mod_name:String) -> Dictionary:
	if mod_configs.has(mod_name):
		return mod_configs[mod_name]
	else:
		return {}
