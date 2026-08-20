extends "res://main.gd"

const AICanvas  = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ai_canvas.gd")
const AITelemetry = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ai_telemetry.gd")
const AIHud = preload("res://mods-unpacked/Pasha-AutoBattler/extensions/ai_hud.gd")

var canvas_layer
var ai_telemetry
var ai_hud

func _ready():
	canvas_layer = AICanvas.new()
	add_child(canvas_layer)
	ai_telemetry = AITelemetry.new()
	add_child(ai_telemetry)
	ai_hud = AIHud.new()
	add_child(ai_hud)

func free():
	remove_child(canvas_layer)
	.free()
