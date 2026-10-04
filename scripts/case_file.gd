extends Panel
## Case file for a complaint: tick the violations you are citing, then choose an
## action. Dismiss / warn / schedule a hearing / fine.

signal ruled(action: String, cited: Array)

const PANEL_SIZE := Vector2(620, 900)

var data: Dictionary = {}

var _checks: Array = []
var _buttons: Array = []


func setup(case_data: Dictionary) -> void:
	data = case_data


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4ecd8")
	style.set_corner_radius_all(28)
	style.shadow_size = 12
	style.shadow_color = Color(0, 0, 0, 0.35)
	add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	box.add_child(_label("CASE FILE · %s" % str(data.get("address", "")), 22, Color("6b6b6b")))
	box.add_child(_label(str(data.get("owner", "")), 30, Color("1c1b1f")))
	var tags: Array = [str(data.get("relationship", "neutral")).replace("_", " ").to_upper()]
	if int(data.get("repeat_count", 0)) > 0:
		tags.append("REPEAT x%d" % int(data.repeat_count))
	if str(data.get("lot_type", "")) != "standard":
		tags.append(str(data.get("lot_type", "")).replace("_", " ").to_upper())
	box.add_child(_label(" · ".join(tags), 18, Color("b3261e")))
	box.add_child(_label(str(data.get("text", "")), 24, Color("1c1b1f")))

	var quality := int(data.get("quality", 0))
	var evidence_text := "NO PHOTO ON FILE" if quality <= 0 else "PHOTO QUALITY %d%% · %d shot(s)" % [quality, int(data.get("shots", 1))]
	box.add_child(_label(evidence_text, 20, Color("2f9e57") if quality >= 70 else Color("b3261e")))
	box.add_child(HSeparator.new())
	box.add_child(_label("CITE (tick what you can support)", 18, Color("6b6b6b")))
	var documented: Array = data.get("documented", [])
	for violation in data.get("violations", []):
		var check := CheckButton.new()
		var note := "photo ✓" if str(violation.id) in documented else "no photo"
		check.text = "%s  (%s%s)" % [str(violation.label), note, ", borderline" if bool(violation.get("borderline", false)) else ""]
		check.button_pressed = true
		check.add_theme_font_size_override("font_size", 22)
		check.set_meta("id", str(violation.id))
		box.add_child(check)
		_checks.append(check)
	var history: Array = data.get("history", [])
	if not history.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(_label("HISTORY", 18, Color("6b6b6b")))
		for entry in history.slice(maxi(0, history.size() - 3)):
			box.add_child(_label("Day %d · %s" % [int(entry.get("day", 0)), str(entry.get("state", "")).replace("_", " ")],
					18, Color("425466")))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for spec in [["dismiss", "DISMISS"], ["warning", "WARNING"], ["hearing", "HEARING"], ["fine", "FINE"]]:
		var btn := Button.new()
		btn.text = str(spec[1])
		btn.custom_minimum_size = Vector2(0, 80)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 28)
		btn.pressed.connect(_choose.bind(str(spec[0])))
		grid.add_child(btn)
		_buttons.append(btn)


func _choose(action: String) -> void:
	for btn in _buttons:
		(btn as Button).disabled = true
	var cited: Array = []
	if action != "dismiss":
		for check in _checks:
			if (check as CheckButton).button_pressed:
				cited.append(str(check.get_meta("id")))
	ruled.emit(action, cited)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
