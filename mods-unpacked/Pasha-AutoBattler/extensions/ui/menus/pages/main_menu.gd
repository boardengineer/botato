extends "res://ui/menus/pages/main_menu.gd"

const AutobattlerOptions = preload("res://mods-unpacked/Pasha-AutoBattler/autobattler_options.gd")

func _ready():
	# Create the singleton once. main_menu._ready runs on every return to the menu,
	# so without this guard each visit stacks another AutobattlerOptions node under
	# /root -- multiple _input handlers that all fire on Shift+Space, toggling the
	# flag once each (net zero) and generally corrupting the option state.
	if $"/root".has_node("AutobattlerOptions"):
		return
	var options_node = AutobattlerOptions.new()
	options_node.set_name("AutobattlerOptions")
	$"/root".add_child(options_node)
