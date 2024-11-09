extends "res://ui/menus/run/weapon_selection.gd"

var selector_button


func _ready():
	selector_button = _back_button.duplicate()
	selector_button.rect_position.x += _back_button.rect_size.x + 50
	selector_button.text = "SELECTING FOR"
	add_child(selector_button)
	update_select_button_for_player()
	CoopService.connect("selecting_player_changed", self, "update_select_button_for_player")
	


func update_select_button_for_player():
	var color : Color = CoopService.get_player_color(CoopService.current_player_index)
	var stylebox_theme = selector_button.get_stylebox("normal").duplicate()
	stylebox_theme.bg_color  = color
	
	selector_button.add_stylebox_override("normal", stylebox_theme)
