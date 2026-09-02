extends CanvasLayer

# Always-on readout of who is steering.
#
# Shift+A only ever printed "ARBITER on" to the log file and the AI marker
# looks identical for both controllers, so while playing there was no way to
# tell which one you were feeling. That is not a cosmetic gap: a play session
# on 2026-08-19 spent 129 seconds on the field controller and 2 on the arbiter
# because the toggle was firing twice per press, and nothing on screen said so.

const MARGIN = 14
const COLOR_OFF = Color(0.65, 0.65, 0.65)
const COLOR_ARBITER = Color(0.40, 1.00, 0.55)
const COLOR_FIELD = Color(1.00, 0.78, 0.30)

var _label
var _options


func _ready():
	layer = 100                      # above the game HUD
	_label = Label.new()
	_label.set_position(Vector2(MARGIN, MARGIN))
	# Drop shadow: the arena floor is light and the pause menu is dark, and the
	# readout has to stay legible over both without a background panel.
	_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.9))
	_label.add_constant_override("shadow_offset_x", 1)
	_label.add_constant_override("shadow_offset_y", 1)
	add_child(_label)


func _process(_delta):
	if _options == null:
		_options = get_node_or_null("/root/AutobattlerOptions")
		if _options == null:
			return
	if _label == null:
		return

	if not _options.enable_autobattler:
		_apply("BOT OFF   shift+space", COLOR_OFF)
	else:
		_apply("BOT ON - ARBITER", COLOR_ARBITER)


# NOT named _set: that is an Object virtual (property setter) and overriding it
# with a different signature stops the script compiling, which silently takes
# main.gd's preload down with it and un-installs the whole extension.
func _apply(text: String, color: Color) -> void:
	if _label.text != text:
		_label.text = text
		_label.add_color_override("font_color", color)
