extends Control
## Top-down neighborhood. Drag up/down to follow a sidewalk, push sideways to
## deliberately enter the road or turn at an intersection.

signal visit(house: int)

const HOUSE_COUNT := 12
const HOUSE_SPACING := 390.0
const HOUSE_MARGIN := 520.0
const WORLD_H := HOUSE_MARGIN * 2.0 + HOUSE_SPACING * (HOUSE_COUNT - 1)
const WORLD_W := 1800.0
const ROAD_HALF := 62.0
const WALK_W := 38.0
const HOUSE_W := 126.0
const HOUSE_D := 144.0
const YARD_GAP := 80.0
const WALK_SPEED := 380.0
const STICK_RANGE := 110.0
const DEADZONE := 0.12
const NEAR_DIST := 150.0
const DRIVEWAY_HALF := 30.0
const WORLD_TILT := 0.84
const WALK_WORLD_SCALE := 0.90
const TUFTS := 46
const INCH_PX := 4.5
const WALKER_K := 1.4
const SIDEWALK_CENTER := ROAD_HALF + WALK_W * 0.5
const LANE_SWITCH_INPUT := 0.52
const LATERAL_SNAP_SPEED := 520.0
const CAR_CLEAR_X := 42.0
const CAR_CLEAR_Y := 58.0
const JUNCTIONS := [WORLD_H * 0.2, WORLD_H * 0.4, WORLD_H * 0.61, WORLD_H * 0.81]
const CONNECTOR_XS := [300.0, WORLD_W - 300.0]
const LAKE_Y := WORLD_H * 0.53
const MOUNTAIN_Y := 260.0
const ROOFS := [Color("c4543e"), Color("5b6f8f"), Color("8a6f56"), Color("4f7f6a"), Color("805b73"), Color("b77945")]
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
var _player_x := WORLD_W * 0.5
var _cam := 0.0
var _cam_x := 0.0
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
var _neighbors: Array = []
var _pet_stations: Array = []
## -1 = left sidewalk, 0 = road center, 1 = right sidewalk.
var _main_lane := 1
var _lane_switch_ready := true
var _world_scale := 1.0
var _camera_flash := 0.0
var _photo_message := ""
var _photo_message_t := 0.0


func _ready() -> void:
	clip_contents = true
	_sb = StyleBoxFlat.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in HOUSE_COUNT:
		_houses.append({"roof": ROOFS[i % ROOFS.size()], "kind": i % 5,
				"brick": i % 4 == 0, "solar": i % 5 == 3, "fence": i % 3 == 2})
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
	for k in 8:
		_neighbors.append({"route": k % 3, "seed": rng.randf_range(0.0, WORLD_H),
				"speed": rng.randf_range(22.0, 42.0), "side": -1 if k % 2 == 0 else 1,
				"tone": k % 4, "dog": k in [1, 4, 7]})
	_pet_stations = [
		{"x": CONNECTOR_XS[0] - SIDEWALK_CENTER - 25.0, "y": (JUNCTIONS[0] + JUNCTIONS[1]) * 0.5},
		{"x": CONNECTOR_XS[1] + SIDEWALK_CENTER + 25.0, "y": (JUNCTIONS[2] + JUNCTIONS[3]) * 0.5},
		{"x": _road_x(JUNCTIONS[2]) + SIDEWALK_CENTER + 24.0, "y": JUNCTIONS[2] + 220.0},
	]
	GameState.stats_changed.connect(_sync_mood)
	_sync_mood()


func house_y(i: int) -> float:
	if i >= 8:
		var junction_y := float(JUNCTIONS[i - 8])
		var offset := ROAD_HALF + WALK_W + YARD_GAP + HOUSE_D * 0.5
		return junction_y + (-offset if i % 2 == 0 else offset)
	return WORLD_H - HOUSE_MARGIN - i * HOUSE_SPACING


func _side(i: int) -> int:
	if i >= 8:
		return -1 if i % 2 == 0 else 1
	return -1 if i % 2 == 0 else 1


func _house_c(i: int) -> Vector2:
	if i >= 8:
		return Vector2(240.0 if _side(i) < 0 else WORLD_W - 240.0, house_y(i))
	return Vector2(_road_x(house_y(i)) + _side(i) * (ROAD_HALF + WALK_W + YARD_GAP + HOUSE_W * 0.5), house_y(i))


func _road_x(wy: float) -> float:
	return WORLD_W * 0.5 + sin(wy / 430.0) * 70.0 + sin(wy / 170.0) * 20.0


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
		_player_x = saved_position.x if saved_position.x >= 0.0 else _road_x(_player_y)
		var offset := _player_x - _road_x(_player_y)
		_main_lane = 0 if absf(offset) < ROAD_HALF else (-1 if offset < 0.0 else 1)
	else:
		_main_lane = 1
		_player_x = _road_x(_player_y) + SIDEWALK_CENTER
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
	if pos.distance_to(Vector2(size.x - 66.0, size.y - 72.0)) <= 48.0:
		_take_photo.call_deferred()
		return true
	if pos.x >= size.x - 206.0 and pos.y <= 296.0:
		return true
	pos = _screen_to_world_draw(pos)
	for i in HOUSE_COUNT:
		var kind: String = _pins.get(i, "")
		if kind != "lawn" and kind != "card":
			continue
		var pin := _house_c(i) - Vector2(_cam_x, _cam) + Vector2(0, -18.0)
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
		var previous := Vector2(_player_x, _player_y)
		var candidate := previous + velocity * delta
		candidate.y = fposmod(candidate.y, WORLD_H)
		var road_center := _road_x(candidate.y)
		var closest_junction := float(JUNCTIONS[0])
		for junction in JUNCTIONS:
			if absf(candidate.y - float(junction)) < absf(candidate.y - closest_junction):
				closest_junction = float(junction)
		var connector_x := _closest_connector(candidate.x)
		var on_connector := absf(candidate.x - connector_x) < ROAD_HALF + WALK_W and candidate.y > float(JUNCTIONS[0]) - 120.0 and candidate.y < float(JUNCTIONS[3]) + 120.0
		var on_side_street := absf(candidate.x - road_center) > ROAD_HALF + WALK_W and absf(candidate.y - closest_junction) < 150.0
		var driveway_house := _driveway_at(candidate)
		if on_connector and absf(candidate.y - closest_junction) >= 115.0:
			candidate.x = clampf(candidate.x, connector_x - ROAD_HALF - WALK_W * 0.72,
					connector_x + ROAD_HALF + WALK_W * 0.72)
		elif driveway_house >= 0:
			# Driveways connect each sidewalk to its front door, so the player can
			# leave the walking lane only where the neighborhood visually supports it.
			var home := _house_c(driveway_house)
			candidate.y = clampf(candidate.y, home.y - DRIVEWAY_HALF, home.y + DRIVEWAY_HALF)
			candidate.x = clampf(candidate.x, minf(home.x, road_center) - 18.0, maxf(home.x, road_center) + 18.0)
		elif on_side_street:
			candidate.y = clampf(candidate.y, closest_junction - ROAD_HALF - WALK_W * 0.65,
					closest_junction + ROAD_HALF + WALK_W * 0.65)
			candidate.x = fposmod(candidate.x, WORLD_W)
		elif absf(candidate.y - closest_junction) < 115.0:
			# The intersection is the only free-turn area. Moving beyond its outer
			# sidewalk enters a side street instead of being clamped to the main road.
			candidate.x = fposmod(candidate.x, WORLD_W)
		else:
			_update_main_lane(move.x)
			var target_x := road_center + float(_main_lane) * SIDEWALK_CENTER
			candidate.x = move_toward(previous.x, target_x, LATERAL_SNAP_SPEED * delta)
		candidate = _keep_clear_of_cars(previous, candidate)
		_player_x = candidate.x
		_player_y = candidate.y
		_face = velocity.angle() + PI * 0.5
		_phase += delta * 10.0 * strength
		_moving = true
	else:
		_moving = false
	_world_scale = lerpf(_world_scale, WALK_WORLD_SCALE if _moving else 1.0, 1.0 - exp(-5.0 * delta))
	_camera_flash = maxf(0.0, _camera_flash - delta * 3.5)
	_photo_message_t = maxf(0.0, _photo_message_t - delta)
	_angle = lerp_angle(_angle, _face, 1.0 - exp(-12.0 * delta))
	_cam = clampf(_player_y - size.y * 0.58, 0.0, maxf(0.0, WORLD_H - size.y))
	_cam_x = clampf(_player_x - size.x * 0.5, 0.0, maxf(0.0, WORLD_W - size.x))
	_near = -1
	var best := NEAR_DIST
	for i in HOUSE_COUNT:
		var d := Vector2(_player_x, _player_y).distance_to(_house_c(i))
		if d < best:
			best = d
			_near = i
	queue_redraw()


func _driveway_at(point: Vector2) -> int:
	for i in HOUSE_COUNT:
		var home := _house_c(i)
		if absf(point.y - home.y) <= DRIVEWAY_HALF:
			var road := _road_x(home.y)
			if point.x >= minf(home.x, road) - 18.0 and point.x <= maxf(home.x, road) + 18.0:
				return i
	return -1


func _screen_to_world_draw(point: Vector2) -> Vector2:
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	var scale := Vector2(_world_scale, _world_scale * WORLD_TILT)
	return center + (point - center) / scale


func _take_photo() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://hoa-photo-%s.png" % stamp
	var error := get_viewport().get_texture().get_image().save_png(path)
	_photo_message = "PHOTO SAVED" if error == OK else "CAMERA ERROR"
	_photo_message_t = 2.2
	_camera_flash = 1.0 if error == OK else 0.0
	queue_redraw()


func _closest_connector(x: float) -> float:
	return float(CONNECTOR_XS[0]) if absf(x - float(CONNECTOR_XS[0])) < absf(x - float(CONNECTOR_XS[1])) else float(CONNECTOR_XS[1])


func _update_main_lane(horizontal_input: float) -> void:
	if absf(horizontal_input) < 0.25:
		_lane_switch_ready = true
		return
	if not _lane_switch_ready or absf(horizontal_input) < LANE_SWITCH_INPUT:
		return
	if _main_lane != 0 and signf(horizontal_input) == -float(_main_lane):
		# An intentional push toward the street moves from the sidewalk to its center.
		_main_lane = 0
		_lane_switch_ready = false
	elif _main_lane == 0:
		# An intentional push away from the center selects that side's sidewalk.
		_main_lane = -1 if horizontal_input < 0.0 else 1
		_lane_switch_ready = false


func _keep_clear_of_cars(previous: Vector2, candidate: Vector2) -> Vector2:
	for car in _cars:
		var car_pos := Vector2(_road_x(float(car.y)) + int(car.side) * (ROAD_HALF - 24.0), float(car.y))
		if absf(candidate.x - car_pos.x) >= CAR_CLEAR_X or absf(candidate.y - car_pos.y) >= CAR_CLEAR_Y:
			continue
		# Slide along the car on the axis that was already clear. If loading an old
		# save inside a car, move the walker to the nearest safe side immediately.
		if absf(previous.x - car_pos.x) >= CAR_CLEAR_X:
			candidate.x = previous.x
		elif absf(previous.y - car_pos.y) >= CAR_CLEAR_Y:
			candidate.y = previous.y
		else:
			var side := -1.0 if previous.x <= car_pos.x else 1.0
			candidate.x = car_pos.x + side * CAR_CLEAR_X
	return candidate


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
	var world_center := Vector2(cx, h * 0.54)
	draw_set_transform(world_center * (Vector2.ONE - Vector2(_world_scale, _world_scale * WORLD_TILT)),
			0.0, Vector2(_world_scale, _world_scale * WORLD_TILT))
	_draw_ground(w, h, cx)
	_draw_ambience(w, h)
	_draw_pet_stations()
	for car in _cars:
		if _on_screen(car.y):
			_draw_car(_road_x(car.y) - _cam_x + car.side * (ROAD_HALF - 24.0), car.y - _cam, car.col)
	for i in HOUSE_COUNT:
		if _on_screen(house_y(i), 320.0):
			_draw_yard(i)
	var sh := Vector2(18.0, 22.0) * (1.0 + _dusk * 1.2)
	for t in _trees:
		if _on_screen(t.y):
			var tc := Vector2(_road_x(t.y) - _cam_x + t.side * (ROAD_HALF + WALK_W + t.off + t.r), t.y - _cam)
			_ellipse(tc + sh * 0.9, t.r, t.r, Color(0, 0, 0, 0.18))
	for i in HOUSE_COUNT:
		if _on_screen(house_y(i), 320.0):
			var focus_scale := 1.20 if i == _near else 1.0
			_set_world_transform(_house_c(i) - Vector2(_cam_x, _cam), focus_scale)
			_draw_house(i, sh / focus_scale)
			_set_world_transform()
	for t in _trees:
		if _on_screen(t.y):
			var sway := sin(_time * 1.3 + float(t.phase)) * 3.0
			var tc := Vector2(_road_x(t.y) - _cam_x + t.side * (ROAD_HALF + WALK_W + t.off + t.r) + sway, t.y - _cam)
			draw_line(tc + Vector2(0, 30.0), tc + Vector2(-sway * 0.4, -8.0), Color("6b4931"), 10.0, true)
			var g := Color("2f9e57").lightened(float(t.tone)).lerp(Color("1c5a3e"), _dusk * 0.7)
			_ellipse(tc, t.r, t.r * 0.9, g)
			_ellipse(tc + Vector2(-t.r * 0.28, -t.r * 0.2), t.r * 0.62, t.r * 0.58, g.lightened(0.12))
			_ellipse(tc + Vector2(t.r * 0.3, -t.r * 0.08), t.r * 0.48, t.r * 0.5, g.darkened(0.08))
	for i in HOUSE_COUNT:
		if _on_screen(house_y(i), 320.0):
			_draw_highlight(i)
			_draw_pin(i)
	_draw_neighbors()
	_draw_walker(Vector2(_player_x - _cam_x, _player_y - _cam))
	if _dusk > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.1, 0.32, 0.4 * _dusk))
	if _gloom > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.25, 0.27, 0.32, 0.4 * _gloom))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_ui(w, h)
	if _camera_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, _camera_flash * 0.72))


func _set_world_transform(focus := Vector2.ZERO, focus_scale := 1.0) -> void:
	var base_scale := Vector2(_world_scale, _world_scale * WORLD_TILT)
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	var origin := center * (Vector2.ONE - base_scale)
	if focus_scale != 1.0:
		origin += base_scale * focus * (1.0 - focus_scale)
	draw_set_transform(origin, 0.0, base_scale * focus_scale)


func _draw_ground(w: float, h: float, cx: float) -> void:
	var lawn := Color("58c27d").lerp(Color("2c7050"), _dusk * 0.7)
	draw_rect(Rect2(0, 0, w, h), lawn)
	var k := int(floor(_cam / 120.0))
	while k * 120.0 - _cam < h:
		if k % 2 == 0:
			draw_rect(Rect2(0, k * 120.0 - _cam, w, 120.0), Color(1, 1, 1, 0.045))
		k += 1
	_draw_landmarks(w, h)
	var road := Color("3a4152").lerp(Color("22263a"), _dusk * 0.6)
	var walk := Color("d9dde3").lerp(Color("8f8aa8"), _dusk * 0.6)
	# Two parallel neighborhood avenues connect the cross streets into a real
	# street network, with roundabouts at alternating junctions.
	var top_y := float(JUNCTIONS[0]) - ROAD_HALF - WALK_W
	var bottom_y := float(JUNCTIONS[3]) + ROAD_HALF + WALK_W
	for connector in CONNECTOR_XS:
		var sx: float = float(connector) - _cam_x
		draw_rect(Rect2(sx - ROAD_HALF - WALK_W, top_y - _cam, WALK_W, bottom_y - top_y), walk)
		draw_rect(Rect2(sx - ROAD_HALF, top_y - _cam, ROAD_HALF * 2.0, bottom_y - top_y), road)
		draw_rect(Rect2(sx + ROAD_HALF, top_y - _cam, WALK_W, bottom_y - top_y), walk)
		var dash_y := top_y + 30.0
		while dash_y < bottom_y:
			draw_line(Vector2(sx, dash_y - _cam), Vector2(sx, dash_y + 42.0 - _cam), Color("ffe08a", 0.7), 4.0)
			dash_y += 88.0
	for junction in JUNCTIONS:
		var sy: float = float(junction) - _cam
		if sy > -100.0 and sy < h + 100.0:
			draw_rect(Rect2(-_cam_x, sy - ROAD_HALF, WORLD_W, ROAD_HALF * 2.0), road)
			draw_rect(Rect2(-_cam_x, sy - ROAD_HALF - WALK_W, WORLD_W, WALK_W), walk)
			draw_rect(Rect2(-_cam_x, sy + ROAD_HALF, WORLD_W, WALK_W), walk)
			for wx in range(0, int(WORLD_W), 90):
				draw_line(Vector2(wx - _cam_x, sy), Vector2(wx + 44.0 - _cam_x, sy), Color("ffe08a", 0.7), 4.0)
	# Curving residential lanes break up the grid and make the neighborhood feel
	# grown-in. They meet the main avenue at their ends and weave through blocks.
	for lane_i in 3:
		var lane := PackedVector2Array()
		var lane_y := WORLD_H * (0.27 + lane_i * 0.23)
		for point_i in 15:
			var t := float(point_i) / 14.0
			var wx := 90.0 + t * (WORLD_W - 180.0)
			var wy := lane_y + sin(t * TAU * 1.5 + lane_i * 1.7) * (72.0 + lane_i * 9.0)
			lane.append(Vector2(wx - _cam_x, wy - _cam))
		draw_polyline(lane, walk, ROAD_HALF * 2.0 + WALK_W * 2.0, true)
		draw_polyline(lane, road, ROAD_HALF * 2.0, true)
		draw_polyline(lane, Color("ffe08a", 0.68), 4.0, true)
	for connector_i in CONNECTOR_XS.size():
		for junction_i in range(connector_i, JUNCTIONS.size(), 2):
			var circle_c := Vector2(float(CONNECTOR_XS[connector_i]) - _cam_x, float(JUNCTIONS[junction_i]) - _cam)
			draw_circle(circle_c, 88.0, walk)
			draw_circle(circle_c, 66.0, road)
			draw_circle(circle_c, 25.0, Color("4f9b64").lerp(Color("274c42"), _dusk * 0.6))
			draw_circle(circle_c, 31.0, Color("d9dde3"), false, 5.0)
	_draw_road_band(-ROAD_HALF - WALK_W, ROAD_HALF + WALK_W, walk, h)
	_draw_road_band(-ROAD_HALF, ROAD_HALF, road, h)
	k = int(floor(_cam / 80.0))
	while k * 80.0 - _cam < h:
		var wy: float = k * 80.0
		var sy: float = wy - _cam
		var rc := _road_x(wy) - _cam_x
		draw_line(Vector2(rc, sy), Vector2(_road_x(wy + 40.0) - _cam_x, sy + 40.0), Color("ffe08a", 0.7), 4.0)
		k += 1


func _draw_landmarks(w: float, h: float) -> void:
	var lake_y := LAKE_Y - _cam
	var lake_x := WORLD_W - 230.0 - _cam_x
	if lake_y > -300.0 and lake_y < h + 300.0:
		_ellipse(Vector2(lake_x, lake_y), 178.0, 245.0, Color("b8d7b2").lerp(Color("314f55"), _dusk * 0.6))
		_ellipse(Vector2(lake_x + 8.0, lake_y), 157.0, 224.0, Color("4aa9c7").lerp(Color("25465d"), _dusk * 0.65))
		for i in 6:
			var ripple_y := lake_y - 150.0 + i * 58.0
			draw_arc(Vector2(lake_x + sin(i * 1.7) * 45.0, ripple_y), 22.0 + i * 3.0,
					0.15, PI - 0.15, 16, Color(0.8, 0.95, 1.0, 0.35), 2.0)
		# Small neighborhood dock.
		draw_rect(Rect2(lake_x - 141.0, lake_y - 18.0, 118.0, 36.0), Color("8a6747"))
		for x in range(int(lake_x - 134.0), int(lake_x - 28.0), 18):
			draw_line(Vector2(x, lake_y - 16.0), Vector2(x, lake_y + 16.0), Color("b38a60"), 2.0)
	var mountain_y := MOUNTAIN_Y - _cam
	if mountain_y > -260.0 and mountain_y < h + 260.0:
		var back := Color("75869b").lerp(Color("343a57"), _dusk * 0.65)
		var front := Color("536b64").lerp(Color("27394a"), _dusk * 0.65)
		for i in 6:
			var base_x := -80.0 + i * 365.0 - _cam_x
			var peak := Vector2(base_x + 85.0, mountain_y - 145.0 - (i % 3) * 32.0)
			draw_colored_polygon(PackedVector2Array([
					Vector2(base_x, mountain_y + 70.0), peak, Vector2(base_x + 190.0, mountain_y + 70.0)]), back)
			draw_colored_polygon(PackedVector2Array([
					peak, peak + Vector2(-31.0, 52.0), peak + Vector2(4.0, 39.0), peak + Vector2(34.0, 58.0)]),
					Color("e8eef2", 0.9))
		for i in 5:
			var base_x := -30.0 + i * 430.0 - _cam_x
			draw_colored_polygon(PackedVector2Array([
					Vector2(base_x, mountain_y + 95.0), Vector2(base_x + 95.0, mountain_y - 70.0),
					Vector2(base_x + 210.0, mountain_y + 95.0)]), front)


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
		points.append(Vector2(_road_x(_cam + sy) - _cam_x + left, sy))
		sy += step
	sy = h + step
	while sy >= -step:
		points.append(Vector2(_road_x(_cam + sy) - _cam_x + right, sy))
		sy -= step
	draw_colored_polygon(points, color)


func _draw_car(x: float, y: float, col: Color) -> void:
	var body := col.lerp(Color("111522"), _dusk * 0.4)
	var glass := Color("bfe2f5").lerp(Color("303b55"), _dusk * 0.65)
	# Offset shadow, visible tires, tapered hood/trunk, and a raised cabin make
	# the parked cars read as small 3D objects instead of flat rectangles.
	_ellipse(Vector2(x + 7.0, y + 8.0), 29.0, 49.0, Color(0, 0, 0, 0.24))
	_rr(Rect2(x - 27.0, y - 29.0, 8.0, 22.0), Color("171b24"), 3)
	_rr(Rect2(x + 19.0, y - 29.0, 8.0, 22.0), Color("171b24"), 3)
	_rr(Rect2(x - 27.0, y + 12.0, 8.0, 22.0), Color("171b24"), 3)
	_rr(Rect2(x + 19.0, y + 12.0, 8.0, 22.0), Color("171b24"), 3)
	draw_colored_polygon(PackedVector2Array([
			Vector2(x - 21.0, y - 45.0), Vector2(x + 21.0, y - 45.0),
			Vector2(x + 25.0, y - 31.0), Vector2(x + 25.0, y + 33.0),
			Vector2(x + 20.0, y + 45.0), Vector2(x - 20.0, y + 45.0),
			Vector2(x - 25.0, y + 33.0), Vector2(x - 25.0, y - 31.0)]), body.darkened(0.12))
	_rr(Rect2(x - 21.0, y - 39.0, 42.0, 77.0), body, 11)
	# Raised roof/cabin with shaded sides and separate front/rear glass.
	_rr(Rect2(x - 17.0, y - 25.0, 34.0, 48.0), body.lightened(0.16), 8)
	draw_colored_polygon(PackedVector2Array([
			Vector2(x - 17.0, y - 23.0), Vector2(x - 13.0, y - 17.0),
			Vector2(x - 13.0, y + 17.0), Vector2(x - 17.0, y + 22.0)]), body.darkened(0.16))
	_rr(Rect2(x - 13.0, y - 20.0, 26.0, 15.0), glass, 4)
	_rr(Rect2(x - 13.0, y + 7.0, 26.0, 12.0), glass.darkened(0.08), 4)
	draw_line(Vector2(x - 16.0, y - 34.0), Vector2(x + 13.0, y - 34.0), body.lightened(0.38), 2.0, true)
	draw_circle(Vector2(x - 14.0, y - 39.0), 3.0, Color("fff1b0"))
	draw_circle(Vector2(x + 14.0, y - 39.0), 3.0, Color("fff1b0"))
	draw_circle(Vector2(x - 14.0, y + 38.0), 2.8, Color("d94b45"))
	draw_circle(Vector2(x + 14.0, y + 38.0), 2.8, Color("d94b45"))


func _draw_pet_stations() -> void:
	for station in _pet_stations:
		var p := Vector2(float(station.x) - _cam_x, float(station.y) - _cam)
		if p.y < -80.0 or p.y > size.y + 80.0:
			continue
		_ellipse(p + Vector2(5.0, 8.0), 18.0, 10.0, Color(0, 0, 0, 0.18))
		draw_rect(Rect2(p + Vector2(-4.0, -32.0), Vector2(8.0, 42.0)), Color("52616f"))
		_rr(Rect2(p + Vector2(-16.0, -48.0), Vector2(32.0, 28.0)), Color("2f9e57"), 5)
		draw_circle(p + Vector2(0.0, -34.0), 6.0, Color.WHITE, false, 2.0)
		draw_circle(p + Vector2(-5.0, 12.0), 8.0, Color("72bde0"))
		draw_string(ThemeDB.fallback_font, p + Vector2(-14.0, -28.0), "PET", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)


func _draw_neighbors() -> void:
	var route_top := float(JUNCTIONS[0])
	var route_span := float(JUNCTIONS[3]) - route_top
	for neighbor in _neighbors:
		var route := int(neighbor.route)
		var wy: float
		var wx: float
		if route == 0:
			wy = fposmod(float(neighbor.seed) + _time * float(neighbor.speed), WORLD_H - 280.0) + 140.0
			wx = _road_x(wy) + int(neighbor.side) * SIDEWALK_CENTER
		else:
			wy = route_top + fposmod(float(neighbor.seed) + _time * float(neighbor.speed), route_span)
			wx = float(CONNECTOR_XS[route - 1]) + int(neighbor.side) * SIDEWALK_CENTER
		if not _on_screen(wy, 100.0):
			continue
		var p := Vector2(wx - _cam_x, wy - _cam)
		_draw_neighbor(p, int(neighbor.tone), float(neighbor.speed))
		if bool(neighbor.dog):
			var dog_side := float(neighbor.side)
			var dog_p := p + Vector2(25.0 * dog_side, 24.0)
			draw_line(p + Vector2(7.0 * dog_side, 3.0), dog_p + Vector2(0.0, -5.0), Color("7b5a3b"), 2.0)
			_draw_dog(dog_p, int(neighbor.tone))


func _draw_neighbor(p: Vector2, tone: int, speed: float) -> void:
	var bob := sin(_time * speed * 0.12 + p.y * 0.02) * 2.0
	var shirts := [Color("e05a47"), Color("477bd1"), Color("e6ad3b"), Color("8c5fa8")]
	var shirt: Color = shirts[tone]
	var skin: Color = [Color("f2c29b"), Color("9b6547"), Color("d89b73"), Color("6f4635")][tone]
	_ellipse(p + Vector2(3.0, 11.0), 10.0, 7.0, Color(0, 0, 0, 0.16))
	draw_line(p + Vector2(-5.0, 7.0), p + Vector2(-7.0, 17.0 + bob), Color("253044"), 4.0, true)
	draw_line(p + Vector2(5.0, 7.0), p + Vector2(7.0, 17.0 - bob), Color("253044"), 4.0, true)
	_ellipse(p, 10.0, 13.0, shirt)
	draw_circle(p + Vector2(0.0, -13.0), 7.0, skin)


func _draw_dog(p: Vector2, tone: int) -> void:
	var fur: Color = [Color("c78a4b"), Color("e7d2aa"), Color("6b4a34"), Color("b6a39a")][tone]
	_ellipse(p, 11.0, 7.0, fur)
	draw_circle(p + Vector2(10.0, -4.0), 6.0, fur.lightened(0.08))
	draw_colored_polygon(PackedVector2Array([p + Vector2(7.0, -8.0), p + Vector2(5.0, -15.0), p + Vector2(11.0, -9.0)]), fur.darkened(0.18))
	draw_line(p + Vector2(-8.0, 3.0), p + Vector2(-13.0, 10.0), fur.darkened(0.15), 3.0, true)
	draw_line(p + Vector2(7.0, 3.0), p + Vector2(9.0, 10.0), fur.darkened(0.15), 3.0, true)
	draw_line(p + Vector2(-10.0, -2.0), p + Vector2(-15.0, -9.0), fur, 3.0, true)


func _yard_rect(i: int) -> Rect2:
	if i >= 8:
		var hc := _house_c(i) - Vector2(_cam_x, _cam)
		return Rect2(hc.x - HOUSE_W * 0.65, hc.y - 104.0, HOUSE_W * 1.3, 208.0)
	var cx := _road_x(house_y(i)) - _cam_x
	var x0 := (cx + ROAD_HALF + WALK_W) if _side(i) > 0 else (cx - ROAD_HALF - WALK_W - YARD_GAP)
	return Rect2(x0, house_y(i) - 100.0 - _cam, YARD_GAP, 200.0)


func _draw_yard(i: int) -> void:
	var r := _yard_rect(i)
	var home := _house_c(i)
	var road_x := _road_x(home.y)
	var drive_start := Vector2(road_x - _cam_x, home.y - _cam)
	var drive_end := Vector2(home.x - _side(i) * HOUSE_W * 0.46 - _cam_x, home.y - _cam)
	draw_line(drive_start, drive_end, Color("b8b3a8").lerp(Color("686477"), _dusk * 0.5), DRIVEWAY_HALF * 1.55, true)
	draw_line(drive_start, drive_end, Color(1, 1, 1, 0.16), 3.0, true)
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
	var c := _house_c(i) - Vector2(_cam_x, _cam)
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
	elif hs.kind == 4:
		_rr(rect, Color("ddd1bb").lerp(Color("6f6470"), _dusk * 0.5), 12)
		draw_colored_polygon(PackedVector2Array([
				Vector2(rect.position.x - 8.0, c.y - 18.0), Vector2(c.x, rect.position.y - 24.0),
				Vector2(rect.end.x + 8.0, c.y - 18.0), Vector2(c.x, c.y + 10.0)]), roof)
		_rr(Rect2(c.x - 49.0, c.y + 26.0, 38.0, 30.0), Color("84b9d5").lerp(Color("ffd36e"), _dusk), 5)
		_rr(Rect2(c.x + 11.0, c.y + 26.0, 38.0, 30.0), Color("84b9d5").lerp(Color("ffd36e"), _dusk), 5)
	else:
		draw_rect(Rect2(rect.position.x, rect.position.y, HOUSE_W * 0.5, HOUSE_D), roof.lightened(0.14))
		draw_rect(Rect2(c.x, rect.position.y, HOUSE_W * 0.5, HOUSE_D), roof.darkened(0.14))
		var ry := rect.position.y + 14.0
		while ry < rect.end.y - 6.0:
			draw_line(Vector2(rect.position.x, ry), Vector2(rect.end.x, ry), Color(0, 0, 0, 0.08), 2.0)
			ry += 16.0
		draw_line(Vector2(c.x, rect.position.y), Vector2(c.x, rect.end.y), roof.darkened(0.35), 3.0)
		draw_rect(Rect2(c.x - side * -34.0 - 10.0, rect.position.y + 18.0, 20.0, 22.0), Color("3b3f4f"))
	if bool(hs.brick):
		var by := rect.position.y + 12.0
		while by < rect.end.y:
			draw_line(Vector2(rect.position.x + 6.0, by), Vector2(rect.end.x - 6.0, by), Color(0.22, 0.12, 0.08, 0.22), 2.0)
			by += 18.0
	if bool(hs.solar):
		for row in 2:
			for col in 3:
				var panel := Rect2(c.x - 45.0 + col * 31.0, c.y - 48.0 + row * 27.0, 27.0, 22.0)
				_rr(panel, Color("16364f"), 2)
				draw_rect(panel, Color("65a8c9", 0.7), false, 1.5)
	if bool(hs.fence):
		var fence_x := inner_x - side * 58.0
		for fy in range(int(c.y - 78.0), int(c.y + 88.0), 22):
			draw_line(Vector2(fence_x, fy), Vector2(fence_x, fy + 14.0), Color("efe0bd"), 5.0)
		draw_line(Vector2(fence_x, c.y - 72.0), Vector2(fence_x, c.y + 82.0), Color("cbb995"), 2.0)
	# Door, walkway lamps, and foundation details keep each home readable from above.
	var door := Rect2(c.x - side * (HOUSE_W * 0.5 - 7.0) - 8.0, c.y - 14.0, 16.0, 28.0)
	_rr(door, Color("56372b"), 3)
	for lamp_y in [-34.0, 34.0]:
		draw_circle(Vector2(inner_x - side * 18.0, c.y + lamp_y), 4.0, Color("ffd36e"))
	# Chimneys and air-conditioning units vary the roofline.
	if i % 2 == 0:
		_rr(Rect2(c.x + side * 38.0 - 9.0, c.y - 63.0, 18.0, 26.0), Color("765044"), 3)
	else:
		_rr(Rect2(c.x - side * 48.0 - 12.0, c.y + 45.0, 24.0, 24.0), Color("aeb6bc"), 4)
		draw_circle(Vector2(c.x - side * 48.0, c.y + 57.0), 7.0, Color("6e7880"), false, 2.0)
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
	var c := _house_c(i) - Vector2(_cam_x, _cam)
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var rect := Rect2(c.x - HOUSE_W * 0.62, c.y - HOUSE_D * 0.62, HOUSE_W * 1.24, HOUSE_D * 1.24).grow(12.0 + pulse * 5.0)
	var active: bool = _pins.get(i, "") in ["lawn", "card"]
	var col := Color("ffd36e") if active else Color(1, 1, 1, 0.8)
	draw_rect(rect, Color(col, 0.12 + 0.08 * pulse))
	draw_rect(rect, Color(col, 0.95), false, 5.0)
	if active:
		var tag := Rect2(c.x - 58.0, rect.position.y - 36.0, 116.0, 30.0)
		_rr(tag, Color("e0533d"), 8)
		draw_string(ThemeDB.fallback_font, tag.position + Vector2(0.0, 22.0), "VIOLATION",
				HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 17, Color.WHITE)


func _draw_pin(i: int) -> void:
	if not _pins.has(i):
		return
	var kind: String = _pins[i]
	var active := kind != "done"
	var c := _house_c(i) - Vector2(_cam_x, _cam) + Vector2(0, -18.0 + (sin(_time * 3.0 + i) * 6.0 if active else 0.0))
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
	_draw_map(Rect2(w - 206.0, 16.0, 190.0, 280.0))
	var camera_c := Vector2(w - 66.0, h - 72.0)
	draw_circle(camera_c + Vector2(3.0, 5.0), 42.0, Color(0, 0, 0, 0.25))
	draw_circle(camera_c, 42.0, Color("f4ecd8"))
	_rr(Rect2(camera_c - Vector2(25.0, 17.0), Vector2(50.0, 36.0)), Color("273444"), 7)
	_rr(Rect2(camera_c + Vector2(-13.0, -24.0), Vector2(26.0, 10.0)), Color("273444"), 4)
	draw_circle(camera_c + Vector2(0.0, 1.0), 12.0, Color("71b9dc"))
	draw_circle(camera_c + Vector2(0.0, 1.0), 7.0, Color("182735"))
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
	if _photo_message_t > 0.0:
		var photo_size := font.get_string_size(_photo_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		var photo_box := Rect2(camera_c.x - photo_size.x - 72.0, camera_c.y - 24.0, photo_size.x + 24.0, 48.0)
		_rr(photo_box, Color(0.04, 0.08, 0.12, 0.82), 12)
		draw_string(font, photo_box.position + Vector2(12.0, 32.0), _photo_message,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)


func _draw_map(rect: Rect2) -> void:
	_rr(rect, Color(0.04, 0.08, 0.12, 0.78), 16)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12.0, 25.0), "MAP",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("d8edf6"))
	var inner := Rect2(rect.position + Vector2(10.0, 34.0), rect.size - Vector2(20.0, 44.0))
	var lake_my := inner.position.y + (1.0 - LAKE_Y / WORLD_H) * inner.size.y
	_ellipse(Vector2(inner.end.x - 11.0, lake_my), 28.0, 22.0, Color("4aa9c7", 0.85))
	var mountain_my := inner.position.y + (1.0 - MOUNTAIN_Y / WORLD_H) * inner.size.y
	for i in 3:
		var mx := inner.position.x + 18.0 + i * 43.0
		draw_colored_polygon(PackedVector2Array([
				Vector2(mx - 18.0, mountain_my + 12.0), Vector2(mx, mountain_my - 18.0 - i * 3.0),
				Vector2(mx + 20.0, mountain_my + 12.0)]), Color("75869b"))
	var route := PackedVector2Array()
	for i in 25:
		var wy := WORLD_H * float(i) / 24.0
		var nx := clampf(_road_x(wy) / WORLD_W, 0.0, 1.0)
		var ny := 1.0 - wy / WORLD_H
		route.append(inner.position + Vector2(nx * inner.size.x, ny * inner.size.y))
	draw_polyline(route, Color("b7bec8"), 8.0, true)
	for junction in JUNCTIONS:
		var my: float = inner.position.y + (1.0 - float(junction) / WORLD_H) * inner.size.y
		draw_line(Vector2(inner.position.x, my), Vector2(inner.end.x, my), Color("8e98a8"), 5.0, true)
	for house in _pins:
		var h := int(house)
		var hp := _house_c(h)
		var mx := inner.position.x + clampf(hp.x / WORLD_W, 0.0, 1.0) * inner.size.x
		var my := inner.position.y + (1.0 - hp.y / WORLD_H) * inner.size.y
		var kind: String = _pins[house]
		var col := Color("7b8794") if kind == "done" else (Color("50c878") if kind == "lawn" else Color("ff6b5a"))
		draw_circle(Vector2(mx, my), 6.0, col)
	var px := inner.position.x + clampf(_player_x / WORLD_W, 0.0, 1.0) * inner.size.x
	var py := inner.position.y + (1.0 - _player_y / WORLD_H) * inner.size.y
	draw_circle(Vector2(px, py), 7.0, Color("ffd36e"))
	draw_circle(Vector2(px, py), 10.0, Color("ffd36e", 0.35), false, 2.0)
