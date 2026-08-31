extends "res://ui/menus/title_screen/title_screen.gd"

var option_tab = load("res://mods-unpacked/dami-ModOptions/mod_options_tab/mod_options_tab.tscn")

onready var menu_options = $Menus/MenuOptions


func _ready():
	var button_container = menu_options.get_node_or_null("Buttons/HBoxContainer2")
	var button_controller = menu_options.get_node_or_null("Buttons")

	var last_button_index = button_container.get_child_count() - 2

	var last_button = button_container.get_child(last_button_index)
	var mod_options_button = last_button.duplicate()
	mod_options_button.name = "ButtonModOptions"
	button_container.add_child_below_node(last_button, mod_options_button)
	mod_options_button.connect("pressed", button_controller, "_change_tab", [last_button_index])
	mod_options_button.text = "Mods"
	# load() not preload() so a decompiled build that hasn't imported the .stex still
	# parses this extension (the Mods tab works; only the button icon is skipped).
	var _mo_icon = load("res://mods-unpacked/dami-ModOptions/assets/mods_icon.png")
	if _mo_icon:
		mod_options_button.icon = _mo_icon
	button_controller.buttons_tab_np.push_back(mod_options_button.get_path())
	button_controller.tab_container.add_child(option_tab.instance())
	button_controller.buttons_tab.push_back(mod_options_button)
