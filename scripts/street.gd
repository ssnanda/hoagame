extends Control
## Modern flat-vector street: parallax neighborhood + a walking president.
## Sky shifts from day to dusk as days pass; it greys out when happiness is low.

const SPEED := 90.0           # px/s for the sidewalk layer
const DUSK_DAYS := 40.0       # days until the sky is fully dusk
const SKY_DAY_TOP := Color("5fb4f0")
const SKY_DAY_BOTTOM := Color("d8f0ff")
const SKY_DUSK_TOP := Color("3b2f6b")
const SKY_DUSK_BOTTOM := Color("ff9d6c")
const SUIT := Color("23304a")
const SKIN := Color("f2c29b")

const FAR_PERIOD := 1100.0
const HOUSE_PERIOD := 1500.0

var _scroll := 0.0
var _time := 0.0
var _dusk := 0.0
var _gloom := 0.0
var _far: Array = []     # {x, w, h, c}
var _houses: Array = []  # {x, w, h, hue, kind}
var _shrubs: Array = []  # {x, r}


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(0, 280)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var x := 0.0
	while x < FAR_PERIOD:
		var w := rng.randf_range(60.0, 130.0)
		_far.append({"x": x, "w": w, "h": rng.randf_range(60.0, 150.0), "c": rng.randf()})
		x += w + rng.randf_range(0.0, 20.0)
	x = 0.0
	while x < HOUSE_PERIOD - 260.0:
		var w := rng.randf_range(190.0, 250.0)
		_houses.append({"x": x, "w": w, "h": rng.randf_range(95.0, 135.0),
				"hue": rng.randf(), "kind": rng.randi_range(0, 2)})
		x += w + rng.randf_range(40.0, 90.0)
	for i in 14:
		_shrubs.append({"x": rng.randf() * HOUSE_PERIOD, "r": rng.randf_range(16.0, 28.0)})
	GameState.stats_changed.connect(_sync_mood)
	_sync_mood()


func _sync_mood() -> void:
	var dusk := clampf(float(GameState.day - 1) / DUSK_DAYS, 0.0, 1.0)
	var happy: float = float(GameState.stats.get("happiness", 50))
	var gloom := clampf((35.0 - happy) / 35.0, 0.0, 1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "_dusk", dusk, 0.8)
	tw.tween_property(self, "_gloom", gloom, 0.8)


func _process(delta: float) -> void:
	_scroll += SPEED * delta
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var ground_y := h - 70.0   # top of the sidewalk
	_draw_sky(w, h)
	_draw_far(w, ground_y)
	_draw_houses(w, ground_y)
	_draw_ground(w, h, ground_y)
	_draw_walker(Vector2(w * 0.32, ground_y + 34.0))
	if _gloom > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.25, 0.27, 0.32, 0.45 * _gloom))


func _draw_sky(w: float, h: float) -> void:
	var top := SKY_DAY_TOP.lerp(SKY_DUSK_TOP, _dusk)
	var bottom := SKY_DAY_BOTTOM.lerp(SKY_DUSK_BOTTOM, _dusk)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([top, top, bottom, bottom]))
	# sun sinks toward the horizon as dusk grows
	var sun := Vector2(w * 0.78, lerpf(60.0, h - 110.0, _dusk))
	var sun_col := Color("fff2b0").lerp(Color("ff7a45"), _dusk)
	for i in 4:
		draw_circle(sun, 54.0 - i * 10.0 + 40.0, Color(sun_col, 0.07))
	draw_circle(sun, 30.0, sun_col)
	# soft drifting clouds
	for i in 3:
		var cx := fposmod(i * 330.0 + _scroll * (0.05 + i * 0.015), w + 260.0) - 130.0
		var cy := 36.0 + i * 34.0
		var cc := Color(1, 1, 1, lerpf(0.85, 0.25, _dusk))
		draw_circle(Vector2(cx, cy), 20.0, cc)
		draw_circle(Vector2(cx + 24.0, cy - 8.0), 26.0, cc)
		draw_circle(Vector2(cx + 54.0, cy), 20.0, cc)
		draw_rect(Rect2(cx, cy, 54.0, 20.0), cc)


func _draw_far(w: float, ground_y: float) -> void:
	var off := fposmod(_scroll * 0.2, FAR_PERIOD)
	var base := SKY_DAY_BOTTOM.lerp(SKY_DUSK_TOP, 0.35 + 0.4 * _dusk).darkened(0.12)
	for b in _far:
		var x: float = b.x - off
		while x < -b.w:
			x += FAR_PERIOD
		while x < w:
			var col := base.lerp(Color("7a8fb5"), b.c * 0.4)
			draw_rect(Rect2(x, ground_y - b.h, b.w, b.h), col)
			x += FAR_PERIOD


func _draw_houses(w: float, ground_y: float) -> void:
	var off := fposmod(_scroll * 0.55, HOUSE_PERIOD)
	for hs in _houses:
		var x: float = hs.x - off
		while x < -hs.w:
			x += HOUSE_PERIOD
		while x < w:
			_draw_house(Vector2(x, ground_y), hs)
			x += HOUSE_PERIOD
	for s in _shrubs:
		var sx: float = s.x - off
		while sx < -40.0:
			sx += HOUSE_PERIOD
		while sx < w + 40.0:
			var g := Color("3fae6a").lerp(Color("1f5e44"), _dusk * 0.7)
			draw_circle(Vector2(sx, ground_y - s.r * 0.4), s.r, g)
			draw_circle(Vector2(sx + s.r * 0.8, ground_y - s.r * 0.25), s.r * 0.7, g.lightened(0.1))
			sx += HOUSE_PERIOD


func _draw_house(origin: Vector2, hs: Dictionary) -> void:
	var wd: float = hs.w
	var ht: float = hs.h
	var palette := [Color("f4ece1"), Color("cfe3f0"), Color("f2d4cc"), Color("d9e8d2")]
	var body: Color = palette[int(hs.hue * 4.0) % 4].lerp(Color("5a4f7a"), _dusk * 0.4)
	var roof := Color("34405e").lerp(Color("231c3c"), _dusk * 0.5)
	var top := origin.y - ht
	# shadow on the lawn
	draw_rect(Rect2(origin.x - 4.0, origin.y - 6.0, wd + 8.0, 6.0), Color(0, 0, 0, 0.12))
	draw_rect(Rect2(origin.x, top, wd, ht), body)
	if hs.kind == 1:  # modern flat roof with an overhang
		draw_rect(Rect2(origin.x - 10.0, top - 14.0, wd + 20.0, 14.0), roof)
	else:             # gable roof
		draw_colored_polygon(PackedVector2Array([
				Vector2(origin.x - 12.0, top), Vector2(origin.x + wd * 0.5, top - 52.0),
				Vector2(origin.x + wd + 12.0, top)]), roof)
	# windows glow warmer as dusk grows
	var glass := Color("9ed2f2").lerp(Color("ffd36e"), _dusk)
	var win_w := 36.0
	var win_h := 38.0
	draw_rect(Rect2(origin.x + 22.0, top + 26.0, win_w, win_h), glass)
	draw_rect(Rect2(origin.x + wd - 22.0 - win_w, top + 26.0, win_w, win_h), glass)
	# door with accent colour
	var door := Color("e0533d") if hs.kind == 0 else Color("2f4858")
	draw_rect(Rect2(origin.x + wd * 0.5 - 14.0, origin.y - 56.0, 28.0, 56.0), door)
	draw_circle(Vector2(origin.x + wd * 0.5 + 8.0, origin.y - 28.0), 2.5, Color("ffe08a"))
	if hs.kind == 2:  # the obligatory pink flamingo
		var fx := origin.x + wd + 14.0
		draw_line(Vector2(fx, origin.y), Vector2(fx, origin.y - 22.0), Color("ff6fa5"), 2.0)
		draw_circle(Vector2(fx, origin.y - 28.0), 6.0, Color("ff6fa5"))
		draw_line(Vector2(fx + 4.0, origin.y - 30.0), Vector2(fx + 11.0, origin.y - 28.0), Color("ffb36b"), 2.0)


func _draw_ground(w: float, h: float, ground_y: float) -> void:
	var lawn := Color("58c27d").lerp(Color("2c7050"), _dusk * 0.7)
	draw_rect(Rect2(0, ground_y - 8.0, w, 12.0), lawn)
	var walk := Color("d9dde3").lerp(Color("8f8aa8"), _dusk * 0.6)
	draw_rect(Rect2(0, ground_y + 4.0, w, 56.0), walk)
	# sidewalk joints
	var joint := 120.0
	var off := fposmod(_scroll, joint)
	var x := -off
	while x < w:
		draw_line(Vector2(x, ground_y + 4.0), Vector2(x - 14.0, ground_y + 60.0), walk.darkened(0.12), 2.0)
		x += joint
	# curb + road
	draw_rect(Rect2(0, ground_y + 60.0, w, 6.0), walk.lightened(0.15))
	var road := Color("3a4152").lerp(Color("22263a"), _dusk * 0.6)
	draw_rect(Rect2(0, ground_y + 66.0, w, h - ground_y - 66.0), road)
	# dashed centre line
	var dash := 70.0
	var doff := fposmod(_scroll * 1.5, dash * 2.0)
	var dx := -doff
	var ly := h - 5.0
	while dx < w:
		draw_rect(Rect2(dx, ly - 2.0, dash, 3.0), Color(1, 1, 1, 0.55))
		dx += dash * 2.0


func _draw_walker(foot: Vector2) -> void:
	var phase := _time * 7.0
	var bob := absf(sin(phase)) * 4.0
	var swing := sin(phase)
	var hip := foot + Vector2(0, -34.0 - bob)
	# ground shadow
	draw_set_transform(foot + Vector2(0, 2.0), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, 24.0, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# legs (back then front)
	var back := Color("151d2e")
	draw_line(hip + Vector2(-2, 0), foot + Vector2(-swing * 16.0, -bob * 0.2), back, 8.0, true)
	draw_line(hip + Vector2(2, 0), foot + Vector2(swing * 16.0, -bob * 0.2), SUIT, 8.0, true)
	# shoes
	draw_circle(foot + Vector2(-swing * 16.0 + 3.0, 0), 5.0, Color("0d1220"))
	draw_circle(foot + Vector2(swing * 16.0 + 3.0, 0), 5.0, Color("0d1220"))
	# torso
	var torso_top := hip + Vector2(0, -44.0)
	draw_line(hip, torso_top, SUIT, 26.0, true)
	draw_line(hip + Vector2(0, -38.0), hip + Vector2(0, -16.0), Color("e0533d"), 4.0, true)  # tie
	# arms: front arm carries the briefcase
	var shoulder := torso_top + Vector2(0, 8.0)
	draw_line(shoulder, shoulder + Vector2(swing * 14.0, 28.0), SUIT.lightened(0.1), 7.0, true)
	var hand := shoulder + Vector2(-swing * 12.0, 28.0)
	draw_line(shoulder, hand, SUIT, 7.0, true)
	draw_rect(Rect2(hand + Vector2(-9.0, 2.0), Vector2(22.0, 16.0)), Color("8a5a34"))
	# head + hair
	var head := torso_top + Vector2(0, -16.0)
	draw_circle(head, 15.0, SKIN)
	draw_arc(head, 15.0, PI * 1.05, PI * 1.95, 14, Color("2b2118"), 8.0, true)
	draw_circle(head + Vector2(6.0, -1.0), 1.8, Color("2b2118"))
