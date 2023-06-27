extends "res://main.gd"

const AICanvas  = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ai_canvas.gd")

var canvas_layer

func _ready():
	canvas_layer = AICanvas.new()
	add_child(canvas_layer)

func free():
	remove_child(canvas_layer)
	.free()
