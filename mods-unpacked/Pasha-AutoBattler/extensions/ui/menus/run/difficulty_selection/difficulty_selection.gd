extends "res://ui/menus/run/difficulty_selection/difficulty_selection.gd"
# Mouse-driven danger selection when a lone human is commanding bots: click a
# danger level to pick it. Same fix as the character/weapon screens (shared logic
# in coop_mouse_select) -- enable mouse focus on the difficulty grid, keep
# CoopService.listening_for_inputs true (else the FocusEmulators swallow the
# click), and route the mouse pick to the active slot.

const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")


func _ready() -> void:
	._ready()
	Coop.enable_mouse_grid(self, RunData.is_coop_run)
	Coop.keep_mouse_enabled()
	# Character select leaves current_player_index wherever the F1 bot-add cycling
	# last put it (often a bot slot). Danger is a single shared choice driven by the
	# human, so default it back to the first player on entry.
	if Coop.only_p1_is_human():
		CoopService.current_player_index = 0


func _process(delta: float) -> void:
	._process(delta)
	Coop.keep_mouse_enabled()


func _set_base_ui_player_count(count: int, is_coop_run: bool, initialize: bool = false) -> void:
	._set_base_ui_player_count(count, is_coop_run, initialize)
	Coop.enable_mouse_grid(self, is_coop_run)


func _on_element_pressed(element: InventoryElement, inventory_player_index: int) -> void:
	Coop.route_to(element, CoopService.current_player_index)
	._on_element_pressed(element, inventory_player_index)


func _on_element_focused(element: InventoryElement, inventory_player_index: int, displayPanelData: bool = true) -> void:
	Coop.route_to(element, CoopService.current_player_index)
	._on_element_focused(element, inventory_player_index, displayPanelData)
