extends "res://ui/menus/run/character_selection.gd"

var selector_button 

func _ready():
	selector_button = _back_button.duplicate()
	selector_button.rect_position.x += _back_button.rect_size.x + 50
	selector_button.text = "SELECTING FOR"
	update_select_button_for_player()
	add_child(selector_button)
	print_debug("ready character selection")
	CoopService.connect("selecting_player_changed", self, "update_select_button_for_player")


func update_select_button_for_player():
	var color : Color = CoopService.get_player_color(CoopService.current_player_index)
	var stylebox_theme = selector_button.get_stylebox("normal")
	stylebox_theme.modulate_color  = color
	
	selector_button.add_stylebox_override("normal", stylebox_theme)


func _on_element_focused(element:InventoryElement, inventory_player_index:int) -> void:
	var player_index = FocusEmulatorSignal.get_player_index(element)
	var panel = _get_panels()[player_index]
	print_debug("is visible ", panel.visible, " player index ", player_index)
	if not panel.visible or player_index == CoopService.current_player_index:
		._on_element_focused(element, inventory_player_index)


func _on_element_pressed(element:InventoryElement, _inventory_player_index:int) -> void:
	FocusEmulatorSignal.override_player_index = true
	._on_element_pressed(element, _inventory_player_index)
	FocusEmulatorSignal.override_player_index = false
