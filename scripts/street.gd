extends Control
## Top-down vertical street. Hold a thumb anywhere (bottom-right works) and drag up/down
## to walk; houses glow as you pass, release to inspect the glowing one.

signal visit(house: int)

const HOUSE_COUNT := 6
const HOUSE_SPACING := 440.0
const HOUSE_MARGIN := 520.0
const WORLD_H := HOUSE_MARGIN * 2.0 + HOUSE_SPACING * (HOUSE_COUNT - 1)
const ROAD_HALF := 70.0
const WALK_W := 46.0
const HOUSE_W := 150.0
const HOUSE_D := 170.0
const YARD_GAP := 80.0
const WALK_SPEED := 380.0
const STICK_RANGE := 110.0
const DEADZONE := 0.12
const NEAR_DIST := 120.0
const TUFTS := 46
const INCH_PX := 4.5
const WALKER_K := 1.4
const JUNCTIONS := [WORLD_H * 0.34, WORLD_H * 0.68]
const ROOFS := [Color("c4543e"), Color("5b6f8f"), Color("8a6f56"), Color("4f7f6a")]
const QUIPS := [
	"No complaints here. Suspicious.",
	"Everything's up to code.",
	"A gnome stares back at me.",
	"All quiet. Too quiet.",
	"Nice flamingo. Compliant.",
	"Fresh mulch. No paperwork required.",
	"A sprinkler has excellent timing.",
	"The curtains moved. Neighborhood watch works.",
	"A dog objects to this inspection.",
]

var _player_y := WORLD_H - 260.0
var _player_x := 360.0
var _cam := 0.0
var _stick := Vector2.ZERO
var _anchor := Vector2.ZERO
var _finger := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _dragging := false
var _used := false
var _angle := 0.0
var _face := 0.0
var _phase := 0.0
var _time := 0.0
var _near := -1
var _moving := false
var _dusk := 0.0
var _gloom := 0.0
var _pins: Dictionary = {}
var _grass: Array = []
var _day_total := 1
var _day_done := 0
var _houses: Array = []
var _tufts: Array = []
var _trees: Array = []
var _cars: Array = []
var _bubble := ""
var _bubble_t := 0.0
var _dusk_tween: Tween
var _sb: StyleBoxFlat
var _walker_variant := 0
var _weather := 0
var _clouds: Array = []


func _ready() -> void:
	clip_contents = true
	_sb = StyleBoxFlat.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in HOUSE_COUNT:
		_houses.append({"roof": ROOFS[i % ROOFS.size()], "kind": i % 3})
		_grass.append(3.0)
	for j in TUFTS:
		_tufts.append({"x": rng.randf(), "y": rng.randf(), "h": rng.randf_range(0.6, 1.0), "a": rng.randf_range(-0.3, 0.3)})
	for side in [-1, 1]:
		var y := 120.0
		while y < WORLD_H:
			var blocked := false
			for i in HOUSE_COUNT:
				if _side(i) == side and absf(y - house_y(i)) < 150.0:
					blocked = true
			if not blocked:
				_trees.append({"side": side, "y": y, "off": rng.randf_range(16.0, 150.0), "r": rng.randf_range(24.0, 44.0),
						"tone": rng.randf_range(-0.12, 0.16), "phase": rng.randf_range(0.0, TAU)})
			y += rng.randf_range(105.0, 185.0)
	var car_cols := [Color("e0533d"), Color("3a6fd8"), Color("f2b632"), Color("e8e8ee"), Color("2f9e57")]
	for k in 9:
		_cars.append({"y": rng.randf_range(200.0, WORLD_H - 200.0), "side": -1 if k % 2 == 0 else 1,
				"col": car_cols[rng.randi() % car_cols.size()]})
	for k in 7:
		_clouds.append({"x": rng.randf_range(-100.0, 700.0), "y": rng.randf_range(30.0, 360.0),
				"speed": rng.randf_range(5.0, 13.0), "scale": rng.randf_range(0.7, 1.35)})
	GameState.stats_changed.connect(_sync_mood)
	_sync_mood()


func house_y(i: int) -> float:
	return WORLD_H - HOUSE_MARGIN - i * HOUSE_SPACING


func _side(i: int) -> int:
	return -1 if i % 2 == 0 else 1


func _house_c(i: int) -> Vector2:
	return Vector2(_road_x(house_y(i)) + _side(i) * (ROAD_HALF + WALK_W + YARD_GAP + HOUSE_W * 0.5), house_y(i))


func _road_x(wy: float) -> float:
	return size.x * 0.5 + sin(wy / 430.0) * 34.0 + sin(wy / 170.0) * 12.0


## pins: house index -> "lawn" | "card". grass: tall-grass height in inches per house.
func set_day(pins: Dictionary, grass: Array, completed := 0, saved_position = null) -> void:
	_pins = pins.duplicate()
	_grass = grass.duplicate()
	_day_total = maxi(pins.size(), 1)
	_day_done = int(completed)
	_walker_variant = (GameState.day - 1) % 4
	_weather = (GameState.day - 1) % 3
	if saved_position is Vector2 and saved_position.y >= 0.0:
		_player_y = clampf(saved_position.y, 140.0, WORLD_H - 140.0)
		_player_x = saved_position.x
	else:
		_player_x = _road_x(_player_y)
	_update_dusk()


func get_player_y() -> float:
	return _player_y


func get_player_position() -> Vector2:
	return Vector2(_player_x, _player_y)


func mark_done(house: int) -> void:
	_pins[house] = "done"
	_day_done += 1
	_update_dusk()


func _update_dusk() -> void:
	if _dusk_tween:
		_dusk_tween.kill()
	_dusk_tween = create_tween()
	_dusk_tween.tween_property(self, "_dusk", 0.85 * float(_day_done) / _day_total, 1.0)


func _sync_mood() -> void:
	var happy: float = float(GameState.stats.get("happiness", 50))
	var tw := create_tween()
	tw.tween_property(self, "_gloom", clampf((35.0 - happy) / 35.0, 0.0, 1.0), 0.8)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_used = true
			_anchor = event.position
			_finger = event.position
			_press_pos = event.position
			_stick = Vector2.ZERO
		else:
			_dragging = false
			_stick = Vector2.ZERO
			if event.position.distance_to(_press_pos) < 22.0:
				if not _tap_flag(event.position):
					_enter_near()
			else:
				_enter_near()
	elif event is InputEventMouseMotion and _dragging:
		_finger = event.position
		_stick = (_finger - _anchor).limit_length(STICK_RANGE) / STICK_RANGE


func _enter_near() -> void:
	if _near < 0:
		return
	var kind: String = _pins.get(_near, "")
	if kind == "lawn" or kind == "card":
		visit.emit(_near)
	else:
		_bubble = "Case closed." if kind == "done" else QUIPS[randi() % QUIPS.size()]
		_bubble_t = 2.2


func _tap_flag(pos: Vector2) -> bool:
	if pos.x >= size.x - 158.0 and pos.y <= 226.0:
		return true
	for i in HOUSE_COUNT:
		var kind: String = _pins.get(i, "")
		if kind != "lawn" and kind != "card":
			continue
		var pin := _house_c(i) - Vector2(0, _cam) + Vector2(0, -18.0)
		var house_rect := Rect2(pin - Vector2(HOUSE_W * 0.6, HOUSE_D * 0.6), Vector2(HOUSE_W * 1.2, HOUSE_D * 1.2))
		if pos.distance_to(pin) <= 72.0 or house_rect.has_point(pos):
			visit.emit(i)
			return true
	return false


func _process(delta: float) -> void:
	_time += delta
	_bubble_t = maxf(0.0, _bubble_t - delta)
	var move := _stick
	if not _dragging:
		move = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_action_just_pressed("ui_accept"):
			_enter_near()
	if move.length() > DEADZONE:
		var strength := (move.length() - DEADZONE) / (1.0 - DEADZONE)
		var velocity := move.normalized() * WALK_SPEED * strength
		_player_y = clampf(_player_y + velocity.y * delta, 140.0, WORLD_H - 140.0)
		_player_x += velocity.x * delta
		var road_center := _road_x(_player_y)
		var near_junction := false
		for jy in JUNCTIONS:
			if absf(_player_y - jy) < 105.0:
				near_junction = true
		var reach := size.x * 0.42 if near_junction else ROAD_HALF + WALK_W * 0.72
		_player_x = clampf(_player_x, road_center - reach, road_center + reach)
		_face = velocity.angle() + PI * 0.5
		_phase += delta * 10.0 * strength
		_moving = true
	else:
		_moving = false
	_angle = lerp_angle(_angle, _face, 1.0 - exp(-12.0 * delta))
	_cam = clampf(_player_y - size.y * 0.58, 0.0, maxf(0.0, WORLD_H - size.y))
	_near = -1
	var best := NEAR_DIST
	for i in HOUSE_COUNT:
		var d := absf(_player_y - house_y(i))
		if d < best:
			best = d
			_near = i
	queue_redraw()


func _on_screen(wy: float, margin := 260.0) -> bool:
	var sy := wy - _cam
	return sy > -margin and sy < size.y + margin


func _rr(rect: Rect2, color: Color, radius: int) -> void:
	_sb.bg_color = color
	_sb.set_corner_radius_all(radius)
	draw_style_box(_sb, rect)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	_draw_ground(w, h, cx)
	_draw_ambience(w, h)
	for car in _cars:
		if _on_screen(car.y):
			_draw_car(_road_x(car.y) + car.side * (ROAD_HALF - 24.0), car.y - _cam, car.col)
	for i in HOUSE_COUNT:
		if _on_screen(house_y(i), 320.0):
			_draw_yard(i)
	var sh := Vector2(18.0, 22.0) * (1.0 + _dusk * 1.2)
	for t in _trees:
		if _on_screen(t.y):
			var tc := Vector2(_road_x(t.y) + t.side * (ROAD_HALF + WALK_W + t.off + t.r), t.y - _cam)
			_ellipse(tc + sh * 0.9, t.r, t.r, Color(0, 0, 0, 0.18))
	for i in HOUSE_COUNT:
		if _on_screen(house_y(i), 320.0):
			_draw_house(i, sh)
	for t in _trees:
		if _on_screen(t.y):
			var sway := sin(_time * 1.3 + float(t.phase)) * 3.0
			var tc := Vector2(_road_x(t.y) + t.side * (ROAD_HALF + WALK_W + t.off + t.r) + sway, t.y - _cam)
			draw_line(tc + Vector2(0, 30.0), tc + Vector2(-sway * 0.4, -8.0), Color("6b4931"), 10.0, true)
			var g := Color("2f9e57").lightened(float(t.tone)).lerp(Color("1c5a3e"), _dusk * 0.7)
			_ellipse(tc, t.r, t.r * 0.9, g)
			_ellipse(tc + Vector2(-t.r * 0.28, -t.r * 0.2), t.r * 0.62, t.r * 0.58, g.lightened(0.12))
			_ellipse(tc + Vector2(t.r * 0.3, -t.r * 0.08), t.r * 0.48, t.r * 0.5, g.darkened(0.08))
	for i in HOUSE_COUNT:
		if _on_screen(house_y(i), 320.0):
			_draw_highlight(i)
			_draw_pin(i)
	_draw_walker(Vector2(_player_x, _player_y - _cam))
	if _dusk > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.1, 0.32, 0.4 * _dusk))
	if _gloom > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.25, 0.27, 0.32, 0.4 * _gloom))
	_draw_ui(w, h)


func _draw_ground(w: float, h: float, cx: float) -> void:
	var lawn := Color("58c27d").lerp(Color("2c7050"), _dusk * 0.7)
	draw_rect(Rect2(0, 0, w, h), lawn)
	var k := int(floor(_cam / 120.0))
	while k * 120.0 - _cam < h:
		if k % 2 == 0:
			draw_rect(Rect2(0, k * 120.0 - _cam, w, 120.0), Color(1, 1, 1, 0.045))
		k += 1
	var road := Color("3a4152").lerp(Color("22263a"), _dusk * 0.6)
	var walk := Color("d9dde3").lerp(Color("8f8aa8"), _dusk * 0.6)
	for junction in JUNCTIONS:
		var sy: float = float(junction) - _cam
		if sy > -100.0 and sy < h + 100.0:
			draw_rect(Rect2(0, sy - ROAD_HALF, w, ROAD_HALF * 2.0), road)
			draw_rect(Rect2(0, sy - ROAD_HALF - WALK_W, w, WALK_W), walk)
			draw_rect(Rect2(0, sy + ROAD_HALF, w, WALK_W), walk)
	_draw_road_band(-ROAD_HALF - WALK_W, ROAD_HALF + WALK_W, walk, h)
	_draw_road_band(-ROAD_HALF, ROAD_HALF, road, h)
	k = int(floor(_cam / 80.0))
	while k * 80.0 - _cam < h:
		var wy: float = k * 80.0
		var sy: float = wy - _cam
		var rc := _road_x(wy)
		draw_line(Vector2(rc, sy), Vector2(_road_x(wy + 40.0), sy + 40.0), Color("ffe08a", 0.7), 4.0)
		k += 1


func _draw_ambience(w: float, h: float) -> void:
	if _weather == 0:
		for cloud in _clouds:
			var x := fposmod(float(cloud.x) + _time * float(cloud.speed), w + 220.0) - 110.0
			var y := float(cloud.y) - fposmod(_cam * 0.08, h + 200.0)
			var s := float(cloud.scale)
			_ellipse(Vector2(x, y), 38.0 * s, 15.0 * s, Color(1, 1, 1, 0.12))
			_ellipse(Vector2(x + 28.0 * s, y + 3.0), 28.0 * s, 12.0 * s, Color(1, 1, 1, 0.1))
	elif _weather == 1:
		for i in 9:
			var x := fposmod(i * 97.0 + _time * (18.0 + i), w + 40.0) - 20.0
			var y := fposmod(i * 143.0 + _time * 28.0, h + 60.0) - 30.0
			draw_circle(Vector2(x, y), 3.0 + float(i % 3), Color("ffd36e", 0.35))
	else:
		for i in 3:
			var bx := fposmod(i * 240.0 + _time * (28.0 + i * 4.0), w + 100.0) - 50.0
			var by := 90.0 + i * 70.0 + sin(_time * 1.8 + i) * 18.0
			var wing := 5.0 + 4.0 * sin(_time * 8.0 + i)
			draw_arc(Vector2(bx - 7.0, by), wing, PI, TAU, 8, Color(0.1, 0.15, 0.2, 0.35), 2.0)
			draw_arc(Vector2(bx + 7.0, by), wing, PI, TAU, 8, Color(0.1, 0.15, 0.2, 0.35), 2.0)
func _draw_road_band(left: float, right: float, color: Color, h: float) -> void:
	var points := PackedVector2Array()
	var step := 28.0
	var sy := -step
	while sy <= h + step:
		points.append(Vector2(_road_x(_cam + sy) + left, sy))
		sy += step
	sy = h + step
	while sy >= -step:
		points.append(Vector2(_road_x(_cam + sy) + right, sy))
		sy -= step
	draw_colored_polygon(points, color)


func _draw_car(x: float, y: float, col: Color) -> void:
	_rr(Rect2(x - 20.0 + 5.0, y - 43.0 + 6.0, 40.0, 86.0), Color(0, 0, 0, 0.2), 12)
	_rr(Rect2(x - 20.0, y - 43.0, 40.0, 86.0), col.lerp(Color("111522"), _dusk * 0.4), 12)
	_rr(Rect2(x - 15.0, y - 24.0, 30.0, 16.0), Color("cfe9ff").lerp(Color("39455f"), _dusk * 0.6), 5)
	_rr(Rect2(x - 15.0, y + 12.0, 30.0, 12.0), Color("cfe9ff").lerp(Color("39455f"), _dusk * 0.6), 5)


func _yard_rect(i: int) -> Rect2:
	var cx := _road_x(house_y(i))
	var x0 := (cx + ROAD_HALF + WALK_W) if _side(i) > 0 else (cx - ROAD_HALF - WALK_W - YARD_GAP)
	return Rect2(x0, house_y(i) - 100.0 - _cam, YARD_GAP, 200.0)


func _draw_yard(i: int) -> void:
	var r := _yard_rect(i)
	var inches: float = _grass[i]
	var tall := clampf((inches - 3.0) / 7.0, 0.0, 1.0)
	_rr(r, Color("3f9e60").lerp(Color("b2b04a"), tall * 0.5).lerp(Color("1c5a3e"), _dusk * 0.5), 10)
	var base := Color("2f9e57").lerp(Color("1c5a3e"), _dusk * 0.7)
	for t in _tufts:
		var p := Vector2(r.position.x + 6.0 + t.x * (r.size.x - 12.0), r.position.y + 8.0 + t.y * (r.size.y - 12.0))
		var len: float = inches * INCH_PX * t.h
		for a in [-0.55, 0.0, 0.55]:
			var ang: float = a + t.a + sin(_time * 1.6 + p.y * 0.05) * 0.06
			draw_line(p, p + Vector2(sin(ang), -cos(ang)) * len, base.lightened(float(t.h) * 0.2 - 0.1), 2.0, true)


func _draw_house(i: int, sh: Vector2) -> void:
	var hs: Dictionary = _houses[i]
	var c := _house_c(i) - Vector2(0, _cam)
	var side := _side(i)
	var rect := Rect2(c.x - HOUSE_W * 0.5, c.y - HOUSE_D * 0.5, HOUSE_W, HOUSE_D)
	draw_rect(Rect2(rect.position + sh, rect.size), Color(0, 0, 0, 0.2))
	# porch + path toward the road
	var inner_x := c.x - side * HOUSE_W * 0.5
	_rr(Rect2(minf(inner_x, inner_x - side * 34.0), c.y - 18.0, 34.0, 36.0), Color("d8c6a3").lerp(Color("6c6280"), _dusk * 0.5), 4)
	var roof: Color = hs.roof
	roof = roof.lerp(Color("231c3c"), _dusk * 0.35)
	if hs.kind == 1:
		draw_rect(rect, roof.lightened(0.35))
		draw_rect(rect, roof.darkened(0.2), false, 4.0)
		_rr(Rect2(c.x - 22.0, c.y - 40.0, 44.0, 36.0), Color("9ed2f2").lerp(Color("ffd36e"), _dusk), 6)
		_rr(Rect2(c.x - 40.0 + 20.0 * -side, c.y + 22.0, 30.0, 30.0), Color("b8bdc8"), 4)
	else:
		draw_rect(Rect2(rect.position.x, rect.position.y, HOUSE_W * 0.5, HOUSE_D), roof.lightened(0.14))
		draw_rect(Rect2(c.x, rect.position.y, HOUSE_W * 0.5, HOUSE_D), roof.darkened(0.14))
		var ry := rect.position.y + 14.0
		while ry < rect.end.y - 6.0:
			draw_line(Vector2(rect.position.x, ry), Vector2(rect.end.x, ry), Color(0, 0, 0, 0.08), 2.0)
			ry += 16.0
		draw_line(Vector2(c.x, rect.position.y), Vector2(c.x, rect.end.y), roof.darkened(0.35), 3.0)
		draw_rect(Rect2(c.x - side * -34.0 - 10.0, rect.position.y + 18.0, 20.0, 22.0), Color("3b3f4f"))
	if _dusk > 0.05:
		_ellipse(c + Vector2(side * 30.0, 30.0), 20.0, 16.0, Color("ffd36e", 0.55 * _dusk))
	if hs.kind == 2:
		var fp := Vector2(inner_x - side * 52.0, c.y + 62.0)
		draw_line(fp, fp + Vector2(0, 14), Color("ff6fa5"), 2.0)
		_ellipse(fp, 7.0, 5.0, Color("ff6fa5"))
		draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -4), fp + Vector2(-5, -12), fp + Vector2(5, -12)]), Color("ffb36b"))


func _draw_highlight(i: int) -> void:
	if i != _near:
		return
	var c := _house_c(i) - Vector2(0, _cam)
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var rect := Rect2(c.x - HOUSE_W * 0.5, c.y - HOUSE_D * 0.5, HOUSE_W, HOUSE_D).grow(10.0 + pulse * 4.0)
	var active: bool = _pins.get(i, "") in ["lawn", "card"]
	var col := Color("ffd36e") if active else Color(1, 1, 1, 0.8)
	draw_rect(rect, Color(col, 0.12 + 0.08 * pulse))
	draw_rect(rect, Color(col, 0.95), false, 5.0)


func _draw_pin(i: int) -> void:
	if not _pins.has(i):
		return
	var kind: String = _pins[i]
	var active := kind != "done"
	var c := _house_c(i) - Vector2(0, _cam) + Vector2(0, -18.0 + (sin(_time * 3.0 + i) * 6.0 if active else 0.0))
	var col := Color("3fae6a") if kind == "lawn" else (Color("e0533d") if kind == "card" else Color("9aa4b2"))
	if active:
		_ellipse(c, 44.0 + sin(_time * 4.0) * 5.0, 44.0 + sin(_time * 4.0) * 5.0, Color(col, 0.25))
	_ellipse(c + Vector2(6, 8), 34.0, 34.0, Color(0, 0, 0, 0.2))
	_ellipse(c, 34.0, 34.0, col)
	match kind:
		"lawn":
			for k in 3:
				var bx := c.x - 14.0 + k * 14.0
				draw_colored_polygon(PackedVector2Array([
						Vector2(bx - 5.0, c.y + 14.0), Vector2(bx + (k - 1) * 3.0, c.y - 16.0 - (k % 2) * 4.0),
						Vector2(bx + 5.0, c.y + 14.0)]), Color.WHITE)
		"card":
			draw_string(ThemeDB.fallback_font, c + Vector2(-30.0, 16.0), "!",
					HORIZONTAL_ALIGNMENT_CENTER, 60.0, 46, Color.WHITE)
		_:
			draw_polyline(PackedVector2Array([c + Vector2(-14, 2), c + Vector2(-4, 13), c + Vector2(15, -11)]),
					Color.WHITE, 6.0, true)


func _draw_walker(pos: Vector2) -> void:
	var swing := sin(_phase) if _moving else 0.0
	var bob := absf(cos(_phase)) * -3.5 if _moving else sin(_time * 2.0) * 0.8
	var k := WALKER_K * (1.0 + 0.03 * absf(sin(_phase))) if _moving else WALKER_K * (1.0 + 0.012 * sin(_time * 2.0))
	draw_set_transform(pos + Vector2(8, 10), _angle, Vector2(k * 1.2, k))
	_ellipse(Vector2.ZERO, 20.0, 15.0, Color(0, 0, 0, 0.25))
	draw_set_transform(pos + Vector2(0, bob), _angle, Vector2(k, k))
	var suits := [Color("23304a"), Color("3f315f"), Color("28544b"), Color("65412f")]
	var skins := [Color("f2c29b"), Color("9b6547"), Color("d89b73"), Color("6f4635")]
	var hairs := [Color("2b2118"), Color("141923"), Color("80552f"), Color("d7c2a1")]
	var suit: Color = suits[_walker_variant]
	var skin: Color = skins[_walker_variant]
	var hair: Color = hairs[_walker_variant]
	draw_circle(Vector2(-8, swing * 12.0 + 4.0), 6.5, Color("0d1220"))
	draw_circle(Vector2(8, -swing * 12.0 + 4.0), 6.5, Color("0d1220"))
	draw_line(Vector2(-16, 0), Vector2(-19, swing * 11.0 + 4.0), suit.lightened(0.1), 6.0, true)
	var hand := Vector2(19, -swing * 10.0 + 4.0)
	draw_line(Vector2(16, 0), hand, suit, 6.0, true)
	var case_bob := absf(swing) * 3.0
	draw_rect(Rect2(hand + Vector2(-1, -9 + case_bob), Vector2(12, 24)), Color("8a5a34"))
	_ellipse(Vector2(0, 0), 18.0, 11.0, suit)
	draw_line(Vector2(0, -6), Vector2(0, 6), Color("e0533d"), 3.0)
	draw_circle(Vector2(0, -2), 11.0, skin)
	draw_arc(Vector2(0, -2), 11.0, 0.0, PI, 14, hair, 7.0, true)
	if _walker_variant == 1:
		draw_line(Vector2(-8, -1), Vector2(8, -1), Color("20283a"), 2.0)
	elif _walker_variant == 2:
		draw_circle(Vector2(-5, -2), 2.0, Color("20283a"))
		draw_circle(Vector2(5, -2), 2.0, Color("20283a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _bubble_t > 0.0:
		var font := ThemeDB.fallback_font
		var tsize := font.get_string_size(_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var box := Rect2(pos.x - tsize.x * 0.5 - 16.0, pos.y - 100.0, tsize.x + 32.0, 52.0)
		box.position.x = clampf(box.position.x, 8.0, size.x - box.size.x - 8.0)
		_rr(box, Color.WHITE, 14)
		draw_string(font, box.position + Vector2(16.0, 36.0), _bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("1c1b1f"))


func _chevron(c: Vector2, up: bool, alpha: float) -> void:
	var d := -1.0 if up else 1.0
	draw_polyline(PackedVector2Array([c + Vector2(-16, -7 * d), c + Vector2(0, 7 * d), c + Vector2(16, -7 * d)]),
			Color(1, 1, 1, alpha), 5.0, true)


func _draw_ui(w: float, h: float) -> void:
	var font := ThemeDB.fallback_font
	_draw_map(Rect2(w - 158.0, 16.0, 142.0, 210.0))
	if _dragging:
		var knob := _anchor + (_finger - _anchor).limit_length(STICK_RANGE)
		draw_arc(_anchor, STICK_RANGE * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.28), 4.0, true)
		_chevron(_anchor + Vector2(0, -STICK_RANGE * 0.62 - 22.0), true, 0.5)
		_chevron(_anchor + Vector2(0, STICK_RANGE * 0.62 + 22.0), false, 0.5)
		draw_polyline(PackedVector2Array([_anchor + Vector2(-STICK_RANGE * 0.62 - 22.0, -16.0),
				_anchor + Vector2(-STICK_RANGE * 0.62 - 38.0, 0.0), _anchor + Vector2(-STICK_RANGE * 0.62 - 22.0, 16.0)]),
				Color(1, 1, 1, 0.5), 5.0, true)
		draw_polyline(PackedVector2Array([_anchor + Vector2(STICK_RANGE * 0.62 + 22.0, -16.0),
				_anchor + Vector2(STICK_RANGE * 0.62 + 38.0, 0.0), _anchor + Vector2(STICK_RANGE * 0.62 + 22.0, 16.0)]),
				Color(1, 1, 1, 0.5), 5.0, true)
		_ellipse(knob, 30.0, 30.0, Color(1, 1, 1, 0.6))
	elif not _used:
		var hc := Vector2(w - 90.0, h - 150.0)
		var bob := sin(_time * 3.0) * 8.0
		_chevron(hc + Vector2(0, -40.0 - bob), true, 0.8)
		_chevron(hc + Vector2(0, 40.0 + bob), false, 0.8)
		draw_string(font, hc + Vector2(-82.0, 8.0), "DRAG TO WALK", HORIZONTAL_ALIGNMENT_CENTER, 164.0, 23, Color(1, 1, 1, 0.9))
	var prompt := ""
	if _near >= 0:
		var kind: String = _pins.get(_near, "")
		prompt = "TAP FLAG TO INSPECT" if kind == "lawn" or kind == "card" else "CASE CLOSED"
	if prompt != "":
		var ts := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var box := Rect2(20.0, h - 72.0, ts.x + 32.0, 52.0)
		_rr(box, Color(0, 0, 0, 0.55), 14)
		draw_string(font, box.position + Vector2(16.0, 36.0), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("ffd36e"))


func _draw_map(rect: Rect2) -> void:
	_rr(rect, Color(0.04, 0.08, 0.12, 0.78), 16)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12.0, 25.0), "MAP",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d8edf6"))
	var inner := Rect2(rect.position + Vector2(10.0, 34.0), rect.size - Vector2(20.0, 44.0))
	var route := PackedVector2Array()
	for i in 25:
		var wy := WORLD_H * float(i) / 24.0
		var nx := clampf((_road_x(wy) - size.x * 0.25) / (size.x * 0.5), 0.0, 1.0)
		var ny := 1.0 - wy / WORLD_H
		route.append(inner.position + Vector2(nx * inner.size.x, ny * inner.size.y))
	draw_polyline(route, Color("b7bec8"), 8.0, true)
	for junction in JUNCTIONS:
		var my: float = inner.position.y + (1.0 - float(junction) / WORLD_H) * inner.size.y
		draw_line(Vector2(inner.position.x, my), Vector2(inner.end.x, my), Color("8e98a8"), 5.0, true)
	for house in _pins:
		var h := int(house)
		var hp := _house_c(h)
		var mx := inner.position.x + clampf((hp.x - size.x * 0.25) / (size.x * 0.5), 0.0, 1.0) * inner.size.x
		var my := inner.position.y + (1.0 - hp.y / WORLD_H) * inner.size.y
		var kind: String = _pins[house]
		var col := Color("7b8794") if kind == "done" else (Color("50c878") if kind == "lawn" else Color("ff6b5a"))
		draw_circle(Vector2(mx, my), 6.0, col)
	var px := inner.position.x + clampf((_player_x - size.x * 0.25) / (size.x * 0.5), 0.0, 1.0) * inner.size.x
	var py := inner.position.y + (1.0 - _player_y / WORLD_H) * inner.size.y
	draw_circle(Vector2(px, py), 7.0, Color("ffd36e"))
	draw_circle(Vector2(px, py), 10.0, Color("ffd36e", 0.35), false, 2.0)
