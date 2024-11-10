extends "res://ui/menus/run/coop_join_panel.gd"

onready var center_container = $ScrollContainer/CenterContainer

var _add_bot_button

func _ready():
	var only_child = center_container.get_child(0)
	center_container.remove_child(only_child)
	
	var item_container : VBoxContainer = VBoxContainer.new()
	item_container.alignment = BoxContainer.ALIGN_CENTER
	item_container.add_child(only_child)
		
	_add_bot_button = get_node("/root/CharacterSelection/BackButton").duplicate()
	_add_bot_button.visible = false
	
	for a_signal in _add_bot_button.get_signal_list():
		var conns = _add_bot_button.get_signal_connection_list(a_signal.name)
		for cur_conn in conns:
			_add_bot_button.disconnect(cur_conn.signal, cur_conn.target, cur_conn.method)
	
	_add_bot_button.connect("pressed", self, "_add_bot_button_pressed")
	_add_bot_button.text = "Add Bot"
	item_container.add_child(_add_bot_button)
	
	add_child(item_container)
	var scroller = ScrollContainer.new()


func update_indicators(connected_players:Array, connection_progress:Array) -> void:
	.update_indicators(connected_players, connection_progress)
	var are_main_join_instructions_showing: = connected_players.empty()
	
	var is_panel_for_next_player: = player_index == connected_players.size() + connection_progress.size()
	_add_bot_button.visible = not are_main_join_instructions_showing and is_panel_for_next_player


func _add_bot_button_pressed() -> void:
	if CoopService.connected_players.size() < 4:
		CoopService.current_player_index = CoopService.connected_players.size()
		CoopService._add_player(CoopService.connected_players.size(), CoopService.PlayerType.KEYBOARD_AND_MOUSE)
