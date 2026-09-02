extends CanvasLayer
# In-arena highlight for the TAB-focused co-op player. A self-contained node added
# to Main so it never has to touch Main's _ready/_process chain.
# Each frame it outlines the focused player's HUD block (PlayerUIElements.hud_
# container), tinted with their color -- the same outline used on the menu screens.
# Only active for a lone human commanding bots; the shop / level-up screens draw
# their own outline and hide the arena HUD, so this one hides itself there.

const Coop = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ui/menus/run/coop_mouse_select.gd")

var _outline : Panel


func _ready() -> void:
	layer = 5   # above the game HUD ($UI/HUD), below full-screen menus
	_outline = Coop.make_outline()
	add_child(_outline)


func _process(_delta: float) -> void:
	if _outline == null:
		return
	var main = get_parent()
	if main == null or not ("_players_ui" in main) or not Coop.only_p1_is_human():
		_outline.visible = false
		return
	# Hide during the active battle -- the focus highlight is only useful for TAB
	# navigation between waves, and would just clutter combat. _wave_timer runs for
	# the wave's duration and is stopped once the wave ends.
	var wt = main._wave_timer if ("_wave_timer" in main) else null
	if wt != null and not wt.is_stopped():
		_outline.visible = false
		return
	var pi = CoopService.current_player_index
	var ui = main._players_ui
	if pi < 0 or pi >= ui.size() or ui[pi] == null:
		_outline.visible = false
		return
	Coop.update_outline_panel(_outline, ui[pi].hud_container, pi)
