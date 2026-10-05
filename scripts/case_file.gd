extends Panel
## Case sheet: PROPERTY, COMPLAINT, OBSERVATIONS, POSSIBLE VIOLATIONS, ACTION.
## Tick what you can support, then choose. Actions obey the HOA rules and say why
## when one is unavailable.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal ruled(action: String, cited: Array)
signal closed                       ## player backed out without ruling

const PANEL_SIZE := Vector2(640, 1000)
const ACTION_LABELS := {"dismiss": "DISMISS", "warning": "WARNING", "hearing": "HEARING", "fine": "FINE"}

var data: Dictionary = {}

var _checks: Array = []
var _buttons: Dictionary = {}
var _reason: Label


func setup(case_data: Dictionary) -> void:
	data = case_data


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	add_theme_stylebox_override("panel", UiKit.panel_style())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var back := UiKit.button("< BACK", 20, 60)
	back.custom_minimum_size = Vector2(140, 60)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): closed.emit())
	column.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	box.add_child(UiKit.section("PROPERTY"))
	box.add_child(UiKit.label(str(data.get("address", "")), 30, UiKit.INK))
	box.add_child(UiKit.label("%s · %s" % [str(data.get("owner", "")), str(data.get("relationship", "Neutral"))], 22, UiKit.ACCENT))
	if str(data.get("next", "")) != "":
		box.add_child(UiKit.label("NEXT: %s" % str(data.next), 18, UiKit.GOOD))
	var tags: Array = []
	if int(data.get("repeat_count", 0)) > 0:
		tags.append("REPEAT OFFENDER x%d" % int(data.repeat_count))
	if str(data.get("lot_type", "standard")) != "standard":
		tags.append(str(data.get("lot_type", "")).replace("_", " ").to_upper())
	if not tags.is_empty():
		box.add_child(UiKit.label(" · ".join(tags), 17, UiKit.BAD))
	var blurb := str(data.get("blurb", ""))
	if blurb != "":
		box.add_child(UiKit.label(blurb, 17, UiKit.MUTED))
	for line in data.get("history", []):
		box.add_child(UiKit.label(str(line), 16, UiKit.MUTED))

	box.add_child(HSeparator.new())
	box.add_child(UiKit.section("COMPLAINT · %s" % str(data.get("source", ""))))
	box.add_child(UiKit.label(str(data.get("text", "")), 24, UiKit.INK))
	var reliability := str(data.get("reliability", ""))
	if reliability != "":
		box.add_child(UiKit.label(reliability, 16, UiKit.MUTED))

	box.add_child(HSeparator.new())
	box.add_child(UiKit.section("OBSERVATIONS"))
	var photos: Array = data.get("photos", [])
	if photos.is_empty():
		box.add_child(UiKit.label("No photos on file. Use the camera at the property.", 19, UiKit.BAD))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		for tex in photos:
			var rect := TextureRect.new()
			rect.texture = tex
			rect.custom_minimum_size = Vector2(170, 118)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			row.add_child(rect)
		box.add_child(UiKit.label("Best photo quality %d%% · %d shot(s)" % [int(data.get("quality", 0)), int(data.get("shots", 0))], 17, UiKit.GOOD if int(data.get("quality", 0)) >= 70 else UiKit.MUTED))
	for note in data.get("observations", []):
		box.add_child(UiKit.label("• %s" % str(note), 18, UiKit.INK))

	box.add_child(HSeparator.new())
	box.add_child(UiKit.section("POSSIBLE VIOLATIONS · tick what you can support"))
	for v in data.get("violations", []):
		var suffix := ""
		if bool(v.get("documented", false)):
			suffix = "  [photo ✓]"
		elif bool(v.get("cleared", false)):
			suffix = "  [photo: nothing seen]"
		var check := UiKit.check("%s%s" % [str(v.label), suffix], 22)
		check.button_pressed = bool(v.get("documented", false))
		check.set_meta("id", str(v.id))
		check.toggled.connect(func(_on): _refresh_actions())
		box.add_child(check)
		if str(v.get("rule", "")) != "":
			box.add_child(UiKit.label("Rule: %s" % str(v.rule), 15, UiKit.MUTED))
		_checks.append(check)

	column.add_child(HSeparator.new())
	column.add_child(UiKit.section("ACTION"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	for action in ["dismiss", "warning", "hearing", "fine"]:
		var btn := UiKit.button(str(ACTION_LABELS[action]), 26, 70)
		btn.pressed.connect(_choose.bind(action))
		grid.add_child(btn)
		_buttons[action] = btn
	_reason = UiKit.label("", 16, UiKit.BAD)
	column.add_child(_reason)
	_refresh_actions()


func _cited() -> Array:
	var cited: Array = []
	for check in _checks:
		if (check as CheckButton).button_pressed:
			cited.append(str(check.get_meta("id")))
	return cited


func _refresh_actions() -> void:
	var options: Dictionary = (data.options_for as Callable).call(_cited()) if data.has("options_for") else {}
	var reasons: Array = []
	for action in _buttons:
		var option: Dictionary = options.get(action, {"enabled": true, "reason": ""})
		(_buttons[action] as Button).disabled = not bool(option.enabled)
		if not bool(option.enabled) and str(option.reason) != "" and not str(option.reason) in reasons:
			reasons.append("%s: %s" % [str(ACTION_LABELS[action]).capitalize(), str(option.reason)])
	_reason.text = "\n".join(reasons)
	# One procedurally sensible action gets the spotlight; the rest stay available but quiet.
	var recommended := "warning" if not _cited().is_empty() else "dismiss"
	for action in _buttons:
		var btn := _buttons[action] as Button
		if action == recommended and not btn.disabled:
			for state in ["normal", "hover", "pressed"]:
				var box := StyleBoxFlat.new()
				box.bg_color = UiKit.GOLD if state != "pressed" else UiKit.GOLD.darkened(0.15)
				box.set_corner_radius_all(14)
				btn.add_theme_stylebox_override(state, box)
			for slot in ["font_color", "font_hover_color", "font_pressed_color"]:
				btn.add_theme_color_override(slot, UiKit.INK)
		else:
			for state in ["normal", "hover", "pressed"]:
				btn.remove_theme_stylebox_override(state)
			for slot in ["font_color", "font_hover_color", "font_pressed_color"]:
				btn.remove_theme_color_override(slot)


func _choose(action: String) -> void:
	for btn in _buttons.values():
		(btn as Button).disabled = true
	ruled.emit(action, _cited() if action != "dismiss" else [])
