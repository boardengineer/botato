extends Button

var selected := false
var mouse_offset := Vector2.ZERO
var parent:Control

func _ready():
	parent = get_parent()

func _process(_delta):
	if selected:
		follow_mouse()

func follow_mouse():
	parent.rect_global_position = get_global_mouse_position() + mouse_offset


func _on_Button_button_down():
	selected = true
	mouse_offset = parent.rect_global_position - get_global_mouse_position()


func _on_Button_button_up():
	selected = false


func _on_Button_mouse_exited():
	release_focus()
