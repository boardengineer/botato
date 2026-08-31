extends HBoxContainer

signal color_changed(value)

onready var _label = $Label
onready var _rect = $ColorRect
onready var _picker = $Control/ColorPicker
onready var _picker_control = $Control
onready var _picker_outline = $Control/Button
onready var _picker_button = $Button

var container:Node


func _ready()->void :
	_rect.color = Color.aqua
	_picker.color = Color.aqua


func set_container(p_container:Node):
	container = p_container

	remove_child(_picker_control)
	container.add_child(_picker_control)


func set_color(color:String)->void :
	var new_color = Color(color)
	_picker.color = new_color
	_on_ColorPicker_color_changed(new_color)


func _on_ColorPicker_color_changed(color):
	_rect.color = color
	emit_signal("color_changed", color.to_html())


func _on_Button_pressed():
	_picker_control.rect_global_position.x = _rect.rect_global_position.x - _picker_outline.rect_size.x - get("custom_constants/separation")
	_picker_control.rect_global_position.y = _rect.rect_global_position.y - (_picker_outline.rect_size.y - rect_size.y) / 2

#	var controly = _picker_control.rect_global_position.y
#	var coontainery = get_parent().rect_size.y
#	var parnet = get_parent()
	container.show_picker(_picker_control, _picker_outline.rect_size)


