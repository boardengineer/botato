extends "res://ui/menus/run/weapon_selection.gd"
# Mouse-driven co-op weapon selection, matching the character screen (shared logic
# in coop_mouse_select.gd):
#   * Click a player's panel to make that slot active (outlined in its color).
#   * Click a weapon in a player's inventory to pick it for them.
# The weapon screen has one inventory PER player with element signals bound to the
# inventory index, so a mouse pick routes to that column's player.
#
# It also keeps CoopService.listening_for_inputs true: the character screen runs
# with it on, but the weapon screen leaves it off, which makes each
# FocusEmulator._input swallow every mouse click before the weapon buttons or this
# node ever see it. It flips false naturally once all slots have picked.

const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")

var _active_outline = null


func _ready() -> void:
	._ready()
	_active_outline = Coop.make_outline()
	add_child(_active_outline)
	Coop.enable_mouse_grid(self, RunData.is_coop_run)
	if RunData.is_coop_run:
		CoopService.listening_for_inputs = true


func _input(event: InputEvent) -> void:
	._input(event)
	if Coop.try_panel_click(self, event):
		get_tree().set_input_as_handled()


func _process(delta: float) -> void:
	._process(delta)
	Coop.update_outline(self, _active_outline)
	if RunData.is_coop_run and not _all_selected():
		CoopService.listening_for_inputs = true


func _all_selected() -> bool:
	for i in range(RunData.get_player_count()):
		if not _has_player_selected[i]:
			return false
	return true


func _set_base_ui_player_count(count: int, is_coop_run: bool, initialize: bool = false) -> void:
	._set_base_ui_player_count(count, is_coop_run, initialize)
	Coop.enable_mouse_grid(self, is_coop_run)


func _on_element_pressed(element: InventoryElement, inventory_player_index: int) -> void:
	Coop.route_to(element, inventory_player_index)
	._on_element_pressed(element, inventory_player_index)


func _on_element_focused(element: InventoryElement, inventory_player_index: int, displayPanelData: bool = true) -> void:
	Coop.route_to(element, inventory_player_index)
	._on_element_focused(element, inventory_player_index, displayPanelData)
