extends Control
## Cinematic close-up for one encounter (see sim/encounters.gd and data/encounters.json).
## Letterboxed illustrated scene: house front, the resident, the inspector from behind
## and a handful of props. Plays the lines, offers concise choices, then emits the choice.
## All drawing is code; no art assets.

signal finished(choice: Dictionary)

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const DrawUtil := preload("res://scripts/world/draw_util.gd")
const Encounters := preload("res://scripts/sim/encounters.gd")

const BAR := 92.0
const SKIN := [Color("f1c9a5"), Color("d9a27a"), Color("a8714e"), Color("7a4b32"), Color("f6d7bd")]
const SHIRT := [Color("c0504a"), Color("4a7fc0"), Color("5aa469"), Color("d6a23c"), Color("8b5db5"), Color("3d9aa6")]

var data: Dictionary = {}
var owner_name := ""
var extra: Dictionary = {}     ## extra {tokens} for line text, e.g. {favored}
var address := ""
var wall_color := Color("d9c7a3")
var roof_color := Color("7a4b3a")
var skin := SKIN[0]
var shirt := SHIRT[0]

var _t := 0.0
var _line := 0
var _scene_idx := 0         ## how far the staged action has progressed (drives props)
var _stage := "lines"        ## lines | choices | reply
var _shake := 0.0
var _text: Label
var _name: Label
var _box: Panel
var _choices: VBoxContainer
var _tap_hint: Label
var _typing: Tween
var _reply_lines: Array = []
var _picked: Dictionary = {}
var _scene_rect := Rect2()


func setup(encounter: Dictionary, owner: String, addr: String, seed_value: int, wall: Color, roof: Color, tokens: Dictionary = {}) -> void:
	extra = tokens
	data = encounter
	owner_name = owner
	address = addr
	wall_color = wall
	roof_color = roof
	skin = SKIN[seed_value % SKIN.size()]
	shirt = SHIRT[(seed_value / 5) % SHIRT.size()]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 55
	_scene_rect = Rect2(0.0, BAR, size.x, size.y * 0.70 - BAR)
	_box = Panel.new()
	_box.add_theme_stylebox_override("panel", UiKit.panel_style(22))
	_box.position = Vector2(20.0, size.y * 0.70 + 12.0)
	_box.size = Vector2(size.x - 40.0, 180.0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_name = UiKit.label("", 20, UiKit.MUTED)
	_name.position = Vector2(22.0, 10.0)
	_name.size = Vector2(_box.size.x - 44.0, 26.0)
	_box.add_child(_name)
	_text = UiKit.label("", 29, UiKit.INK)
	_text.position = Vector2(22.0, 40.0)
	_text.size = Vector2(_box.size.x - 44.0, 130.0)
	_box.add_child(_text)
	_tap_hint = UiKit.label("TAP TO CONTINUE", 16, UiKit.MUTED)
	_tap_hint.position = Vector2(_box.size.x - 200.0, _box.size.y - 30.0)
	_tap_hint.size = Vector2(180.0, 24.0)
	_tap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_box.add_child(_tap_hint)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	_choices.position = Vector2(20.0, size.y * 0.70 + 130.0)
	_choices.size = Vector2(size.x - 40.0, size.y * 0.30 - 150.0)
	add_child(_choices)
	var skip := UiKit.button("SKIP", 20, 48)
	skip.position = Vector2(size.x - 128.0, 22.0)
	skip.size = Vector2(108.0, 48.0)
	skip.pressed.connect(_skip)
	add_child(skip)
	_show_line()
	Sfx.play("notify")
	if str(data.get("tone", "")) in ["slapstick", "comic"]:
		_shake = 0.6


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(0.0, _shake - delta)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Touches arrive as emulated mouse clicks, so handling the mouse alone covers both.
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not pressed:
		return
	accept_event()
	if _stage == "choices":
		return
	if _typing != null and _typing.is_running():
		_typing.kill()
		_text.visible_ratio = 1.0
		return
	_advance()


func _skip() -> void:
	Sfx.play("tap")
	if _stage == "lines":
		_line = (data.lines as Array).size() - 1
		_show_line()
		if _typing != null:
			_typing.kill()
		_text.visible_ratio = 1.0
		_advance()
	elif _stage == "reply":
		_finish()


func _advance() -> void:
	if _stage == "lines":
		_line += 1
		if _line >= (data.lines as Array).size():
			_show_choices()
		else:
			_show_line()
	elif _stage == "reply":
		_line += 1
		if _line >= _reply_lines.size():
			_finish()
		else:
			_show_reply_line()


func _fill(text: String) -> String:
	return Encounters.fill(text, owner_name, address, extra)


func _say(who: String, text: String) -> void:
	match who:
		"resident":
			_name.text = owner_name.to_upper()
			_text.add_theme_color_override("font_color", UiKit.INK)
		"player":
			_name.text = "YOU"
			_text.add_theme_color_override("font_color", UiKit.ACCENT)
		_:
			_name.text = ""
			_text.add_theme_color_override("font_color", UiKit.MUTED)
	_text.text = _fill(text)
	_tap_hint.visible = true
	_text.visible_ratio = 0.0
	if _typing != null:
		_typing.kill()
	if Settings.reduce_motion:
		_text.visible_ratio = 1.0
		return
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, maxf(0.4, _text.text.length() * 0.018))


func _show_line() -> void:
	_scene_idx = _line
	var line: Dictionary = (data.lines as Array)[_line]
	_say(str(line.who), str(line.text))
	if str(data.get("tone", "")) in ["angry", "slapstick"] and str(line.who) != "narration":
		_shake = 0.35
		Sfx.play("bark" if "dog" in (data.get("props", []) as Array) and _line == 0 else "bad")
	if str(data.get("tone", "")) == "slapstick" and _line >= 2:
		_shake = 0.8
		Settings.haptic(40)


func _show_choices() -> void:
	_stage = "choices"
	_box.size.y = 112.0          # keep the last line visible above the replies
	_text.size.y = 64.0
	_text.add_theme_font_size_override("font_size", 22)
	_scene_idx = (data.lines as Array).size()
	_tap_hint.visible = false
	for opt: Dictionary in data.choices:
		var b := UiKit.button(_fill(str(opt.label)), 21, 50)
		b.pressed.connect(func():
			Sfx.play("tap")
			Settings.haptic(15)
			_pick(opt))
		_choices.add_child(b)


func _pick(opt: Dictionary) -> void:
	_picked = opt
	for child in _choices.get_children():
		child.queue_free()
	_reply_lines = [{"who": "player", "text": str(opt.get("reply", ""))}, {"who": "narration", "text": str(opt.get("result", ""))}]
	var footer := str(data.get("footer", ""))
	if footer != "":
		_reply_lines.append({"who": "narration", "text": footer})
	_stage = "reply"
	_line = 0
	_show_reply_line()


func _show_reply_line() -> void:
	var line: Dictionary = _reply_lines[_line]
	_say(str(line.who), str(line.text))


func _finish() -> void:
	_stage = "done"
	finished.emit(_picked)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var s := _scene_rect
	var tone := str(data.get("tone", "calm"))
	var wobble := Vector2.ZERO
	if _shake > 0.0 and not Settings.reduce_motion:
		wobble = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 9.0 * minf(_shake, 1.0)
	# Backdrop: sky, lawn, then the scene clipped between the letterbox bars.
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var floor_y := s.end.y - 120.0
	draw_set_transform(wobble, 0.0, Vector2.ONE)
	draw_rect(s, Color("9ed3ee").lerp(Color("c9d5dd"), 0.6 if tone in ["angry", "tense"] else 0.0))
	draw_rect(Rect2(s.position.x, floor_y - 40.0, s.size.x, s.end.y - floor_y + 40.0), Color("6fae5e"))
	draw_rect(Rect2(s.position.x, floor_y + 34.0, s.size.x, s.end.y - floor_y - 34.0), Color("4a5160"))
	draw_rect(Rect2(s.position.x, floor_y + 28.0, s.size.x, 8.0), Color("b8b2a4"))
	for lane in range(0, int(s.size.x), 80):
		draw_rect(Rect2(lane + fposmod(_t * 10.0, 80.0), floor_y + 92.0, 40.0, 4.0), Color(1, 1, 1, 0.35))
	_house(s, floor_y)
	var show_props := _visible_props()
	_props_back(show_props, s, floor_y)
	_inspector(Vector2(s.size.x * 0.2, floor_y + 24.0), show_props)
	var pose := str(data.get("pose", "idle"))
	if tone == "slapstick" and _scene_idx >= 2:
		pose = "yelling"
	_figure(Vector2(s.size.x * 0.64, floor_y + 14.0), 2.4, pose, shirt, skin, tone)
	_props_front(show_props, s, floor_y)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Letterbox bars with the address.
	draw_rect(Rect2(0.0, 0.0, size.x, BAR), Color.BLACK)
	draw_rect(Rect2(0.0, s.end.y, size.x, size.y - s.end.y), Color(0.02, 0.03, 0.05))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(24.0, 52.0), address.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 180.0, 24, Color("ffd36e"))
	draw_string(font, Vector2(24.0, 78.0), tone.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.5))


func _visible_props() -> Array:
	var all: Array = data.get("props", [])
	if all.size() < 3:
		return all
	var lines: int = (data.lines as Array).size()
	var shown := mini(all.size(), 1 + int(floor(float(_scene_idx) * all.size() / maxf(lines, 1.0))))
	return all.slice(0, shown)


func _house(s: Rect2, floor_y: float) -> void:
	var w := s.size.x * 0.9
	var x0 := s.position.x + (s.size.x - w) * 0.5
	var top := floor_y - 330.0
	var wall := Rect2(x0, top + 40.0, w, floor_y - top - 40.0)
	draw_rect(wall, wall_color)
	for k in range(0, int(wall.size.y), 14):
		draw_line(Vector2(wall.position.x, wall.position.y + k), Vector2(wall.end.x, wall.position.y + k), wall_color.darkened(0.06), 1.0)
	draw_colored_polygon(PackedVector2Array([Vector2(x0 - 24.0, top + 44.0), Vector2(x0 + w * 0.5, top - 30.0), Vector2(x0 + w + 24.0, top + 44.0)]), roof_color)
	# Door (opens at the first line) and windows.
	var door := Rect2(x0 + w * 0.5 - 38.0, floor_y - 150.0, 76.0, 150.0)
	DrawUtil.rr(self, door, Color("5a3a28"), 6)
	draw_rect(Rect2(door.position + Vector2(8.0, 10.0), Vector2(60.0, 52.0)), Color("a8c9d6"))
	draw_circle(door.position + Vector2(62.0, 86.0), 4.0, Color("e5c46a"))
	for wx in [x0 + 36.0, x0 + w - 36.0 - 76.0]:
		var win := Rect2(wx, floor_y - 140.0, 76.0, 70.0)
		draw_rect(win, Color("a8c9d6"))
		draw_rect(win, Color("f4ecd8"), false, 4.0)
		draw_line(win.position + Vector2(38.0, 0.0), win.position + Vector2(38.0, 70.0), Color("f4ecd8"), 3.0)
	# A curtain that twitches: the neighbor-watch effect.
	var sway := sin(_t * 3.0) * 3.0
	draw_rect(Rect2(x0 + w - 36.0 - 76.0, floor_y - 140.0, 20.0 + sway, 70.0), Color(0.9, 0.5, 0.5, 0.55))
	# Hedge and mailbox for depth.
	for k in 6:
		DrawUtil.ellipse(self, Vector2(x0 + 10.0 + k * 38.0, floor_y - 6.0), 24.0, 18.0, Color("3d7f45"))


func _figure(feet: Vector2, k: float, pose: String, shirt_c: Color, skin_c: Color, tone: String) -> void:
	var bob := sin(_t * (9.0 if tone in ["angry", "slapstick"] else 3.0)) * (3.0 if tone != "calm" else 1.5)
	var base := feet + Vector2(0.0, -abs(bob) * 0.5)
	var hip := base + Vector2(0.0, -34.0 * k)
	var chest := hip + Vector2(0.0, -34.0 * k)
	var head := chest + Vector2(0.0, -24.0 * k)
	if pose == "laughing":
		head.y += bob
	# Legs and shadow.
	DrawUtil.ellipse(self, base + Vector2(0.0, 4.0), 30.0 * k * 0.6, 7.0 * k * 0.5, Color(0, 0, 0, 0.22))
	draw_rect(Rect2(hip + Vector2(-9.0 * k, 0.0), Vector2(7.0 * k, 34.0 * k)), Color("33445a"))
	draw_rect(Rect2(hip + Vector2(2.0 * k, 0.0), Vector2(7.0 * k, 34.0 * k)), Color("33445a"))
	# Torso.
	DrawUtil.rr(self, Rect2(chest + Vector2(-14.0 * k, 0.0), Vector2(28.0 * k, 36.0 * k)), shirt_c, int(8 * k))
	var hand_l := chest + Vector2(-20.0 * k, 32.0 * k)
	var hand_r := chest + Vector2(20.0 * k, 32.0 * k)
	var arm_w := 6.0 * k
	match pose:
		"arms_crossed":
			hand_l = chest + Vector2(10.0 * k, 16.0 * k)
			hand_r = chest + Vector2(-10.0 * k, 18.0 * k)
		"pointing":
			hand_l = chest + Vector2(-58.0 * k, -6.0 * k + sin(_t * 12.0) * 4.0)
		"pleading":
			hand_l = chest + Vector2(-4.0 * k, 10.0 * k)
			hand_r = chest + Vector2(4.0 * k, 10.0 * k)
		"filming":
			hand_r = chest + Vector2(-30.0 * k, -26.0 * k)
			hand_l = chest + Vector2(-26.0 * k, -22.0 * k)
		"yelling":
			hand_l = chest + Vector2(-34.0 * k, -26.0 * k + sin(_t * 10.0) * 8.0)
			hand_r = chest + Vector2(34.0 * k, -26.0 * k + cos(_t * 10.0) * 8.0)
		"shrug":
			hand_l = chest + Vector2(-34.0 * k, 4.0 * k + sin(_t * 3.0) * 2.0)
			hand_r = chest + Vector2(34.0 * k, 4.0 * k + sin(_t * 3.0) * 2.0)
		"laughing":
			hand_l = chest + Vector2(-8.0 * k, 26.0 * k)
			hand_r = chest + Vector2(8.0 * k, 26.0 * k)
		"waving":
			hand_r = chest + Vector2(30.0 * k, -24.0 * k + sin(_t * 9.0) * 8.0)
		"crying":
			hand_l = chest + Vector2(-8.0 * k, -22.0 * k)
			hand_r = chest + Vector2(8.0 * k, -22.0 * k)
		"celebrating":
			hand_l = chest + Vector2(-30.0 * k, -34.0 * k)
			hand_r = chest + Vector2(30.0 * k, -34.0 * k)
			head.y -= abs(sin(_t * 8.0)) * 8.0 * k
		"confused":
			hand_r = chest + Vector2(14.0 * k, -26.0 * k)
			hand_l = chest + Vector2(-20.0 * k, 28.0 * k)
		"running":
			hand_l = chest + Vector2(-24.0 * k, 10.0 * k + sin(_t * 16.0) * 14.0)
			hand_r = chest + Vector2(24.0 * k, 10.0 * k - sin(_t * 16.0) * 14.0)
	for pair in [[chest + Vector2(-13.0 * k, 6.0 * k), hand_l], [chest + Vector2(13.0 * k, 6.0 * k), hand_r]]:
		draw_line(pair[0], pair[1], shirt_c.darkened(0.12), arm_w)
		draw_circle(pair[1], arm_w * 0.65, skin_c)
	# Head and face.
	draw_circle(head, 17.0 * k, skin_c)
	draw_arc(head, 17.5 * k, PI * 1.05, PI * 1.95, 14, Color("4a3426"), 5.0 * k)
	var tilt := 0.0
	var eye_y := head.y - 2.0 * k
	for sx in [-1.0, 1.0]:
		draw_circle(Vector2(head.x + sx * 6.5 * k, eye_y), 1.9 * k, Color("1c1b1f"))
		if tone in ["angry", "tense"]:
			draw_line(Vector2(head.x + sx * 10.0 * k, eye_y - 11.0 * k), Vector2(head.x + sx * 3.0 * k, eye_y - 5.0 * k), Color("2b1c12"), 2.4 * k)
		elif tone == "pleading":
			draw_line(Vector2(head.x + sx * 10.0 * k, eye_y - 6.0 * k), Vector2(head.x + sx * 3.0 * k, eye_y - 9.0 * k), Color("2b1c12"), 2.0 * k)
		else:
			draw_line(Vector2(head.x + sx * 10.0 * k, eye_y - 8.0 * k), Vector2(head.x + sx * 3.0 * k, eye_y - 8.0 * k), Color("2b1c12"), 2.0 * k)
	var mouth := head + Vector2(0.0, 8.0 * k)
	if pose in ["yelling"] or (tone == "angry" and fmod(_t, 0.5) < 0.25):
		DrawUtil.ellipse(self, mouth, 5.5 * k, 4.5 * k, Color("5a1e1e"))
	elif pose == "crying":
		draw_arc(mouth + Vector2(0.0, 4.0), 5.0 * k, PI + 0.4, TAU - 0.4, 10, Color("5a1e1e"), 2.0 * k)
		for sx in [-1.0, 1.0]:
			var drop := fposmod(_t * 1.2 + sx, 1.0)
			draw_circle(Vector2(head.x + sx * 7.0 * k, eye_y + drop * 14.0 * k), 1.8 * k, Color("7ec8f0"))
	elif pose == "confused":
		draw_arc(mouth, 3.0 * k, 0.0, PI, 8, Color("5a1e1e"), 2.0 * k)
		draw_string(ThemeDB.fallback_font, head + Vector2(16.0 * k, -14.0 * k), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color("ffd36e"))
	elif pose in ["laughing", "celebrating"]:
		draw_arc(mouth + Vector2(0.0, -2.0 * k), 6.0 * k, 0.1, PI - 0.1, 10, Color("5a1e1e"), 2.5 * k)
	elif pose == "pleading":
		draw_arc(mouth + Vector2(0.0, 4.0 * k), 5.0 * k, PI + 0.4, TAU - 0.4, 10, Color("5a1e1e"), 2.0 * k)
	else:
		draw_line(mouth + Vector2(-4.0 * k, 0.0), mouth + Vector2(4.0 * k, 0.0), Color("5a1e1e"), 2.0 * k)
	if tone in ["angry", "tense"] and not Settings.reduce_motion:
		# Anger ticks above the head.
		var tick := head + Vector2(20.0 * k, -16.0 * k)
		for a in [0.0, 1.57]:
			draw_line(tick + Vector2.from_angle(a + 0.8) * 4.0 * k, tick + Vector2.from_angle(a + 0.8) * 10.0 * k, Color("e0533d"), 2.5)
	if pose == "filming":
		var phone := hand_r + Vector2(-6.0 * k, -14.0 * k)
		DrawUtil.rr(self, Rect2(phone, Vector2(11.0 * k, 20.0 * k)), Color("20252b"), 3)
		if fmod(_t, 1.0) < 0.6:
			draw_circle(phone + Vector2(5.0 * k, 3.0 * k), 2.2 * k, Color("e0533d"))


func _inspector(feet: Vector2, props: Array) -> void:
	var k := 2.0
	var down := "slapstick" == str(data.get("tone", "")) and _scene_idx >= 2
	if down or ("blanket" in props and _scene_idx >= 2):
		# Flat on the ground, cartoon stars circling.
		draw_set_transform(feet + Vector2(0.0, -18.0), PI * 0.5, Vector2.ONE)
		draw_rect(Rect2(Vector2(-18.0, -12.0), Vector2(36.0, 24.0)), Color("2f4858"))
		draw_set_transform(Vector2(feet.x - 12.0, feet.y - 6.0), 0.0, Vector2.ONE)
		for i in 3:
			var a := _t * 4.0 + i * 2.1
			draw_circle(Vector2(cos(a), sin(a) * 0.4) * 22.0 + Vector2(40.0, -40.0), 4.0, Color("ffd36e"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# Back view: dark blazer, clipboard.
	var hip := feet + Vector2(0.0, -34.0 * k)
	var chest := hip + Vector2(0.0, -34.0 * k)
	var head := chest + Vector2(0.0, -24.0 * k)
	DrawUtil.ellipse(self, feet + Vector2(0.0, 4.0), 18.0, 5.0, Color(0, 0, 0, 0.22))
	draw_rect(Rect2(hip + Vector2(-9.0 * k, 0.0), Vector2(7.0 * k, 34.0 * k)), Color("22303c"))
	draw_rect(Rect2(hip + Vector2(2.0 * k, 0.0), Vector2(7.0 * k, 34.0 * k)), Color("22303c"))
	DrawUtil.rr(self, Rect2(chest + Vector2(-14.0 * k, 0.0), Vector2(28.0 * k, 36.0 * k)), Color("2f4858"), int(8 * k))
	draw_circle(head, 17.0 * k, Color("4a3426"))
	DrawUtil.rr(self, Rect2(chest + Vector2(14.0 * k, 12.0 * k), Vector2(14.0 * k, 20.0 * k)), Color("e8d9a8"), 3)
	if "blanket" in props:
		pass


func _props_back(props: Array, s: Rect2, floor_y: float) -> void:
	if "neighbor" in props:
		_figure(Vector2(s.size.x * 0.92, floor_y + 6.0), 1.15, "yelling", Color("e5a3c4"), SKIN[2], "angry")
	if "leafblower" in props:
		var fx := s.size.x * 0.9
		_figure(Vector2(fx, floor_y + 6.0), 1.1, "idle", Color("d6a23c"), SKIN[1], "calm")
		draw_line(Vector2(fx - 20.0, floor_y - 30.0), Vector2(fx - 70.0, floor_y - 22.0), Color("3a3f45"), 7.0)
		for i in 8:
			var lp := Vector2(fx - 80.0 - fposmod(_t * 160.0 + i * 38.0, 260.0), floor_y - 26.0 + sin(_t * 8.0 + i) * 14.0)
			draw_circle(lp, 4.0, Color("d98b2b") if i % 2 == 0 else Color("b9532a"))
	if "van" in props:
		var arrive := clampf(_t * 0.7, 0.0, 1.0)
		var vx: float = lerpf(s.size.x + 160.0, s.size.x * 0.36, 1.0 - pow(1.0 - arrive, 3.0))
		var vy := floor_y + 112.0
		DrawUtil.rr(self, Rect2(vx - 100.0, vy - 78.0, 200.0, 74.0), Color("f1f1f1"), 8)   # van body
		DrawUtil.rr(self, Rect2(vx - 112.0, vy - 52.0, 40.0, 48.0), Color("e8e8e8"), 6)
		draw_rect(Rect2(vx - 106.0, vy - 48.0, 28.0, 20.0), Color("8fb7cf"))
		draw_rect(Rect2(vx - 60.0, vy - 56.0, 140.0, 8.0), Color("e0a02d"))
		draw_circle(Vector2(vx - 66.0, vy - 2.0), 14.0, Color("20252b"))
		draw_circle(Vector2(vx + 60.0, vy - 2.0), 14.0, Color("20252b"))


func _props_front(props: Array, s: Rect2, floor_y: float) -> void:
	if "police" in props or "ambulance" in props:
		var arrive := clampf(_scene_idx / 2.0, 0.0, 1.0)
		var px := lerpf(s.size.x + 140.0, s.size.x * 0.62, arrive)
		var py := floor_y + 112.0
		var white := "ambulance" in props
		draw_set_transform(Vector2(px, py), 0.0, Vector2(1.5, 1.5))
		DrawUtil.rr(self, Rect2(-90.0, -56.0, 180.0, 52.0), Color("f4f4f4") if white else Color("2b3a55"), 8)
		DrawUtil.rr(self, Rect2(-90.0, -30.0, 180.0, 26.0), Color("d94b45") if white else Color("f4f4f4"), 4)
		DrawUtil.rr(self, Rect2(-86.0, -52.0, 40.0, 20.0), Color("a8c9d6"), 3)
		draw_circle(Vector2(-52.0, -2.0), 12.0, Color("20252b"))
		draw_circle(Vector2(52.0, -2.0), 12.0, Color("20252b"))
		var flash := fmod(_t, 0.5) < 0.25
		draw_rect(Rect2(-28.0, -64.0, 24.0, 8.0), Color("e0533d") if flash else Color("3d7fe0"))
		draw_rect(Rect2(4.0, -64.0, 24.0, 8.0), Color("3d7fe0") if flash else Color("e0533d"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if "inflatable" in props:
		var ix: float = (fposmod(_t * 90.0, s.size.x + 200.0) - 100.0) if _scene_idx >= 1 else s.size.x * 0.82
		var iy: float = floor_y + 30.0 - absf(sin(_t * 3.0)) * 24.0
		DrawUtil.ellipse(self, Vector2(ix, iy), 36.0, 46.0, Color("7ee081"))
		draw_circle(Vector2(ix - 12.0, iy - 14.0), 5.0, Color.WHITE)
		draw_circle(Vector2(ix + 12.0, iy - 14.0), 5.0, Color.WHITE)
		draw_arc(Vector2(ix, iy - 4.0), 14.0, 0.2, PI - 0.2, 10, Color("20252b"), 3.0)
	if "tarp" in props:
		var tx := s.size.x * 0.46
		var ty := floor_y + 70.0
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 90.0, ty), Vector2(tx - 70.0, ty - 50.0), Vector2(tx + 60.0, ty - 56.0), Vector2(tx + 96.0, ty - 4.0), Vector2(tx + 40.0, ty + 8.0)]), Color("3d7fe0"))
		for k in 3:
			draw_line(Vector2(tx - 60.0 + k * 50.0, ty - 50.0), Vector2(tx - 66.0 + k * 50.0, ty), Color("2a5db0"), 3.0)
	if "chairs" in props:
		for k in 5:
			var cx := s.size.x * (0.34 + k * 0.1)
			var cy := floor_y + 40.0
			draw_rect(Rect2(cx - 14.0, cy - 18.0, 28.0, 6.0), Color("e0a02d"))
			draw_rect(Rect2(cx - 14.0, cy - 40.0, 6.0, 22.0), Color("e0a02d"))
			draw_line(Vector2(cx - 12.0, cy - 12.0), Vector2(cx - 12.0, cy + 6.0), Color("8a8f98"), 3.0)
			draw_line(Vector2(cx + 12.0, cy - 12.0), Vector2(cx + 12.0, cy + 6.0), Color("8a8f98"), 3.0)
	if "mud" in props:
		DrawUtil.ellipse(self, Vector2(s.size.x * 0.28, floor_y + 48.0), 60.0, 14.0, Color("6b4a35"))
		for k in 5:
			draw_circle(Vector2(s.size.x * 0.28 + k * 14.0 - 30.0, floor_y + 40.0 - fposmod(_t * 40.0 + k * 9.0, 30.0)), 3.0, Color("6b4a35"))
	if "mower" in props:
		var mx := fposmod(_t * 120.0, s.size.x + 160.0) - 80.0
		DrawUtil.rr(self, Rect2(mx - 30.0, floor_y + 28.0, 60.0, 34.0), Color("e07a1f"), 6)
		draw_circle(Vector2(mx - 20.0, floor_y + 64.0), 8.0, Color("20252b"))
		draw_circle(Vector2(mx + 20.0, floor_y + 64.0), 8.0, Color("20252b"))
		for k in 6:
			draw_circle(Vector2(mx - 40.0 - k * 10.0, floor_y + 52.0 + sin(_t * 12.0 + k) * 4.0), 3.0, Color("3f9e60"))
	if "car" in props:
		var arrive_c := clampf(_scene_idx / 2.0, 0.0, 1.0)
		var cx2 := lerpf(-200.0, s.size.x * 0.52, arrive_c)
		draw_set_transform(Vector2(cx2, floor_y + 112.0), 0.0, Vector2(1.5, 1.5))
		DrawUtil.rr(self, Rect2(-80.0, -48.0, 160.0, 44.0), Color("3a6fd8"), 12)
		DrawUtil.rr(self, Rect2(-40.0, -66.0, 80.0, 26.0), Color("bfe2f5"), 8)
		draw_circle(Vector2(-46.0, -2.0), 12.0, Color("20252b"))
		draw_circle(Vector2(46.0, -2.0), 12.0, Color("20252b"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if "sprinkler" in props:
		for ox in [s.size.x * 0.12, s.size.x * 0.3, s.size.x * 0.44]:
			var origin := Vector2(ox, floor_y + 52.0)
			draw_rect(Rect2(origin + Vector2(-5.0, -4.0), Vector2(10.0, 8.0)), Color("3a3f45"))
			for j in 12:
				var u := fposmod(_t * 1.6 + j * 0.083, 1.0)
				var p := origin + Vector2((u - 0.5) * 90.0 * (1.0 if int(ox) % 2 == 0 else -1.0), -sin(u * PI) * 74.0)
				draw_circle(p, 3.0, Color(0.55, 0.8, 1.0, 0.85))
	if "dog" in props:
		var run := fposmod(_t * 0.5, 1.4) - 0.2
		var dp := Vector2(lerpf(-60.0, s.size.x + 40.0, run), floor_y + 66.0 + sin(_t * 14.0) * 4.0)
		DrawUtil.ellipse(self, dp, 28.0, 14.0, Color("b3763e"))
		draw_circle(dp + Vector2(26.0, -8.0), 11.0, Color("b3763e"))
		draw_colored_polygon(PackedVector2Array([dp + Vector2(22.0, -16.0), dp + Vector2(30.0, -28.0), dp + Vector2(32.0, -12.0)]), Color("7a4a24"))
		draw_rect(Rect2(dp + Vector2(32.0, -10.0), Vector2(18.0, 12.0)), Color("e8d9a8"))
		for leg in 2:
			draw_line(dp + Vector2(-14.0 + leg * 24.0, 8.0), dp + Vector2(-14.0 + leg * 24.0 + sin(_t * 14.0 + leg * 2.0) * 10.0, 22.0), Color("7a4a24"), 5.0)
	if "blanket" in props and _scene_idx >= 2:
		var bp := Vector2(s.size.x * 0.2, floor_y + 28.0)
		draw_colored_polygon(PackedVector2Array([bp + Vector2(-46.0, 0.0), bp + Vector2(-30.0, -34.0), bp + Vector2(30.0, -34.0), bp + Vector2(52.0, 4.0),
				bp + Vector2(30.0, 12.0), bp + Vector2(-30.0, 12.0)]), Color("c9503f"))
		for stripe in 4:
			draw_line(bp + Vector2(-34.0 + stripe * 20.0, -30.0), bp + Vector2(-38.0 + stripe * 20.0, 8.0), Color("f4ecd8"), 3.0)
	if "phone" in props and str(data.get("pose", "")) != "filming":
		var rec := Vector2(s.size.x * 0.84, s.position.y + 30.0)
		draw_string(ThemeDB.fallback_font, rec, "● REC" if fmod(_t, 1.0) < 0.6 else "  REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("e0533d"))
