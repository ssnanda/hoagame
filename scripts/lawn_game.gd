extends Panel
## Lawn inspection: line the marker up with the tallest blade, lock the reading, then rule on it.

signal done(effects: Dictionary, points: int, correct: bool)

const LIMIT_IN := 6.0
const PPI := 30.0
const FIELD_SIZE := Vector2(560, 400)
const OPENERS := [
	"Is that a lawn or a hay farm? Measure it. The limit is 6 inches.",
	"I saw a rabbit go in and not come out. Please measure the grass.",
	"My property value is wilting. Check that lawn. Limit: 6 inches.",
	"It's technically a meadow, but not an approved one. Measure it.",
]
const FINE_OK := [
	"Fined. He mutters, 'It's a meadow, Karen.'",
	"Fine issued. A lawnmower is ordered, reluctantly.",
]
const SLIDE_OK := [
	"Left alone. The neighbor waves from a very short lawn.",
	"Dismissed. Nobody loves a tape measure.",
]

var inches := 5.0
var who := ""

var _locked := false
var _reading := 1.0
var _field: Field
var _reading_label: Label
var _lock_btn: Button
var _verdict_row: HBoxContainer
var _result: Label
var _next_btn: Button
var _pending: Array = []


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

	box.add_child(_label("LAWN INSPECTION — %s" % who, 24, Color("6b6b6b")))
	var complaint := _label(OPENERS[randi() % OPENERS.size()], 30, Color("1c1b1f"))
	box.add_child(complaint)
	box.add_child(_label("Drag to line the marker up with the tallest blade.", 22, Color("6b6b6b")))

	_field = Field.new()
	_field.setup(inches)
	_field.changed.connect(_on_reading)
	box.add_child(_field)

	_reading_label = _label("Reading: 1.0 in", 34, Color("1c1b1f"))
	_reading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_reading_label)

	_lock_btn = _button("LOCK MEASUREMENT")
	_lock_btn.pressed.connect(_lock)
	box.add_child(_lock_btn)

	_verdict_row = HBoxContainer.new()
	_verdict_row.add_theme_constant_override("separation", 16)
	_verdict_row.hide()
	box.add_child(_verdict_row)
	var fine_btn := _button("ISSUE FINE")
	fine_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fine_btn.pressed.connect(_rule.bind(true))
	_verdict_row.add_child(fine_btn)
	var slide_btn := _button("LET IT SLIDE")
	slide_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slide_btn.pressed.connect(_rule.bind(false))
	_verdict_row.add_child(slide_btn)

	_result = _label("", 28, Color("1c1b1f"))
	_result.hide()
	box.add_child(_result)
	_next_btn = _button("CONTINUE")
	_next_btn.hide()
	_next_btn.pressed.connect(func(): done.emit(_pending[0], _pending[1], _pending[2]))
	box.add_child(_next_btn)


func _on_reading(value: float) -> void:
	_reading = value
	_reading_label.text = "Reading: %.1f in" % value


func _lock() -> void:
	_locked = true
	_field.locked = true
	_field.queue_redraw()
	_lock_btn.hide()
	_verdict_row.show()
	_reading_label.text = "Measured %.1f in (limit %d)" % [_reading, int(LIMIT_IN)]


func _rule(fine: bool) -> void:
	var violation := inches > LIMIT_IN
	var correct := fine == violation
	var precise := absf(_reading - inches) <= 0.6
	var fx: Dictionary
	var pts: int
	var text: String
	if fine and violation:
		fx = {"budget": 8, "power": 6, "happiness": -6}
		pts = 100
		text = FINE_OK[randi() % FINE_OK.size()]
	elif not fine and not violation:
		fx = {"happiness": 6, "power": 2}
		pts = 100
		text = SLIDE_OK[randi() % SLIDE_OK.size()]
	elif fine:
		fx = {"budget": -10, "happiness": -14, "power": -6}
		pts = -75
		text = "Wrongful fine! The grass was only %.1f in. A lawyer is en route." % inches
	else:
		fx = {"happiness": -8, "power": -8}
		pts = -50
		text = "You let a hay farm slide. It was %.1f in. The neighbors noticed." % inches
	if correct and precise:
		pts += 50
		text += "\nPrecise measuring: +50"
	_verdict_row.hide()
	_result.text = "%s\n%s" % [text, _fx_text(fx)]
	_result.show()
	_next_btn.show()
	_pending = [fx, pts, correct]


func _fx_text(fx: Dictionary) -> String:
	var names := {"budget": "BUDGET", "happiness": "HAPPY", "power": "POWER"}
	var parts: Array = []
	for key in fx:
		parts.append("%s %+d" % [names[key], int(fx[key])])
	return "  ·  ".join(parts)


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
