extends "res://ui/menus/run/coop_join_panel.gd"

var _new_bot_instructions : Label


func _ready():
	var new_container : VBoxContainer = VBoxContainer.new()
	var container_parent = _coop_join_instructions.get_parent()
	container_parent.remove_child(_coop_join_instructions)
	new_container.add_child(_coop_join_instructions)
	
	_new_bot_instructions = Label.new()
	_new_bot_instructions.text = "F1 To Add Botato"
	_new_bot_instructions.visible = false
	new_container.add_child(_new_bot_instructions)
	
	container_parent.add_child(new_container)

# Dupe the hiding/showing logic for the botato instructions
func update_indicators(connected_players:Array, connection_progress:Array)->void :
	var are_main_join_instructions_showing: = connected_players.empty()	
	var is_panel_for_next_player: = player_index == connected_players.size() + connection_progress.size()
	_new_bot_instructions.visible = not are_main_join_instructions_showing and is_panel_for_next_player
	.update_indicators(connected_players, connection_progress)
