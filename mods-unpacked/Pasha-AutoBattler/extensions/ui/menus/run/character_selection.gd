extends "res://ui/menus/run/character_selection.gd"
# Mouse-driven co-op character selection (shared logic in coop_mouse_select.gd):
#   * Click a player's panel to make that slot active (outlined in its color).
#   * Click a character in the grid to pick it for the active slot.
#   * Each bot slot's panel carries its own AUTO-SHOP toggle (shopping + level-ups),
#     bound to CoopService.autoshop_by_index[slot], default on.

const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")

var _active_outline = null
var _panel_toggles: Array = []   # one AUTO-SHOP CheckButton per panel/slot


func _ready() -> void:
	._ready()
	_active_outline = Coop.make_outline()
	add_child(_active_outline)
	_build_panel_toggles()
	if not CoopService.is_connected("connected_players_updated", self, "_on_players_updated_autoshop"):
		var _e = CoopService.connect("connected_players_updated", self, "_on_players_updated_autoshop")
	_refresh_panel_toggles()


func _input(event: InputEvent) -> void:
	._input(event)
	# Select the player whose panel was clicked, but do NOT consume the event -- the
	# panel now hosts an AUTO-SHOP CheckButton that must still receive the click.
	Coop.try_panel_click(self, event)


func _process(delta: float) -> void:
	._process(delta)
	Coop.update_outline(self, _active_outline)


func _set_base_ui_player_count(count: int, is_coop_run: bool, initialize: bool = false) -> void:
	._set_base_ui_player_count(count, is_coop_run, initialize)
	Coop.enable_mouse_grid(self, is_coop_run)
	_refresh_panel_toggles()


func _on_element_pressed(element: InventoryElement, _inventory_player_index: int) -> void:
	Coop.route_to(element, CoopService.current_player_index)
	._on_element_pressed(element, _inventory_player_index)


func _on_element_focused(element: InventoryElement, inventory_player_index: int, displayPanelData: bool = true) -> void:
	# With bots present, don't let a hover disturb an already-confirmed character (a
	# click still changes it). The base clears only when nothing is confirmed, but
	# skip it outright here so the confirmed slot's highlight/panel stay put.
	if Coop.only_p1_is_human():
		var pi = FocusEmulatorSignal.get_player_index(element)
		if pi >= 0 and pi < _player_characters.size() and _player_characters[pi] != null:
			return
	Coop.route_to(element, CoopService.current_player_index)
	._on_element_focused(element, inventory_player_index, displayPanelData)


# --- Per-bot AUTO-SHOP toggle, hosted inside each player's panel --------------

func _build_panel_toggles() -> void:
	if not _panel_toggles.empty():
		return
	var panels = _get_panels()
	for i in range(panels.size()):
		var toggle = _make_toggle(i)
		_panel_toggles.append(toggle)
		var panel = panels[i]
		if toggle == null or panel == null:
			continue
		# Drop a labeled row into the panel's content column, at the top so it never
		# fights the character visual (which expands to fill the rest). The row's
		# visibility is what we show/hide; the switch inside stays visible.
		var host = panel.get_node("vboxContainer") if panel.has_node("vboxContainer") else panel
		var row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGN_CENTER
		row.visible = false
		var label = Label.new()
		label.text = "Auto-shop"
		row.add_child(label)
		row.add_child(toggle)
		host.add_child(row)
		host.move_child(row, 0)


func _make_toggle(slot: int) -> CheckButton:
	var toggle = CheckButton.new()
	toggle.focus_mode = Control.FOCUS_NONE   # keep it out of the co-op focus chain
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var _e = toggle.connect("toggled", self, "_on_panel_toggle_toggled", [slot])
	return toggle


func _on_players_updated_autoshop(_connected_players) -> void:
	_refresh_panel_toggles()


# Show the toggle only on connected bot slots, reflecting the slot's setting.
func _refresh_panel_toggles() -> void:
	var count = RunData.get_player_count()
	for i in range(_panel_toggles.size()):
		var toggle = _panel_toggles[i]
		if toggle == null:
			continue
		var is_bot = i < CoopService.is_bot_by_index.size() and CoopService.is_bot_by_index[i]
		var show = RunData.is_coop_run and is_bot and i < count
		if toggle.get_parent() != null:
			toggle.get_parent().visible = show   # the labeled row
		if show and i < CoopService.autoshop_by_index.size():
			toggle.pressed = CoopService.autoshop_by_index[i]


func _on_panel_toggle_toggled(button_pressed: bool, slot: int) -> void:
	if slot < CoopService.autoshop_by_index.size():
		CoopService.autoshop_by_index[slot] = button_pressed
