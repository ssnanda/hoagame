extends Control
## Side-scrolling neighborhood. Tap or drag to walk; tap a house with a pin
## to walk there and emit `visit`. Sky runs morning -> dusk as the day's pins are cleared.

signal visit(house: int)

const HOUSE_COUNT := 6
const HOUSE_SPACING := 640.0
const HOUSE_MARGIN := 420.0
const WORLD_W := HOUSE_MARGIN * 2.0 + HOUSE_SPACING * (HOUSE_COUNT - 1)
const HOUSE_W := 220.0
const HOUSE_K := 2.2
const WALKER_K := 1.5
const WALK_SPEED := 320.0
const LAWN_H := 34.0
const WALK_H := 90.0
const BLADES := 36
const INCH_PX := 11.0
const FAR_PERIOD := 1400.0
const SKY_DAY_TOP := Color("5fb4f0")
const SKY_DAY_BOTTOM := Color("d8f0ff")
const SKY_DUSK_TOP := Color("3b2f6b")
const SKY_DUSK_BOTTOM := Color("ff9d6c")
const SUIT := Color("23304a")
const SKIN := Color("f2c29b")
const QUIPS := [
	"No complaints here. Suspicious.",
	"Everything's up to code.",
	"A gnome stares back at me.",
	"All quiet. Too quiet.",
	"Nice flamingo. Compliant.",
]

var _player_x := 260.0
var _target_x := 260.0
var _facing := 1.0
var _walking := false
var _phase := 0.0
var _cam := 0.0
var _time := 0.0
var _dusk := 0.0
var _gloom := 0.0
var _dragging := false
var _want_visit := -1
var _pins: Dictionary = {}
var _grass: Array = []
var _day_total := 1
var _day_done := 0
var _far: Array = []
var _houses: Array = []
var _blades: Array = []
var _bubble := ""
var _bubble_t := 0.0
var _ground_y := 400.0
var _dusk_tween: Tween
var _bubble_style: StyleBoxFlat


func _ready() -> void:
	clip_contents = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var x := 0.0
	while x < FAR_PERIOD:
		var w := rng.randf_range(70.0, 150.0)
		_far.append({"x": x, "w": w, "h": rng.randf_range(80.0, 230.0), "c": rng.randf()})
		x += w + rng.randf_range(0.0, 24.0)
	for i in HOUSE_COUNT:
		_houses.append({"h": rng.randf_range(95.0, 135.0), "hue": rng.randf(), "kind": i % 3})
		_grass.append(3.0)
	for j in BLADES:
		_blades.append({"x": ((j + rng.randf_range(0.1, 0.9)) / BLADES - 0.5) * HOUSE_W,
				"h": rng.randf_range(0.8, 1.0)})
	_blades[BLADES / 2].h = 1.0
	_bubble_style = StyleBoxFlat.new()
	_bubble_style.bg_color = Color.WHITE
	_bubble_style.set_corner_radius_all(14)
	_bubble_style.shadow_size = 6
	_bubble_style.shadow_color = Color(0, 0, 0, 0.25)
	GameState.stats_changed.connect(_sync_mood)
	_sync_mood()


func house_x(i: int) -> float:
	return HOUSE_MARGIN + i * HOUSE_SPACING


## pins: house index -> "lawn" | "card". grass: tall-grass height in inches per house.
func set_day(pins: Dictionary, grass: Array) -> void:
	_pins = pins.duplicate()
	_grass = grass.duplicate()
	_day_total = maxi(pins.size(), 1)
	_day_done = 0
	_want_visit = -1
	_update_dusk()


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
		_dragging = event.pressed
		if event.pressed:
			_press(event.position)
	elif event is InputEventMouseMotion and _dragging and _want_visit < 0:
		_target_x = clampf(_cam + event.position.x, 80.0, WORLD_W - 80.0)


func _press(pos: Vector2) -> void:
	var wx := _cam + pos.x
	_want_visit = -1
	_target_x = clampf(wx, 80.0, WORLD_W - 80.0)
	if pos.y > _ground_y + 40.0:
		return
	for i in HOUSE_COUNT:
		if absf(wx - house_x(i)) < HOUSE_W * HOUSE_K * 0.5:
			_want_visit = i
			_target_x = house_x(i)
			return


func _process(delta: float) -> void:
	_time += delta
	_bubble_t = maxf(0.0, _bubble_t - delta)
	var dist := _target_x - _player_x
	if absf(dist) > 4.0:
		_walking = true
		_facing = signf(dist)
		_player_x += _facing * minf(WALK_SPEED * delta, absf(dist))
		_phase += delta * 9.0
	else:
		_walking = false
		if _want_visit >= 0:
			_arrive()
	var want_cam := clampf(_player_x - size.x * 0.4, 0.0, maxf(0.0, WORLD_W - size.x))
	_cam = lerpf(_cam, want_cam, 1.0 - exp(-8.0 * delta))
	queue_redraw()


func _arrive() -> void:
	var i := _want_visit
	_want_visit = -1
	var kind: String = _pins.get(i, "")
	if kind == "lawn" or kind == "card":
		visit.emit(i)
	else:
		_bubble = "Case closed." if kind == "done" else QUIPS[randi() % QUIPS.size()]
		_bubble_t = 2.2


func _draw() -> void:
	var w := size.x
	var h := size.y
	_ground_y = maxf(h - 260.0, 320.0)
	_draw_sky(w)
	_draw_far(w)
	_draw_ground(w, h)
	_draw_houses(w)
	_draw_pins(w)
	_draw_car(w, h)
	_draw_walker()
	if _gloom > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.25, 0.27, 0.32, 0.45 * _gloom))


func _draw_sky(w: float) -> void:
	var top := SKY_DAY_TOP.lerp(SKY_DUSK_TOP, _dusk)
	var bottom := SKY_DAY_BOTTOM.lerp(SKY_DUSK_BOTTOM, _dusk)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, _ground_y), Vector2(0, _ground_y)]),
			PackedColorArray([top, top, bottom, bottom]))
	var sun := Vector2(w * 0.75, lerpf(110.0, _ground_y - 90.0, _dusk))
	var sun_col := Color("fff2b0").lerp(Color("ff7a45"), _dusk)
	for i in 4:
		draw_circle(sun, 120.0 - i * 18.0, Color(sun_col, 0.07))
	draw_circle(sun, 46.0, sun_col)
	for i in 4:
		var cx := fposmod(i * 330.0 + _time * (10.0 + i * 3.0) - _cam * 0.05, w + 300.0) - 150.0
		var cy := 70.0 + i * 55.0
		var cc := Color(1, 1, 1, lerpf(0.85, 0.25, _dusk))
		draw_circle(Vector2(cx, cy), 28.0, cc)
		draw_circle(Vector2(cx + 34.0, cy - 12.0), 36.0, cc)
		draw_circle(Vector2(cx + 74.0, cy), 28.0, cc)
		draw_rect(Rect2(cx, cy, 74.0, 28.0), cc)


func _draw_far(w: float) -> void:
	var off := fposmod(_cam * 0.25, FAR_PERIOD)
	var base := SKY_DAY_BOTTOM.lerp(SKY_DUSK_TOP, 0.35 + 0.4 * _dusk).darkened(0.12)
	for b in _far:
		var x: float = b.x - off
		while x < -b.w:
			x += FAR_PERIOD
		while x < w:
			draw_rect(Rect2(x, _ground_y - b.h, b.w, b.h), base.lerp(Color("7a8fb5"), b.c * 0.4))
			x += FAR_PERIOD


func _draw_ground(w: float, h: float) -> void:
	var gy := _ground_y
	var lawn := Color("58c27d").lerp(Color("2c7050"), _dusk * 0.7)
	draw_rect(Rect2(0, gy - 6.0, w, LAWN_H + 6.0), lawn)
	var walk_y := gy + LAWN_H
	var walk := Color("d9dde3").lerp(Color("8f8aa8"), _dusk * 0.6)
	draw_rect(Rect2(0, walk_y, w, WALK_H), walk)
	var joint := 160.0
	var x := -fposmod(_cam, joint)
	while x < w:
		draw_line(Vector2(x, walk_y), Vector2(x - 18.0, walk_y + WALK_H), walk.darkened(0.12), 2.0)
		x += joint
	var curb_y := walk_y + WALK_H
	draw_rect(Rect2(0, curb_y, w, 8.0), walk.lightened(0.15))
	var road := Color("3a4152").lerp(Color("22263a"), _dusk * 0.6)
	draw_rect(Rect2(0, curb_y + 8.0, w, h - curb_y - 8.0), road)
	var dash := 90.0
	var dx := -fposmod(_cam * 1.3, dash * 2.0)
	var ly := curb_y + 8.0 + (h - curb_y - 8.0) * 0.6
	while dx < w:
		draw_rect(Rect2(dx, ly, dash, 5.0), Color(1, 1, 1, 0.55))
		dx += dash * 2.0


func _draw_houses(w: float) -> void:
	for i in HOUSE_COUNT:
		var sx := house_x(i) - _cam
		if sx < -400.0 or sx > w + 400.0:
			continue
		draw_set_transform(Vector2(sx, _ground_y), 0.0, Vector2(HOUSE_K, HOUSE_K))
		_draw_house(_houses[i])
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_blades(sx, float(_grass[i]))
	# a few shrubs between houses
	for i in HOUSE_COUNT - 1:
		var sx := house_x(i) + HOUSE_SPACING * 0.5 - _cam
		if sx < -80.0 or sx > w + 80.0:
			continue
		var g := Color("3fae6a").lerp(Color("1f5e44"), _dusk * 0.7)
		draw_circle(Vector2(sx, _ground_y + 4.0), 34.0, g)
		draw_circle(Vector2(sx + 30.0, _ground_y + 12.0), 24.0, g.lightened(0.1))


func _draw_blades(sx: float, inches: float) -> void:
	var base_y := _ground_y + LAWN_H - 8.0
	var col := Color("2f9e57").lerp(Color("1c5a3e"), _dusk * 0.7)
	for b in _blades:
		var bx: float = sx + b.x * HOUSE_K
		var bh: float = inches * INCH_PX * b.h
		var lean := sin(_time * 1.5 + bx * 0.05) * 3.0
		draw_colored_polygon(PackedVector2Array([
				Vector2(bx - 5.0, base_y), Vector2(bx + lean, base_y - bh), Vector2(bx + 5.0, base_y)]),
				col.lightened(float(b.h - 0.8) * 0.6))


func _draw_house(hs: Dictionary) -> void:
	var wd := HOUSE_W
	var ht: float = hs.h
	var palette := [Color("f4ece1"), Color("cfe3f0"), Color("f2d4cc"), Color("d9e8d2")]
	var body: Color = palette[int(hs.hue * 4.0) % 4].lerp(Color("5a4f7a"), _dusk * 0.4)
	var roof := Color("34405e").lerp(Color("231c3c"), _dusk * 0.5)
	var left := -wd * 0.5
	var top := -ht
	draw_rect(Rect2(left - 4.0, -4.0, wd + 8.0, 8.0), Color(0, 0, 0, 0.12))
	draw_rect(Rect2(left, top, wd, ht), body)
	if hs.kind == 1:
		draw_rect(Rect2(left - 10.0, top - 14.0, wd + 20.0, 14.0), roof)
	else:
		draw_colored_polygon(PackedVector2Array([
				Vector2(left - 12.0, top), Vector2(0.0, top - 52.0), Vector2(left + wd + 12.0, top)]), roof)
	var glass := Color("9ed2f2").lerp(Color("ffd36e"), _dusk)
	draw_rect(Rect2(left + 22.0, top + 26.0, 36.0, 38.0), glass)
	draw_rect(Rect2(left + wd - 58.0, top + 26.0, 36.0, 38.0), glass)
	var door := Color("e0533d") if hs.kind == 0 else Color("2f4858")
	draw_rect(Rect2(-14.0, -56.0, 28.0, 56.0), door)
	draw_circle(Vector2(8.0, -28.0), 2.5, Color("ffe08a"))
	if hs.kind == 2:
		var fx := left + wd + 14.0
		draw_line(Vector2(fx, 0), Vector2(fx, -22.0), Color("ff6fa5"), 2.0)
		draw_circle(Vector2(fx, -28.0), 6.0, Color("ff6fa5"))
		draw_line(Vector2(fx + 4.0, -30.0), Vector2(fx + 11.0, -28.0), Color("ffb36b"), 2.0)


func _draw_pins(w: float) -> void:
	for i in HOUSE_COUNT:
		if not _pins.has(i):
			continue
		var sx := house_x(i) - _cam
		if sx < -80.0 or sx > w + 80.0:
			continue
		var kind: String = _pins[i]
		var top := _ground_y - (float(_houses[i].h) + 66.0) * HOUSE_K - 40.0
		var active := kind != "done"
		var c := Vector2(sx, top + (sin(_time * 3.0 + i) * 7.0 if active else 0.0))
		var col := Color("3fae6a") if kind == "lawn" else (Color("e0533d") if kind == "card" else Color("9aa4b2"))
		if active:
			draw_circle(c, 44.0 + sin(_time * 4.0) * 5.0, Color(col, 0.25))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 26), c + Vector2(12, 26), c + Vector2(0, 50)]), col)
		draw_circle(c, 34.0, col)
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


func _draw_car(w: float, h: float) -> void:
	var lane_y := h - (h - (_ground_y + LAWN_H + WALK_H + 8.0)) * 0.22
	var x := fposmod(_time * 140.0, w + 500.0) - 250.0
	var col := Color("e0533d").lerp(Color("7a2a24"), _dusk * 0.5)
	draw_rect(Rect2(x, lane_y - 44.0, 170.0, 34.0), col)
	draw_colored_polygon(PackedVector2Array([
			Vector2(x + 34.0, lane_y - 44.0), Vector2(x + 58.0, lane_y - 74.0),
			Vector2(x + 120.0, lane_y - 74.0), Vector2(x + 146.0, lane_y - 44.0)]), col.lightened(0.08))
	draw_rect(Rect2(x + 64.0, lane_y - 68.0, 52.0, 22.0), Color("cfe9ff").lerp(Color("ffd36e"), _dusk * 0.6))
	for wx in [x + 36.0, x + 134.0]:
		draw_circle(Vector2(wx, lane_y - 8.0), 16.0, Color("111522"))
		draw_circle(Vector2(wx, lane_y - 8.0), 7.0, Color("9aa4b2"))


func _draw_walker() -> void:
	var foot := Vector2(_player_x - _cam, _ground_y + LAWN_H + WALK_H * 0.5 + 10.0)
	var swing := sin(_phase) if _walking else 0.0
	var bob := absf(sin(_phase)) * 4.0 if _walking else 1.0 + sin(_time * 2.0)
	draw_set_transform(foot, 0.0, Vector2(WALKER_K * _facing, WALKER_K))
	var hip := Vector2(0, -34.0 - bob)
	draw_set_transform(foot + Vector2(0, 2.0 * WALKER_K), 0.0, Vector2(WALKER_K * _facing, WALKER_K * 0.25))
	draw_circle(Vector2.ZERO, 24.0, Color(0, 0, 0, 0.2))
	draw_set_transform(foot, 0.0, Vector2(WALKER_K * _facing, WALKER_K))
	draw_line(hip + Vector2(-2, 0), Vector2(-swing * 16.0, -bob * 0.2), Color("151d2e"), 8.0, true)
	draw_line(hip + Vector2(2, 0), Vector2(swing * 16.0, -bob * 0.2), SUIT, 8.0, true)
	draw_circle(Vector2(-swing * 16.0 + 3.0, 0), 5.0, Color("0d1220"))
	draw_circle(Vector2(swing * 16.0 + 3.0, 0), 5.0, Color("0d1220"))
	var torso_top := hip + Vector2(0, -44.0)
	draw_line(hip, torso_top, SUIT, 26.0, true)
	draw_line(hip + Vector2(0, -38.0), hip + Vector2(0, -16.0), Color("e0533d"), 4.0, true)
	var shoulder := torso_top + Vector2(0, 8.0)
	draw_line(shoulder, shoulder + Vector2(swing * 14.0, 28.0), SUIT.lightened(0.1), 7.0, true)
	var hand := shoulder + Vector2(-swing * 12.0, 28.0)
	draw_line(shoulder, hand, SUIT, 7.0, true)
	draw_rect(Rect2(hand + Vector2(-9.0, 2.0), Vector2(22.0, 16.0)), Color("8a5a34"))
	var head := torso_top + Vector2(0, -16.0)
	draw_circle(head, 15.0, SKIN)
	draw_arc(head, 15.0, PI * 1.05, PI * 1.95, 14, Color("2b2118"), 8.0, true)
	draw_circle(head + Vector2(6.0, -1.0), 1.8, Color("2b2118"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _bubble_t > 0.0:
		var font := ThemeDB.fallback_font
		var tsize := font.get_string_size(_bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var box := Rect2(foot.x - tsize.x * 0.5 - 16.0, foot.y - 290.0, tsize.x + 32.0, 52.0)
		box.position.x = clampf(box.position.x, 8.0, size.x - box.size.x - 8.0)
		draw_style_box(_bubble_style, box)
		draw_string(font, box.position + Vector2(16.0, 36.0), _bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("1c1b1f"))
