extends ScrollContainer


signal setting_changed(setting_name, value, mod_name)

onready var mod_list_vbox = $VBoxContainer/MarginContainer/VBoxContainer
onready var color_pickers_container = $VBoxContainer/ColorPickersContainer
onready var info_popup_container = $VBoxContainer/CanvasLayer
onready var info_popup = $VBoxContainer/CanvasLayer/InfoPopup

var mods_config_interface
var components_hovered = 0


func _ready():
	mods_config_interface = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
	var mod_configs = mods_config_interface.mod_configs

	for mod_config_key in mod_configs.keys():
		_init_mod_config_ui(mod_configs[mod_config_key], mod_config_key)

	var _err_setting_changed = connect("setting_changed", mods_config_interface, "on_setting_changed")


func _init_mod_config_ui(mod_config:Dictionary, mod_name:String):
	if mod_config.empty():return

	var mod_config_container = VBoxContainer.new()
	mod_config_container.set("custom_constants/separation", 10)
	mod_list_vbox.add_child(mod_config_container)
	mod_list_vbox.move_child(mod_config_container, mod_list_vbox.get_child_count() - 2)

	var mod_config_label = Label.new()
	mod_config_label.set("custom_fonts/font", preload("res://resources/fonts/actual/base/font_26_outline.tres"))
	mod_config_label.text = mod_name
	mod_config_label.align = VBoxContainer.ALIGN_BEGIN
	mod_config_container.add_child(mod_config_label)

	var mod_config_values_container = VBoxContainer.new()
	mod_config_values_container.set("custom_constants/separation", 10)
	mod_config_container.add_child(mod_config_values_container)

	for config_key in mod_config.keys():
		var config_value = mod_config[config_key]
		var component = HBoxContainer.new()
		mod_config_values_container.add_child(component)

		if mod_config.has(config_key + "_title"):
			var title := Label.new()
			title.text = mod_config[config_key + "_title"]
			title.size_flags_horizontal = SIZE_EXPAND_FILL
			component.add_child(title)

		if config_key.begins_with("enum_"):
			# Catch everything starting with enum.
			# Without that the enum value can be recognized as one of the base types.
			if config_key.ends_with("_options"):
				var enum_value = mod_config[config_key.rstrip("_options")]
				var enum_options: Array = mod_config[config_key]
				_init_drop_down(component, mod_name, config_key, enum_value, enum_options)
		elif config_value is float:
			if (
				not config_key.ends_with("_max")
				and not config_key.ends_with("_min")
				and not config_key.ends_with("_step")
			):
				_setup_float_slider(component, mod_name, mod_config, config_key, config_value)

		elif config_value is bool:
			_init_bool_button(component, mod_name, config_key, config_value)

		elif config_value is String and mods_config_interface.is_color_string(config_value):
			_init_color_picker_button(component, mod_name, config_key, config_value, color_pickers_container)

		if component.get_child_count() > 0 and mod_config.keys().has(config_key + "_tooltip"):
			component.connect("mouse_entered", self, "on_mouse_entered", [component, mod_config[config_key + "_tooltip"]])
			component.connect("mouse_exited", self, "on_mouse_exited", [component])

		# I'm sure there is a better solution for this, but I can't think of something without rewriting all the _init stuff.
		if component.get_child_count() == 0:
			mod_config_values_container.remove_child(component)


func on_mouse_entered(component, tooltip) -> void:
	components_hovered += 1
	info_popup_container.show()
	info_popup.display(component, Text.text(tooltip))


func on_mouse_exited(_component) -> void:
	components_hovered -= 1
	if components_hovered == 0:
		info_popup_container.hide()


func _setup_float_slider(parent: Node, mod_name:String, mod_config:Dictionary, config_key:String, config_value:float):
	var min_value = min(config_value, 0.0)
	var max_value = max(config_value, 1.0 if min_value == 0.0 else 0.0)
	var step = 0.0
	var format = "percent"

	if (
		mod_config.has(config_key + "_max")
		and mod_config[config_key + "_max"] is float
	):
		max_value = mod_config[config_key + "_max"]

	if (
		mod_config.has(config_key + "_min")
		and mod_config[config_key + "_min"] is float
	):
		min_value = mod_config[config_key + "_min"]

	if (
		mod_config.has(config_key + "_step")
		and mod_config[config_key + "_step"] is float
	):
		step = mod_config[config_key + "_step"]

	if mod_config.has(config_key + "_format"):
		format = mod_config[config_key + "_format"]

	return _init_float_slider(parent, config_value, min_value, max_value, step, config_key, mod_name, format)


func _init_float_slider(
	parent: Node,
	current_value: float,
	min_value:float,
	max_value:float,
	step:float,
	config_key:String,
	mod_name:String,
	format:String
):
	var new_slider_option = preload("res://ui/menus/global/slider_option.tscn").instance()
	parent.add_child(new_slider_option)
	if step > 0.0: new_slider_option._slider.step = step
	new_slider_option._slider.max_value = max_value
	new_slider_option._slider.min_value = min_value

	new_slider_option._label.text = config_key.to_upper()

	new_slider_option._value.rect_min_size.x = 140

	new_slider_option.set_value(current_value)

	if format != "percent":
		new_slider_option._slider.disconnect("value_changed", new_slider_option, "_on_HSlider_value_changed")
		new_slider_option._slider.connect("value_changed", self, "_on_HSlider_value_changed", [new_slider_option, format])
		_on_HSlider_value_changed(current_value, new_slider_option, format)

	new_slider_option.connect("value_changed", self, "signal_setting_changed", [config_key, mod_name])

	return new_slider_option


func _on_HSlider_value_changed(value:float, component, format)->void :
	component._value.text = format % value
	component.emit_signal("value_changed", value)


func _init_bool_button(parent:Node, mod_name:String, config_key:String, config_value:bool):
	var new_bool_button = CheckButton.new()
	parent.add_child(new_bool_button)
	new_bool_button.size_flags_horizontal = SIZE_EXPAND_FILL
	new_bool_button.text = config_key.to_upper()
	new_bool_button.pressed = config_value

	new_bool_button.connect("toggled", self, "signal_setting_changed", [config_key, mod_name])

	return new_bool_button


func _init_color_picker_button(
	parent: Node,
	mod_name:String,
	config_key:String,
	config_value:String,
	container:Node
):
	var new_color_option = load("res://ui/menus/global/color_option.tscn").instance()
	new_color_option.size_flags_horizontal = SIZE_EXPAND_FILL
	parent.add_child(new_color_option)
	new_color_option.button_expand.text = config_key.to_upper()
	new_color_option._init_color(Color(config_value))

	new_color_option.connect("color_changed", self, "signal_color_picker_color_changed", [config_key, mod_name])

	return new_color_option


func _init_drop_down(parent: Node, mod_name: String, config_key: String, config_value, config_options: Array):
	var new_drop_down = OptionButton.new()
	parent.add_child(new_drop_down)

	for option in config_options:
		new_drop_down.add_item(option)

	new_drop_down.selected = config_options.find(config_value)

	new_drop_down.connect("item_selected", self, "signal_option_button_item_selected", [config_key.lstrip("enum_").rstrip("_options"), config_options, mod_name])

	return new_drop_down


func signal_setting_changed(value, setting_name:String, mod_name:String):
	emit_signal("setting_changed", setting_name, value, mod_name)


func signal_color_picker_color_changed(value: Color, setting_name:String, mod_name:String):
	emit_signal("setting_changed", setting_name, value.to_html(), mod_name)


func signal_option_button_item_selected(value: int, setting_name:String, options: Array, mod_name:String):
	emit_signal("setting_changed", setting_name, options[value], mod_name)
