# Adds a "Lovense" button to the main menu and the settings popup behind it.
extends "res://ui/menus/pages/main_menu.gd"

const LovenseService = preload("res://mods-unpacked/Pasha-LovenseLink/lovense_service.gd")

var _lov_popup = null
var _lov_status = null
var _lov_addr = null
var _lov_horde_value = null
var _lov_mode_check = null
var _lov_hint = null


func _ready():
	# CHAIN CALL, NOT OPTIONAL. Mods load alphabetically, so this extension
	# sits ON TOP of Pasha-AutoBattler's, whose _ready is what spawns the
	# AutobattlerOptions node. Omit this line and the bot mod silently dies.
	._ready()
	if not $"/root".has_node("PashaLovense"):
		var svc = LovenseService.new()
		svc.set_name("PashaLovense")
		$"/root".call_deferred("add_child", svc)
	_lov_add_button()


func _lov_service():
	return $"/root".get_node_or_null("PashaLovense")


func _lov_add_button():
	# Duplicate a native button so theme, size and hover styling come along.
	# SCRIPTS + USE_INSTANCING but NOT SIGNALS: the scene wires CodexButton's
	# pressed to the codex handler, and copying that would open the codex on
	# top of our popup.
	var b = codex_button.duplicate(Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANCING)
	b.name = "LovenseButton"
	b.text = "Lovense"
	b.connect("pressed", self, "_on_lov_pressed")
	codex_button.get_parent().add_child(b)
	codex_button.get_parent().move_child(b, codex_button.get_index() + 1)


func _on_lov_pressed():
	if _lov_popup == null:
		_lov_build_popup()
	_lov_refresh()
	_lov_popup.popup_centered()
	var svc = _lov_service()
	if svc != null and svc.address != "":
		svc.probe()


func _lov_build_popup():
	_lov_popup = PopupPanel.new()
	_lov_popup.name = "LovensePopup"
	add_child(_lov_popup)

	var margin = MarginContainer.new()
	margin.set("custom_constants/margin_left", 24)
	margin.set("custom_constants/margin_right", 24)
	margin.set("custom_constants/margin_top", 16)
	margin.set("custom_constants/margin_bottom", 16)
	_lov_popup.add_child(margin)

	var box = VBoxContainer.new()
	box.set("custom_constants/separation", 12)
	box.rect_min_size = Vector2(560, 0)
	margin.add_child(box)

	var title = Label.new()
	title.text = "Lovense Link"
	box.add_child(title)

	_lov_status = Label.new()
	_lov_status.text = "idle"
	_lov_status.autowrap = true
	box.add_child(_lov_status)

	_lov_mode_check = CheckBox.new()
	_lov_mode_check.text = "Use PC Bluetooth (Intiface Central)"
	_lov_mode_check.connect("toggled", self, "_on_lov_mode")
	box.add_child(_lov_mode_check)

	var addr_row = HBoxContainer.new()
	addr_row.set("custom_constants/separation", 12)
	box.add_child(addr_row)
	var addr_label = Label.new()
	addr_label.text = "Address"
	addr_row.add_child(addr_label)
	_lov_addr = LineEdit.new()
	_lov_addr.size_flags_horizontal = SIZE_EXPAND_FILL
	_lov_addr.connect("text_entered", self, "_on_lov_addr")
	_lov_addr.connect("focus_exited", self, "_on_lov_addr_unfocus")
	addr_row.add_child(_lov_addr)

	_lov_hint = Label.new()
	_lov_hint.autowrap = true
	_lov_hint.rect_min_size = Vector2(560, 0)
	box.add_child(_lov_hint)

	var horde_row = HBoxContainer.new()
	horde_row.set("custom_constants/separation", 12)
	box.add_child(horde_row)
	var horde_label = Label.new()
	horde_label.text = "Full power at"
	horde_row.add_child(horde_label)
	var slider = HSlider.new()
	slider.min_value = 30
	slider.max_value = 300
	slider.step = 10
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.connect("value_changed", self, "_on_lov_horde")
	horde_row.add_child(slider)
	_lov_horde_value = Label.new()
	_lov_horde_value.text = "100 enemies"
	horde_row.add_child(_lov_horde_value)
	_lov_popup.set_meta("horde_slider", slider)

	var enabled_check = CheckBox.new()
	enabled_check.text = "Vibrate with enemies on screen"
	enabled_check.connect("toggled", self, "_on_lov_enabled")
	box.add_child(enabled_check)
	_lov_popup.set_meta("enabled_check", enabled_check)

	var buttons = HBoxContainer.new()
	buttons.set("custom_constants/separation", 12)
	box.add_child(buttons)
	var test = Button.new()
	test.text = "Test pulse"
	test.connect("pressed", self, "_on_lov_test")
	buttons.add_child(test)
	var connect_btn = Button.new()
	connect_btn.text = "Connect"
	connect_btn.connect("pressed", self, "_on_lov_connect")
	buttons.add_child(connect_btn)
	var close = Button.new()
	close.text = "Close"
	close.connect("pressed", _lov_popup, "hide")
	buttons.add_child(close)

	var svc = _lov_service()
	if svc != null and not svc.is_connected("status_changed", self, "_on_lov_status"):
		svc.connect("status_changed", self, "_on_lov_status")


func _lov_refresh():
	var svc = _lov_service()
	if svc == null:
		return
	_lov_addr.text = svc.address
	_lov_status.text = svc.status
	_lov_mode_check.pressed = svc.mode == LovenseService.MODE_WS
	_lov_popup.get_meta("horde_slider").value = svc.horde_size
	_lov_popup.get_meta("enabled_check").pressed = svc.enabled
	_lov_horde_value.text = "%d enemies" % int(svc.horde_size)
	_lov_update_hint()


func _lov_update_hint():
	if _lov_mode_check.pressed:
		_lov_hint.text = "Pair the device to this PC's Bluetooth in Intiface Central and start its server. Default address 127.0.0.1:12345."
	else:
		_lov_hint.text = "Lovense Remote app: Me > Settings > Game Mode, then enter the IP it shows (phone on this network). Lovense Connect on PC + dongle: 127.0.0.1."


# ------------------------------------------------------------- handlers --

func _on_lov_status(text):
	if _lov_status != null:
		_lov_status.text = text


func _on_lov_mode(pressed):
	var svc = _lov_service()
	if svc == null:
		return
	svc.set_mode(LovenseService.MODE_WS if pressed else LovenseService.MODE_HTTP)
	_lov_addr.text = svc.address
	_lov_update_hint()


func _on_lov_addr(text):
	var svc = _lov_service()
	if svc != null:
		svc.set_address(text)


func _on_lov_addr_unfocus():
	_on_lov_addr(_lov_addr.text)


func _on_lov_horde(value):
	var svc = _lov_service()
	if svc == null:
		return
	svc.horde_size = float(value)
	svc.save_config()
	_lov_horde_value.text = "%d enemies" % int(value)


func _on_lov_enabled(pressed):
	var svc = _lov_service()
	if svc == null:
		return
	svc.enabled = pressed
	svc.save_config()


func _on_lov_test():
	var svc = _lov_service()
	if svc != null:
		svc.test_pulse()


func _on_lov_connect():
	var svc = _lov_service()
	if svc == null:
		return
	svc.set_address(_lov_addr.text)
	svc.probe()
