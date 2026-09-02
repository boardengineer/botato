extends Reference
# Shared mouse-driven co-op selection helpers, used by both the character-select
# and weapon-select screens (both extend BaseSelection). Static functions that
# operate on the selection node `sel` passed in. Autoload singletons (RunData,
# CoopService, Utils, FocusEmulatorSignal) are global identifiers and work here
# exactly as they do in the base scripts.

const OUTLINE_BORDER = 5


# A borderless-fill panel used to outline the active player's panel.
static func make_outline() -> Panel:
	var outline = Panel.new()
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.visible = false
	var sb = StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_width_left = OUTLINE_BORDER
	sb.border_width_right = OUTLINE_BORDER
	sb.border_width_top = OUTLINE_BORDER
	sb.border_width_bottom = OUTLINE_BORDER
	sb.border_color = Color(1, 1, 1)
	sb.set_corner_radius_all(4)
	outline.add_stylebox_override("panel", sb)
	return outline


# Keep the outline over the active player's panel, tinted with their color.
static func update_outline(sel, outline) -> void:
	if outline == null:
		return
	var idx = CoopService.current_player_index
	var panels = sel._get_panels()
	if not RunData.is_coop_run or idx < 0 or idx >= panels.size() or idx >= RunData.get_player_count():
		outline.visible = false
		return
	var panel = panels[idx]
	if panel == null or not panel.is_visible_in_tree():
		outline.visible = false
		return
	var rect = panel.get_global_rect()
	outline.rect_global_position = rect.position
	outline.rect_size = rect.size
	var sb = outline.get_stylebox("panel")
	if sb is StyleBoxFlat and CoopService.has_method("get_player_color"):
		sb.border_color = CoopService.get_player_color(idx)
	outline.visible = true


# If a left-click landed on a connected player's panel, make it the active slot.
# Returns true if a panel was hit (so the caller can mark the input handled).
static func try_panel_click(sel, event) -> bool:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT):
		return false
	if not RunData.is_coop_run:
		return false
	var mouse = sel.get_global_mouse_position()
	var panels = sel._get_panels()
	var count = RunData.get_player_count()
	for i in range(panels.size()):
		if i >= count:
			continue
		var panel = panels[i]
		if panel == null or not panel.is_visible_in_tree():
			continue
		if panel.get_global_rect().has_point(mouse):
			select_slot(sel, i)
			return true
	return false


# Make player_index the active slot and move its focus onto its inventory grid.
static func select_slot(sel, player_index: int) -> void:
	CoopService.current_player_index = player_index
	var inventories = sel._get_inventories()
	var inventory = inventories[player_index] if player_index < inventories.size() else inventories[0]
	var target = sel._latest_focused_element[player_index]
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		if inventory != null and inventory.get_child_count() > 0:
			target = inventory.get_child(0)
	if target != null:
		Utils.focus_player_control(target, player_index)


# Co-op normally disables mouse focus on the grid (base_selection ~148). Re-enable
# it and force every element clickable so the mouse can hover/pick.
static func enable_mouse_grid(sel, is_coop_run: bool) -> void:
	if not is_coop_run:
		return
	for inventory in sel._get_inventories():
		if inventory == null:
			continue
		inventory.mouse_focus_enabled = true
		for child in inventory.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_PASS


# True when 2+ players are connected, player 1 (slot 0) is a human, and every
# other slot is a bot -- a lone human commanding an all-bot team.
static func only_p1_is_human() -> bool:
	var count = CoopService.connected_players.size()
	if count < 2 or CoopService.is_bot_by_index.size() < count:
		return false
	if CoopService.is_bot_by_index[0]:
		return false
	for i in range(1, count):
		if not CoopService.is_bot_by_index[i]:
			return false
	return true


# In-game screens (shop, level-up, crate pickup) hold CoopService.listening_for_
# inputs false, which makes each FocusEmulator._input swallow the human's mouse
# clicks before the buttons see them. Keep it true while a lone human commands
# bots so the mouse works. Attribution is by bound player_index, so no routing is
# needed for the action buttons.
static func keep_mouse_enabled() -> void:
	if only_p1_is_human():
		CoopService.listening_for_inputs = true


# Advance the active-player focus to the next connected slot (wraps). Used by the
# in-run TAB cycling so a lone human can take over any player's panel. No-op unless
# a lone human is commanding bots.
static func cycle_focus() -> void:
	if not only_p1_is_human():
		return
	var count = CoopService.connected_players.size()
	if count < 2:
		return
	CoopService.current_player_index = (CoopService.current_player_index + 1) % count


# Position an outline Panel (from make_outline) over an arbitrary control, tinted
# with the given slot's player color. Hides it when the panel is gone. Used by the
# in-run screens (shop, level-up, HUD) that don't expose sel._get_panels().
static func update_outline_panel(outline, panel, idx: int) -> void:
	if outline == null:
		return
	if panel == null or not (panel is Control) or not panel.is_visible_in_tree() \
			or idx < 0 or idx >= RunData.get_player_count():
		outline.visible = false
		return
	var rect = panel.get_global_rect()
	outline.rect_global_position = rect.position
	outline.rect_size = rect.size
	var sb = outline.get_stylebox("panel")
	if sb is StyleBoxFlat and CoopService.has_method("get_player_color"):
		sb.border_color = CoopService.get_player_color(idx)
	outline.visible = true


# A raw mouse event carries no player (FocusEmulatorSignal == -1, then rejected).
# Point it at the given slot so the base handler assigns the pick to that player.
# A real emulator (keyboard/gamepad) event already carries its player, so leave it.
static func route_to(element, player_index: int) -> void:
	if RunData.is_coop_run and player_index >= 0 and FocusEmulatorSignal.get_player_index(element) < 0:
		FocusEmulatorSignal.set_expected_control(element, player_index)
