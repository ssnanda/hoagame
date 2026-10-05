extends RefCounted
## Shared look for every panel: the same paper card, type sizes and buttons.

const INK := Color("1c1b1f")
const MUTED := Color("5b6670")
const PAPER := Color("f4ecd8")
const ACCENT := Color("2f4858")
const GOOD := Color("2f9e57")
const BAD := Color("b3261e")
const GOLD := Color("ffd36e")


static func panel_style(radius := 28) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(radius)
	style.shadow_size = 12
	style.shadow_color = Color(0, 0, 0, 0.35)
	return style


static func label(text: String, size := 22, color := INK, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", roundi(size * Settings.text_scale))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, size := 28, height := 76) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", size)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


## Check button readable on the paper card (the default theme text is white).
static func check(text: String, size := 24) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.custom_minimum_size = Vector2(0, 56)      # comfortable touch row
	c.add_theme_font_size_override("font_size", size)
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		c.add_theme_color_override(slot, INK)
	return c


static func section(text: String) -> Label:
	return label(text, 17, MUTED)


static func avatar(color: Color, initials: String, diameter := 52.0) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(diameter * 0.5))
	p.add_theme_stylebox_override("panel", style)
	var l := label(initials, int(diameter * 0.4), Color.WHITE, true)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A centered card with a title, a scrolling body and a pinned footer for buttons.
## Returns {root, body, footer}. Add `root` to the overlay; fill `body`/`footer`.
static func modal(host_size: Vector2, panel_size: Vector2, title: String) -> Dictionary:
	var root := Panel.new()
	root.add_theme_stylebox_override("panel", panel_style())
	root.size = panel_size
	root.position = ((host_size - panel_size) * 0.5).max(Vector2(12, 12))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	if title != "":
		column.add_child(label(title, 30, INK, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	return {"root": root, "body": body, "footer": footer}
