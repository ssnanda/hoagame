extends Panel
## Draggable complaint card. Emits `swiped` after the fly-off animation.

signal swiped(side: String)

const SWIPE_THRESHOLD := 140.0

var data: Dictionary = {}
var home_pos := Vector2.ZERO

var _dragging := false
var _drag_start_x := 0.0
var _locked := false
var _who: Label
var _body: Label
var _hint: Label
var _left_btn: Button
var _right_btn: Button


func _ready() -> void:
	pivot_offset = size / 2.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4ecd8")
	style.set_corner_radius_all(28)
	style.shadow_size = 12
	style.shadow_color = Color(0, 0, 0, 0.35)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	_hint = _make_label(40, Color("b3261e"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate.a = 0.0
	box.add_child(_hint)

	_who = _make_label(26, Color("6b6b6b"))
	box.add_child(_who)

	_body = _make_label(38, Color("1c1b1f"))
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)

	var divider := HSeparator.new()
	box.add_child(divider)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	box.add_child(choices)
	_left_btn = _make_button()
	_left_btn.pressed.connect(fling.bind("left"))
	choices.add_child(_left_btn)
	_right_btn = _make_button()
	_right_btn.pressed.connect(fling.bind("right"))
	choices.add_child(_right_btn)


func setup(card_data: Dictionary, pos: Vector2) -> void:
	data = card_data
	home_pos = pos
	position = pos
	_who.text = str(data.get("who", ""))
	_body.text = str(data.get("text", ""))
	_left_btn.text = str(data.get("left", {}).get("label", "LET IT GO"))
	_right_btn.text = str(data.get("right", {}).get("label", "FLAG IT"))


## Programmatic swipe (keyboard / buttons / tests).
func fling(side: String) -> void:
	if _locked:
		return
	_locked = true
	_left_btn.disabled = true
	_right_btn.disabled = true
	_set_hint(-1.0 if side == "left" else 1.0)
	var dir := -1.0 if side == "left" else 1.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:x", home_pos.x + dir * 900.0, 0.25)
	tween.tween_property(self, "rotation", dir * 0.4, 0.25)
	tween.chain().tween_callback(func(): swiped.emit(side))


func _gui_input(event: InputEvent) -> void:
	if _locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start_x = get_global_mouse_position().x
		elif _dragging:
			_dragging = false
			_release()
	elif event is InputEventMouseMotion and _dragging:
		var dx := get_global_mouse_position().x - _drag_start_x
		position.x = home_pos.x + dx
		rotation = clampf(dx / 1500.0, -0.25, 0.25)
		_set_hint(dx / SWIPE_THRESHOLD)


func _release() -> void:
	var dx := position.x - home_pos.x
	if absf(dx) >= SWIPE_THRESHOLD:
		fling("left" if dx < 0.0 else "right")
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "position:x", home_pos.x, 0.15)
	tween.tween_property(self, "rotation", 0.0, 0.15)
	tween.tween_property(_hint, "modulate:a", 0.0, 0.15)


## strength: -1 = full left, +1 = full right.
func _set_hint(strength: float) -> void:
	var side := "left" if strength < 0.0 else "right"
	_hint.text = str(data.get(side, {}).get("label", ""))
	_hint.modulate.a = clampf(absf(strength), 0.0, 1.0)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 92)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 25)
	return button
