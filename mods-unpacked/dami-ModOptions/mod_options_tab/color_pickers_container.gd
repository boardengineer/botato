extends Control


func _ready():
	var _err_hide = connect("hide", self, "hide_children")

func show_picker(picker:Control, picker_outline_rect:Vector2):
	var _visible = picker.visible
	hide_children()
	picker.visible = not _visible
	
	picker.rect_global_position.y = clamp(
		picker.rect_global_position.y,
		115, get_parent().rect_size.y - 80 - picker_outline_rect.y
	)

func hide_children():
	for child in get_children():
		child.hide()
