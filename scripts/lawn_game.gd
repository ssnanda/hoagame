extends Panel
## Lawn measurement: line the marker up with the tallest blade and record the reading.
## The verdict happens on the case sheet; this is evidence gathering.

signal measured(reading: float, precise: bool)
signal closed

const LIMIT_IN := 6.0
const PPI := 30.0
const FIELD_SIZE := Vector2(560, 400)

var inches := 5.0
var who := ""

var _locked := false
var _reading := 1.0
var _field: Field
var _reading_label: Label


class Field extends Control:
	signal changed(reading: float)

	const PPI := 30.0
	var inches := 5.0
	var reading := 1.0
	var locked := false
	var blades: Array = []

	func setup(inch_value: float) -> void:
		inches = inch_value
		custom_minimum_size = Vector2(560, 400)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(inch_value * 1000.0)
		for j in 70:
			blades.append({"x": rng.randf_range(80.0, 540.0), "h": rng.randf_range(0.78, 1.0),
					"lean": rng.randf_range(-6.0, 6.0), "shade": rng.randf()})
		blades[0].h = 1.0

	func _gui_input(event: InputEvent) -> void:
		if locked:
			return
		var pos := Vector2.ZERO
		if event is InputEventMouseButton and event.pressed:
			pos = event.position
		elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			pos = event.position
		else:
			return
		reading = snappedf(clampf((size.y - 40.0 - pos.y) / PPI, 0.0, 12.0), 0.1)
		changed.emit(reading)
		queue_redraw()

	func _draw() -> void:
		var y0 := size.y - 40.0
		draw_rect(Rect2(0, 0, size.x, y0), Color("dff1ff"))
		draw_rect(Rect2(0, y0, size.x, 40.0), Color("5b3d2a"))
		# gnome: hidden once the grass outgrows him
		var gx := size.x - 110.0
		draw_rect(Rect2(gx - 14.0, y0 - 40.0, 28.0, 40.0), Color("3a6fd8"))
		draw_circle(Vector2(gx, y0 - 50.0), 13.0, Color("f2c29b"))
		draw_colored_polygon(PackedVector2Array([
				Vector2(gx - 15.0, y0 - 56.0), Vector2(gx, y0 - 92.0), Vector2(gx + 15.0, y0 - 56.0)]), Color("e0533d"))
		for b in blades:
			var bh: float = inches * PPI * b.h
			var bx: float = b.x
			draw_colored_polygon(PackedVector2Array([
					Vector2(bx - 6.0, y0 + 2.0), Vector2(bx + b.lean, y0 - bh), Vector2(bx + 6.0, y0 + 2.0)]),
					Color("2f9e57").lightened(float(b.shade) * 0.25))
		# ruler
		draw_rect(Rect2(14.0, y0 - 12.0 * PPI, 52.0, 12.0 * PPI), Color("f7e9b8"))
		draw_rect(Rect2(14.0, y0 - 12.0 * PPI, 52.0, 12.0 * PPI), Color("8a7a3a"), false, 2.0)
		for i in 13:
			var ty := y0 - i * PPI
			draw_line(Vector2(14.0, ty), Vector2(14.0 + (30.0 if i % 2 == 0 else 18.0), ty), Color("5a4f2a"), 2.0)
			if i % 2 == 0 and i > 0:
				draw_string(ThemeDB.fallback_font, Vector2(48.0, ty + 5.0), str(i),
						HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("5a4f2a"))
		var limit_y := y0 - 6.0 * PPI
		var x := 70.0
		while x < size.x - 20.0:
			draw_line(Vector2(x, limit_y), Vector2(x + 14.0, limit_y), Color("b3261e"), 2.0)
			x += 24.0
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 130.0, limit_y - 6.0), "LIMIT 6\"",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("b3261e"))
		# marker
		var my := y0 - reading * PPI
		var mc := Color("2f9e57") if locked else Color("ff8a00")
		draw_line(Vector2(66.0, my), Vector2(size.x - 40.0, my), mc, 4.0)
		draw_circle(Vector2(size.x - 28.0, my), 16.0, mc)


func setup(inch_value: float, resident: String) -> void:
	inches = inch_value
	who = resident


func _ready() -> void:
	custom_minimum_size = Vector2(620, 880)
	size = custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4ecd8")
	style.set_corner_radius_all(28)
	style.shadow_size = 12
	style.shadow_color = Color(0, 0, 0, 0.35)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	box.add_child(_label("LAWN MEASUREMENT — %s" % who, 24, Color("6b6b6b")))
	box.add_child(_label("Measure the tallest blade against the 6 inch limit.", 28, Color("1c1b1f")))
	box.add_child(_label("Drag the marker to the top of the grass, then record it. Precise readings count as evidence.", 20, Color("6b6b6b")))

	_field = Field.new()
	_field.setup(inches)
	_field.changed.connect(_on_reading)
	box.add_child(_field)

	_reading_label = _label("Reading: 1.0 in", 34, Color("1c1b1f"))
	_reading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_reading_label)

	var record_btn := _button("RECORD MEASUREMENT")
	record_btn.pressed.connect(_record)
	box.add_child(record_btn)
	var back_btn := _button("< BACK")
	back_btn.custom_minimum_size = Vector2(0, 64)
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.pressed.connect(func(): closed.emit())
	box.add_child(back_btn)


func _on_reading(value: float) -> void:
	_reading = value
	_reading_label.text = "Reading: %.1f in" % value


func _record() -> void:
	if _locked:
		return
	_locked = true
	_field.locked = true
	_field.queue_redraw()
	measured.emit(_reading, absf(_reading - inches) <= 0.6)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 84)
	btn.add_theme_font_size_override("font_size", 32)
	return btn
