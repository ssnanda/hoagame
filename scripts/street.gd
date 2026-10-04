extends Control
## Top-down neighborhood. Drag up/down to follow a sidewalk, push sideways to
## deliberately enter the road or turn at an intersection.

signal visit(house: int)
signal photo_taken(house: int, quality: int, usable: bool, documented: Array)

const HOUSE_COUNT := 112
const MAIN_HOUSE_COUNT := 48
const HOUSE_SPACING := 210.0
const HOUSE_MARGIN := 520.0
const WORLD_H := HOUSE_MARGIN * 2.0 + HOUSE_SPACING * (MAIN_HOUSE_COUNT - 1)
const WORLD_W := 1800.0
const ROAD_HALF := 62.0
const WALK_W := 38.0
const HOUSE_W := 126.0
const HOUSE_D := 144.0
const YARD_GAP := 80.0
const WALK_SPEED := 380.0
const STICK_RANGE := 86.0
const DEADZONE := 0.12
const NEAR_DIST := 150.0
const DRIVEWAY_HALF := 30.0
const WORLD_TILT := 0.84
const WALK_WORLD_SCALE := 0.90
const TUFTS := 46
const INCH_PX := 4.5
const WALKER_K := 1.4
const SIDEWALK_CENTER := ROAD_HALF + WALK_W * 0.5
const CAR_CLEAR_X := 34.0
const CAR_CLEAR_Y := 48.0
const CAR_SCALE := 0.8
const PARK_X := ROAD_HALF - 16.0
const JUNCTIONS := [WORLD_H * 0.08, WORLD_H * 0.2, WORLD_H * 0.32, WORLD_H * 0.44,
		WORLD_H * 0.56, WORLD_H * 0.68, WORLD_H * 0.8, WORLD_H * 0.92]
const CONNECTOR_XS := [300.0, WORLD_W - 300.0]
const CURVED_LANE_COUNT := 6
const CULDESAC_X := 92.0
const MINI_MAP_SIZE := Vector2(148.0, 204.0)
const LAKE_Y := WORLD_H * 0.53
const MOUNTAIN_Y := 260.0
const WEDGE_R := 252.0
const WEDGE_HALF := 0.5
const CART_SPEED := 2.3
const ZOOM_MIN := 1.0
const ZOOM_MAX := 2.4
const USABLE_QUALITY := 40
const GALLERY_PAGE := 4
const SEASON_LAWN := [Color("58c27d"), Color("66b858"), Color("b2a64f"), Color("d6e2e8")]
const SEASON_LEAF := [Color("48b86a"), Color("2f9e57"), Color("d9822b"), Color("e8eef2")]
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
var _house_positions: Array[Vector2] = []
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
var _world_scale := 1.0
var _camera_flash := 0.0
var _photo_message := ""
var _photo_message_t := 0.0
var _map_open := false
var _camera_mode := false
var _evidence: Dictionary = {}
var _property_violations: Dictionary = {}
var _zoom := 1.0
var _gallery_open := false
var _gallery_page := 0
var _gallery_sel := -1
var _thumbs: Dictionary = {}
var _cart := false
var _traffic: Array = []
var _kids: Array = []
var _crews: Array = []
var _season := 0
var _weekend := false
var _obstacles: Array = []
var _static_obstacles: Array = []
var _capturing := false


func _ready() -> void:
	clip_contents = true
	_sb = StyleBoxFlat.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in HOUSE_COUNT:
		_houses.append({"roof": ROOFS[i % ROOFS.size()], "kind": i % 5,
				"brick": i % 4 == 0, "solar": i % 5 == 3, "fence": i % 3 == 2})
		_grass.append(3.0)
	_build_house_positions()
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
		{"x": CONNECTOR_XS[1] + SIDEWALK_CENTER + 25.0, "y": (JUNCTIONS[6] + JUNCTIONS[7]) * 0.5},
		{"x": _road_x(JUNCTIONS[2]) + SIDEWALK_CENTER + 24.0, "y": JUNCTIONS[2] + 220.0},
	]
	GameState.stats_changed.connect(_sync_mood)
	_sync_mood()


func house_y(i: int) -> float:
	return _house_positions[i].y


func _build_house_positions() -> void:
	_house_positions.clear()
	for i in HOUSE_COUNT:
		if i >= MAIN_HOUSE_COUNT:
			var cross_index := i - MAIN_HOUSE_COUNT
			var junction_y := float(JUNCTIONS[int(cross_index / 8)])
			var offset := ROAD_HALF + WALK_W + YARD_GAP + HOUSE_D * 0.5
			var y := junction_y + (-offset if cross_index % 2 == 0 else offset)
			# Keep the outer lots beyond the connector sidewalks while retaining a
			# short approach from each cross-street cul-de-sac.
			var cross_xs := [70.0, 70.0, 550.0, 700.0, 1100.0, 1250.0, 1730.0, 1730.0]
			if _is_wedge(i):
				_house_positions.append(_bulb_center(i) + Vector2.from_angle(_wedge_angle(i)) * WEDGE_R)
			else:
				_house_positions.append(Vector2(cross_xs[cross_index % 8], y))
			continue
		var candidate := WORLD_H - HOUSE_MARGIN - i * HOUSE_SPACING
		# Keep main-avenue lots clear of intersecting and winding roads. This
		# search runs once during setup; drawing uses the cached result.
		var direction := -1.0 if i % 4 < 2 else 1.0
		for attempt in 20:
			var house_x := _road_x(candidate) + _side(i) * (ROAD_HALF + WALK_W + YARD_GAP + HOUSE_W * 0.5)
			if _public_road_distance(Vector2(house_x, candidate), false) >= 210.0:
				break
			candidate = clampf(candidate + direction * 24.0, 180.0, WORLD_H - 180.0)
		var x := _road_x(candidate) + _side(i) * (ROAD_HALF + WALK_W + YARD_GAP + HOUSE_W * 0.5)
		_house_positions.append(Vector2(x, candidate))


func _side(i: int) -> int:
	if i >= MAIN_HOUSE_COUNT:
		return -1 if (i - MAIN_HOUSE_COUNT) % 2 == 0 else 1
	return -1 if i % 2 == 0 else 1


func _house_c(i: int) -> Vector2:
	return _house_positions[i]


func _house_rotation(i: int) -> float:
	if _is_wedge(i):
		var toward := -Vector2.from_angle(_wedge_angle(i))
		return toward.angle() if _side(i) < 0 else toward.angle() + PI
	return PI * 0.5 if i >= MAIN_HOUSE_COUNT else 0.0


## Cul-de-sac lots fan out around the bulb instead of sitting on a straight street.
func _is_wedge(i: int) -> bool:
	return i >= MAIN_HOUSE_COUNT and (i - MAIN_HOUSE_COUNT) % 8 in [0, 1, 6, 7]


func _bulb_center(i: int) -> Vector2:
	var cross_index := i - MAIN_HOUSE_COUNT
	var junction_y := float(JUNCTIONS[int(cross_index / 8)])
	return Vector2(CULDESAC_X if cross_index % 8 < 2 else WORLD_W - CULDESAC_X, junction_y)


func _wedge_angle(i: int) -> float:
	var cross_index := i - MAIN_HOUSE_COUNT
	var up := cross_index % 2 == 0
	var degrees := 100.0 if cross_index % 8 < 2 else 80.0
	return deg_to_rad(-degrees if up else degrees)


## Unit vector from the house toward its street.
func _front_dir(i: int) -> Vector2:
	if _is_wedge(i):
		return -Vector2.from_angle(_wedge_angle(i))
	if i >= MAIN_HOUSE_COUNT:
		return Vector2(0.0, -float(_side(i)))
	return Vector2(-float(_side(i)), 0.0)


func _wedge_polygon(i: int) -> PackedVector2Array:
	var center := _bulb_center(i) - Vector2(_cam_x, _cam)
	var a := _wedge_angle(i)
	var r_in := ROAD_HALF + WALK_W + 4.0
	var r_out := WEDGE_R + HOUSE_W * 0.5 + 30.0
	var pts := PackedVector2Array()
	for k in 9:
		pts.append(center + Vector2.from_angle(a - WEDGE_HALF + WEDGE_HALF * 2.0 * k / 8.0) * r_in)
	for k in 9:
		pts.append(center + Vector2.from_angle(a + WEDGE_HALF - WEDGE_HALF * 2.0 * k / 8.0) * r_out)
	return pts


func _address(i: int) -> String:
	return "%d %s" % [101 + i * 2, "COURT" if i >= MAIN_HOUSE_COUNT else "HOA WAY"]


func _road_x(wy: float) -> float:
	return WORLD_W * 0.5 + sin(wy / 430.0) * 70.0 + sin(wy / 170.0) * 20.0


## pins: house index -> "lawn" | "card". grass: tall-grass height in inches per house.
func set_day(pins: Dictionary, grass: Array, completed := 0, saved_position = null,
		evidence: Dictionary = {}, property_violations: Dictionary = {}) -> void:
	_pins = pins.duplicate()
	_grass = grass.duplicate()
	_evidence = evidence.duplicate(true)
	_property_violations = property_violations.duplicate(true)
	_day_total = maxi(pins.size(), 1)
	_day_done = int(completed)
	_walker_variant = (GameState.day - 1) % 4
	_weather = (GameState.day - 1) % 3
	if saved_position is Vector2 and saved_position.y >= 0.0:
		_player_y = clampf(saved_position.y, 140.0, WORLD_H - 140.0)
		_player_x = saved_position.x if saved_position.x >= 0.0 else _road_x(_player_y)
	else:
		_player_x = _road_x(_player_y) + SIDEWALK_CENTER
	_season = GameState.season()
	_weekend = GameState.is_weekend()
	_refresh_static_obstacles()
	_build_ambient()
	_update_dusk()


func get_player_y() -> float:
	return _player_y


func get_player_position() -> Vector2:
	return Vector2(_player_x, _player_y)


func get_evidence() -> Dictionary:
	return _evidence.duplicate(true)


func mark_done(house: int) -> void:
	_pins[house] = "done"
	_bubble = "INSPECTION COMPLETE · %s" % _address(house)
	_bubble_t = 2.8
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
			elif not (_map_open or _camera_mode or _gallery_open):
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
	if _gallery_open:
		return _tap_gallery(pos)
	if _map_open:
		_map_open = false
		queue_redraw()
		return true
	var buttons := _zoom_buttons()
	if _camera_mode:
		if (buttons.cancel as Rect2).has_point(pos):
			_camera_mode = false
		elif (buttons.minus as Rect2).has_point(pos):
			_zoom = clampf(_zoom - 0.3, ZOOM_MIN, ZOOM_MAX)
		elif (buttons.plus as Rect2).has_point(pos):
			_zoom = clampf(_zoom + 0.3, ZOOM_MIN, ZOOM_MAX)
		elif pos.distance_to(Vector2(size.x - 66.0, size.y - 72.0)) <= 48.0:
			_take_photo()
		return true
	if pos.distance_to(Vector2(size.x - 66.0, size.y - 72.0)) <= 48.0:
		if _near >= 0 and _pins.get(_near, "") in ["lawn", "card"]:
			_camera_mode = true
			_zoom = 1.4
			_photo_message = "FRAME THE VIOLATION"
			_photo_message_t = 2.0
		else:
			_photo_message = "MOVE CLOSER TO INSPECT"
			_photo_message_t = 2.0
		return true
	if pos.distance_to(Vector2(size.x - 66.0, size.y - 172.0)) <= 38.0:
		_gallery_open = true
		_gallery_page = 0
		_gallery_sel = -1
		return true
	if pos.distance_to(Vector2(size.x - 66.0, size.y - 262.0)) <= 38.0:
		_cart = not _cart
		_photo_message = "GOLF CART ON" if _cart else "ON FOOT"
		_photo_message_t = 1.6
		return true
	if pos.x >= size.x - MINI_MAP_SIZE.x - 16.0 and pos.y <= MINI_MAP_SIZE.y + 16.0:
		_map_open = true
		queue_redraw()
		return true
	pos = _screen_to_world_draw(pos)
	for i in HOUSE_COUNT:
		var kind: String = _pins.get(i, "")
		if kind != "lawn" and kind != "card":
			continue
		var pin := _house_c(i) - Vector2(_cam_x, _cam) + Vector2(0, -18.0)
		var house_rect := Rect2(pin - Vector2(HOUSE_W * 0.6, HOUSE_D * 0.6), Vector2(HOUSE_W * 1.2, HOUSE_D * 1.2))
		if i == _near and (pos.distance_to(pin) <= 72.0 or house_rect.has_point(pos)):
			visit.emit(i)
			return true
	return false


func _process(delta: float) -> void:
	_time += delta
	_bubble_t = maxf(0.0, _bubble_t - delta)
	var move := _stick
	if _map_open or _camera_mode or _gallery_open:
		move = Vector2.ZERO
	elif not _dragging:
		move = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_action_just_pressed("ui_accept"):
			_enter_near()
	if move.length() > DEADZONE:
		var strength := (move.length() - DEADZONE) / (1.0 - DEADZONE)
		var velocity := move.normalized() * WALK_SPEED * strength * (CART_SPEED if _cart else 1.0)
		var previous := Vector2(_player_x, _player_y)
		var candidate := previous + velocity * delta
		candidate.y = fposmod(candidate.y, WORLD_H)
		candidate.x = fposmod(candidate.x, WORLD_W)
		candidate = _keep_on_street_network(previous, candidate)
		candidate = _avoid_neighbors(previous, candidate)
		candidate = _keep_clear_of_cars(previous, candidate)
		candidate = _keep_clear_of_obstacles(previous, candidate)
		_player_x = candidate.x
		_player_y = candidate.y
		_face = velocity.angle() + PI * 0.5
		_phase += delta * 10.0 * strength
		_moving = true
	else:
		_moving = false
	_update_ambient(delta)
	var target_scale := WALK_WORLD_SCALE if _moving else 1.0
	if _camera_mode:
		target_scale = _zoom
	_world_scale = lerpf(_world_scale, target_scale, 1.0 - exp(-5.0 * delta))
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
		var segment := _driveway_segment(i)
		if Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1]).distance_to(point) <= DRIVEWAY_HALF:
			return i
	return -1


func _driveway_segment(i: int) -> PackedVector2Array:
	var home := _house_c(i)
	if _is_wedge(i):
		var radial := Vector2.from_angle(_wedge_angle(i))
		return PackedVector2Array([_bulb_center(i) + radial * (ROAD_HALF + WALK_W), home - radial * HOUSE_W * 0.46])
	if i >= MAIN_HOUSE_COUNT:
		var junction := float(JUNCTIONS[int((i - MAIN_HOUSE_COUNT) / 8)])
		return PackedVector2Array([Vector2(home.x, junction + _side(i) * (ROAD_HALF + WALK_W)),
				Vector2(home.x, home.y - _side(i) * HOUSE_D * 0.46)])
	return PackedVector2Array([Vector2(_road_x(home.y) + _side(i) * (ROAD_HALF + WALK_W), home.y),
			Vector2(home.x - _side(i) * HOUSE_W * 0.46, home.y)])


func _keep_on_street_network(previous: Vector2, candidate: Vector2) -> Vector2:
	if _is_walkable(candidate):
		return candidate
	var horizontal := Vector2(candidate.x, previous.y)
	if _is_walkable(horizontal):
		return horizontal
	var vertical := Vector2(previous.x, candidate.y)
	if _is_walkable(vertical):
		return vertical
	return previous


func _is_walkable(point: Vector2) -> bool:
	var allowance := ROAD_HALF + WALK_W * 0.9
	if _public_road_distance(point) <= allowance:
		return true
	return _driveway_at(point) >= 0


func _public_road_distance(point: Vector2, include_main := true) -> float:
	var best := INF
	if include_main:
		best = absf(point.x - _road_x(point.y))
	for junction in JUNCTIONS:
		var street_start := Vector2(CULDESAC_X, float(junction))
		var street_end := Vector2(WORLD_W - CULDESAC_X, float(junction))
		best = minf(best, Geometry2D.get_closest_point_to_segment(point, street_start, street_end).distance_to(point))
	for connector in CONNECTOR_XS:
		if point.y >= float(JUNCTIONS[0]) and point.y <= float(JUNCTIONS[-1]):
			best = minf(best, absf(point.x - float(connector)))
	for lane_i in CURVED_LANE_COUNT:
		var previous_lane_point := _curved_lane_point(lane_i, 0.0)
		for point_i in range(1, 25):
			var lane_point := _curved_lane_point(lane_i, float(point_i) / 24.0)
			best = minf(best, Geometry2D.get_closest_point_to_segment(
					point, previous_lane_point, lane_point).distance_to(point))
			previous_lane_point = lane_point
	return best


func _curved_lane_point(lane_i: int, t: float) -> Vector2:
	var lane_y := WORLD_H * (0.14 + lane_i * 0.144)
	return Vector2(90.0 + t * (WORLD_W - 180.0),
			lane_y + sin(t * TAU * 1.5 + lane_i * 1.7) * (72.0 + lane_i * 9.0))


func _neighbor_position(neighbor: Dictionary, avoid_player := true) -> Vector2:
	var route := int(neighbor.route)
	var result: Vector2
	if route == 0:
		var wy := fposmod(float(neighbor.seed) + _time * float(neighbor.speed), WORLD_H - 280.0) + 140.0
		result = Vector2(_road_x(wy) + int(neighbor.side) * SIDEWALK_CENTER, wy)
	else:
		var top := float(JUNCTIONS[0])
		var span := float(JUNCTIONS[-1]) - top
		var wy := top + fposmod(float(neighbor.seed) + _time * float(neighbor.speed), span)
		result = Vector2(float(CONNECTOR_XS[route - 1]) + int(neighbor.side) * SIDEWALK_CENTER, wy)
	if avoid_player and absf(result.y - _player_y) < 92.0 and absf(result.x - _player_x) < 58.0:
		var strength := 1.0 - absf(result.y - _player_y) / 92.0
		var pass_side := float(neighbor.side)
		if is_zero_approx(pass_side):
			pass_side = 1.0
		result.x += pass_side * 58.0 * strength
	return result


func _dynamic_circles() -> Array:
	var circles: Array = []
	for neighbor in _neighbors:
		circles.append(_neighbor_position(neighbor))
	for k in _kids:
		circles.append(_kid_position(k))
	for crew in _crews:
		circles.append(_crew_worker_position(crew))
	return circles


## Side-passes pedestrians, kids and crews instead of stopping dead behind them.
func _avoid_neighbors(previous: Vector2, candidate: Vector2) -> Vector2:
	var push := Vector2.ZERO
	var too_close := false
	var heading := candidate - previous
	for other: Vector2 in _dynamic_circles():
		var d := candidate.distance_to(other)
		if d >= 52.0 or d < 0.01:
			continue
		var away := (candidate - other) / d
		var tangent := Vector2(-away.y, away.x)
		if tangent.dot(heading) < 0.0:
			tangent = -tangent
		push += away * (52.0 - d) * 0.5 + tangent * (52.0 - d) * 0.35
		too_close = too_close or d < 26.0
	if push == Vector2.ZERO:
		return candidate
	var pushed := candidate + push
	if _is_walkable(pushed):
		return pushed
	return previous if too_close else candidate


func _keep_clear_of_obstacles(previous: Vector2, candidate: Vector2) -> Vector2:
	for rect in _obstacles:
		var r: Rect2 = (rect as Rect2).grow(14.0)
		if not r.has_point(candidate):
			continue
		if not r.has_point(Vector2(candidate.x, previous.y)):
			candidate.y = previous.y
		elif not r.has_point(Vector2(previous.x, candidate.y)):
			candidate.x = previous.x
		else:
			candidate = previous
	return candidate


func _screen_to_world_draw(point: Vector2) -> Vector2:
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	var scale := Vector2(_world_scale, _world_scale * WORLD_TILT)
	return center + (point - center) / scale


func _camera_frame_rect() -> Rect2:
	return Rect2(size.x * 0.12, size.y * 0.2, size.x * 0.76, size.y * 0.56)


func _zoom_buttons() -> Dictionary:
	var frame := _camera_frame_rect()
	return {
		"minus": Rect2(frame.position.x, frame.end.y + 14.0, 76.0, 60.0),
		"plus": Rect2(frame.position.x + 88.0, frame.end.y + 14.0, 76.0, 60.0),
		"cancel": Rect2(frame.end.x - 76.0, frame.position.y - 70.0, 76.0, 54.0),
	}


func _to_screen(world: Vector2) -> Vector2:
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	var scale := Vector2(_world_scale, _world_scale * WORLD_TILT)
	return center + (world - Vector2(_cam_x, _cam) - center) * scale


## Scores the current framing: how much of the lot is in shot, how close the
## inspector stands, and whether the zoom is sensible. Violations whose objects
## are inside the frame count as documented.
func _evaluate_frame() -> Dictionary:
	if _near < 0:
		return {"house": -1, "quality": 0, "documented": []}
	var home := _house_c(_near)
	var frame := _camera_frame_rect()
	var corner_a := _to_screen(home - Vector2(72.0, 72.0))
	var corner_b := _to_screen(home + Vector2(72.0, 72.0))
	var lot := Rect2(corner_a, corner_b - corner_a).abs()
	var coverage := 0.0
	if lot.get_area() > 0.0:
		coverage = lot.intersection(frame).get_area() / lot.get_area()
	var dist := Vector2(_player_x, _player_y).distance_to(home)
	var dist_factor := clampf(1.0 - (dist - 70.0) / 180.0, 0.15, 1.0)
	var zoom_factor := 1.0 if _zoom >= 1.2 and _zoom <= 2.0 else 0.6
	var quality := (0.45 * coverage + 0.35 * dist_factor + 0.2 * zoom_factor) * (1.0 - 0.2 * _dusk) * 100.0
	var documented: Array = []
	if coverage >= 0.35:
		for entry in _violation_layout(_near):
			if frame.has_point(_to_screen(entry.pos)):
				documented.append(str(entry.v.get("id", "")))
	return {"house": _near, "quality": roundi(quality), "documented": documented}


func _take_photo() -> void:
	var info := _evaluate_frame()
	var house: int = info.house
	if house < 0:
		_photo_message = "NO PROPERTY IN RANGE"
		_photo_message_t = 2.0
		return
	var quality: int = info.quality
	var key := "%d:%d:%d" % [roundi(_player_x / 45.0), roundi(_player_y / 45.0), roundi(_zoom * 3.0)]
	var entry: Dictionary = _evidence.get(house, {}).duplicate(true)
	var keys: Array = entry.get("keys", [])
	if key in keys:
		_photo_message = "DUPLICATE · MOVE OR ZOOM"
		_photo_message_t = 2.2
		return
	if quality < USABLE_QUALITY:
		_photo_message = "UNUSABLE %d%% · CLOSER / RECENTER" % quality
		_photo_message_t = 2.4
		photo_taken.emit(house, quality, false, [])
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://evidence-lot-%03d-%s.png" % [101 + house * 2, stamp]
	# Hide HUD for one frame so the saved photo is just the framed scene.
	_capturing = true
	queue_redraw()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_capturing = false
	var vp := get_viewport_rect().size
	var ratio := float(image.get_width()) / maxf(vp.x, 1.0)
	var frame := _camera_frame_rect()
	var origin := frame.position + global_position
	var region := Rect2i(int(origin.x * ratio), int(origin.y * ratio), int(frame.size.x * ratio), int(frame.size.y * ratio))
	region = region.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if region.has_area():
		image = image.get_region(region)
	var error := image.save_png(path)
	_camera_mode = false
	if error != OK:
		_photo_message = "CAMERA ERROR"
		_photo_message_t = 2.2
		return
	var documented: Array = entry.get("documented", [])
	var newly: Array = []
	for id in info.documented:
		if not id in documented:
			documented.append(id)
			newly.append(id)
	keys.append(key)
	var best := int(entry.get("quality", 0))
	var improved := quality >= best
	_evidence[house] = {
		"path": path if improved else str(entry.get("path", path)),
		"time": stamp if improved else str(entry.get("time", stamp)),
		"address": _address(house),
		"category": str(_pins.get(house, "inspection")),
		"quality": maxi(quality, best),
		"documented": documented,
		"shots": int(entry.get("shots", 0)) + 1,
		"keys": keys,
	}
	_photo_message = ("EVIDENCE SAVED · %d%%" % quality) if improved else "KEPT BEST SHOT · %d%%" % best
	_photo_message_t = 2.2
	_camera_flash = 1.0
	photo_taken.emit(house, quality, true, newly)
	queue_redraw()


func _keep_clear_of_cars(previous: Vector2, candidate: Vector2) -> Vector2:
	for car in _cars:
		var car_pos := Vector2(_road_x(float(car.y)) + int(car.side) * PARK_X, float(car.y))
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
	_draw_season_particles(w, h)
	_draw_pet_stations()
	for car in _cars:
		if _on_screen(car.y):
			_draw_car_at(_road_x(car.y) - _cam_x + car.side * PARK_X, car.y - _cam, car.col, CAR_SCALE, 0.0)
	_draw_traffic()
	_draw_crews()
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
			_set_world_transform(_house_c(i) - Vector2(_cam_x, _cam), focus_scale, _house_rotation(i))
			_draw_house(i, sh / focus_scale)
			_set_world_transform()
	for t in _trees:
		if _on_screen(t.y):
			var sway := sin(_time * 1.3 + float(t.phase)) * 3.0
			var tc := Vector2(_road_x(t.y) - _cam_x + t.side * (ROAD_HALF + WALK_W + t.off + t.r) + sway, t.y - _cam)
			draw_line(tc + Vector2(0, 30.0), tc + Vector2(-sway * 0.4, -8.0), Color("6b4931"), 10.0, true)
			var g: Color = (SEASON_LEAF[_season] as Color).lightened(float(t.tone)).lerp(Color("1c5a3e"), _dusk * 0.7)
			_ellipse(tc, t.r, t.r * 0.9, g)
			_ellipse(tc + Vector2(-t.r * 0.28, -t.r * 0.2), t.r * 0.62, t.r * 0.58, g.lightened(0.12))
			_ellipse(tc + Vector2(t.r * 0.3, -t.r * 0.08), t.r * 0.48, t.r * 0.5, g.darkened(0.08))
	for i in HOUSE_COUNT:
		if _on_screen(house_y(i), 320.0):
			_draw_highlight(i)
			_draw_pin(i)
	_draw_neighbors()
	_draw_kids()
	if _cart:
		_draw_cart(Vector2(_player_x - _cam_x, _player_y - _cam))
	_draw_walker(Vector2(_player_x - _cam_x, _player_y - _cam))
	if _dusk > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.1, 0.32, 0.4 * _dusk))
	if _gloom > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(0.25, 0.27, 0.32, 0.4 * _gloom))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _capturing:
		return
	_draw_ui(w, h)
	if _camera_mode:
		_draw_camera_frame(w, h)
	if _map_open:
		_draw_full_map(w, h)
	if _gallery_open:
		_draw_gallery(w, h)
	if _camera_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, _camera_flash * 0.72))


func _set_world_transform(focus := Vector2.ZERO, focus_scale := 1.0, rotation := 0.0) -> void:
	var base_scale := Vector2(_world_scale, _world_scale * WORLD_TILT)
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	var base_origin := center * (Vector2.ONE - base_scale)
	var scaled_focus := base_scale * focus_scale * focus
	var rotated_focus := scaled_focus.rotated(rotation)
	var origin := base_origin + base_scale * focus - rotated_focus
	draw_set_transform(origin, rotation, base_scale * focus_scale)


func _draw_ground(w: float, h: float, cx: float) -> void:
	var lawn: Color = (SEASON_LAWN[_season] as Color).lerp(Color("2c7050"), _dusk * 0.7)
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
	var bottom_y := float(JUNCTIONS[-1]) + ROAD_HALF + WALK_W
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
			var street_x := CULDESAC_X - _cam_x
			var street_w := WORLD_W - CULDESAC_X * 2.0
			draw_rect(Rect2(street_x, sy - ROAD_HALF, street_w, ROAD_HALF * 2.0), road)
			draw_rect(Rect2(street_x, sy - ROAD_HALF - WALK_W, street_w, WALK_W), walk)
			draw_rect(Rect2(street_x, sy + ROAD_HALF, street_w, WALK_W), walk)
			for end_x in [CULDESAC_X, WORLD_W - CULDESAC_X]:
				var end_c := Vector2(float(end_x) - _cam_x, sy)
				draw_circle(end_c, ROAD_HALF + WALK_W, walk)
				draw_circle(end_c, ROAD_HALF, road)
				draw_circle(end_c, 22.0, Color("4f9b64").lerp(Color("274c42"), _dusk * 0.6))
			for wx in range(int(CULDESAC_X), int(WORLD_W - CULDESAC_X), 90):
				draw_line(Vector2(wx - _cam_x, sy), Vector2(wx + 44.0 - _cam_x, sy), Color("ffe08a", 0.7), 4.0)
	# Curving residential lanes break up the grid and make the neighborhood feel
	# grown-in. They meet the main avenue at their ends and weave through blocks.
	for lane_i in CURVED_LANE_COUNT:
		var lane := PackedVector2Array()
		for point_i in 15:
			var t := float(point_i) / 14.0
			lane.append(_curved_lane_point(lane_i, t) - Vector2(_cam_x, _cam))
		draw_polyline(lane, walk, ROAD_HALF * 2.0 + WALK_W * 2.0, true)
		draw_polyline(lane, road, ROAD_HALF * 2.0, true)
		draw_polyline(lane, Color("ffe08a", 0.68), 4.0, true)
		for t in [0.0, 1.0]:
			var end_c := _curved_lane_point(lane_i, t) - Vector2(_cam_x, _cam)
			draw_circle(end_c, ROAD_HALF + WALK_W, walk)
			draw_circle(end_c, ROAD_HALF, road)
			draw_circle(end_c, 20.0, Color("4f9b64").lerp(Color("274c42"), _dusk * 0.6))
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


func _draw_season_particles(w: float, h: float) -> void:
	if _season == 3:
		for i in 28:
			var x := fposmod(i * 61.0 + sin(_time + i) * 14.0, w)
			var y := fposmod(i * 97.0 + _time * (30.0 + i % 5 * 6.0), h + 20.0) - 10.0
			draw_circle(Vector2(x, y), 2.0 + i % 3, Color(1, 1, 1, 0.8))
	elif _season == 2:
		for i in 12:
			var x := fposmod(i * 83.0 + _time * 24.0, w + 40.0) - 20.0
			var y := fposmod(i * 131.0 + _time * 36.0, h + 40.0) - 20.0
			draw_circle(Vector2(x, y), 4.0, [Color("d9822b"), Color("b5482a"), Color("e0b03a")][i % 3])


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
	for neighbor in _neighbors:
		var world_pos := _neighbor_position(neighbor)
		var wy := world_pos.y
		var wx := world_pos.x
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
	if i >= MAIN_HOUSE_COUNT:
		var hc := _house_c(i) - Vector2(_cam_x, _cam)
		return Rect2(hc.x - HOUSE_W * 0.65, hc.y - 104.0, HOUSE_W * 1.3, 208.0)
	var cx := _road_x(house_y(i)) - _cam_x
	var x0 := (cx + ROAD_HALF + WALK_W) if _side(i) > 0 else (cx - ROAD_HALF - WALK_W - YARD_GAP)
	return Rect2(x0, house_y(i) - 100.0 - _cam, YARD_GAP, 200.0)


func _draw_yard(i: int) -> void:
	var r := _yard_rect(i)
	var driveway := _driveway_segment(i)
	var drive_start := driveway[0] - Vector2(_cam_x, _cam)
	var drive_end := driveway[1] - Vector2(_cam_x, _cam)
	var inches: float = _grass[i]
	var tall := clampf((inches - 3.0) / 7.0, 0.0, 1.0)
	var yard_col: Color = Color("3f9e60").lerp(SEASON_LAWN[_season].darkened(0.12), 0.55)
	yard_col = yard_col.lerp(Color("b2b04a"), tall * 0.5).lerp(Color("1c5a3e"), _dusk * 0.5)
	var wedge := PackedVector2Array()
	if _is_wedge(i):
		wedge = _wedge_polygon(i)
		draw_colored_polygon(wedge, yard_col)
		var minp := wedge[0]
		var maxp := wedge[0]
		for q in wedge:
			minp = Vector2(minf(minp.x, q.x), minf(minp.y, q.y))
			maxp = Vector2(maxf(maxp.x, q.x), maxf(maxp.y, q.y))
		r = Rect2(minp, maxp - minp)
	else:
		_rr(r, yard_col, 10)
	var base := Color("2f9e57").lerp(Color("1c5a3e"), _dusk * 0.7)
	for t in _tufts:
		var p := Vector2(r.position.x + 6.0 + t.x * (r.size.x - 12.0), r.position.y + 8.0 + t.y * (r.size.y - 12.0))
		if not wedge.is_empty() and not Geometry2D.is_point_in_polygon(p, wedge):
			continue
		var len: float = inches * INCH_PX * t.h
		for a in [-0.55, 0.0, 0.55]:
			var ang: float = a + t.a + sin(_time * 1.6 + p.y * 0.05) * 0.06
			draw_line(p, p + Vector2(sin(ang), -cos(ang)) * len, base.lightened(float(t.h) * 0.2 - 0.1), 2.0, true)
	# Draw pavement after the lawn so the driveway is a short, visible connection
	# from the sidewalk edge to the entrance—not a stripe painted across the road.
	draw_line(drive_start, drive_end, Color("b8b3a8").lerp(Color("686477"), _dusk * 0.5), DRIVEWAY_HALF * 1.55, true)
	draw_line(drive_start, drive_end, Color(1, 1, 1, 0.16), 3.0, true)
	_draw_lot_details(i, r, drive_start, drive_end)
	_draw_yard_violations(i)


func _draw_lot_details(i: int, yard: Rect2, curb: Vector2, entrance: Vector2) -> void:
	# A curb mailbox and foundation beds make the lot direction readable even
	# before the house is close enough to focus.
	var drive_dir := (entrance - curb).normalized()
	var normal := Vector2(-drive_dir.y, drive_dir.x)
	var mailbox := curb + normal * 24.0
	draw_line(mailbox, mailbox + Vector2(0, -18), Color("5b4634"), 4.0, true)
	_rr(Rect2(mailbox + Vector2(-8, -27), Vector2(16, 11)), Color("344b59"), 3)
	for shrub_i in 3:
		var t := (float(shrub_i) + 1.0) / 4.0
		var shrub := entrance.lerp(curb, t) - normal * 28.0
		_ellipse(shrub, 8.0 + shrub_i * 1.5, 6.0, Color("257149").lightened(i % 3 * 0.05))
	var kind := str(_pins.get(i, ""))
	if kind == "lawn":
		for weed_i in 7:
			var wx := yard.position.x + 12.0 + fposmod(float(i * 31 + weed_i * 23), maxf(20.0, yard.size.x - 24.0))
			var wy := yard.position.y + 18.0 + fposmod(float(i * 19 + weed_i * 37), maxf(24.0, yard.size.y - 36.0))
			draw_line(Vector2(wx, wy), Vector2(wx + (weed_i % 3 - 1) * 4.0, wy - 18.0), Color("d4c54c"), 3.0, true)
	if i % 13 == 0:
		var patio := yard.position + yard.size * Vector2(0.72, 0.72)
		_ellipse(patio, 18.0, 12.0, Color("4aa9c7", 0.8))
	elif i % 9 == 0:
		var shed := yard.position + yard.size * Vector2(0.72, 0.25)
		_rr(Rect2(shed - Vector2(13, 11), Vector2(26, 22)), Color("9a6d45"), 3)


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
	_draw_house_violations(i, c, side, rect)


const HOUSE_OBJECTS := ["paint", "siding", "addition", "rental", "noise", "damage"]
const OBJECT_SLOTS := {"bins": 4, "hoop": 5, "sign": 5, "dead_lawn": 0, "weeds": 1, "rv": 2, "boat": 3,
		"van": 2, "car": 0, "shed": 3, "fence": 1, "decorations": 1, "shrubs": 0, "debris": 3, "dog": 1}
const OBJECT_HALF := {"rv": Vector2(22, 42), "boat": Vector2(18, 38), "van": Vector2(22, 40),
		"car": Vector2(24, 44), "shed": Vector2(16, 14), "bins": Vector2(14, 14), "hoop": Vector2(14, 14),
		"debris": Vector2(24, 20)}


## Where each alleged violation physically sits for lot `i`. Real violations get an
## object; false complaints show nothing, so the photo is the proof.
func _violation_layout(i: int) -> Array:
	var result: Array = []
	var used: Array = []
	var home := _house_c(i)
	var f := _front_dir(i)
	var n := Vector2(-f.y, f.x)
	var curb := _driveway_segment(i)[0]
	for v in _property_violations.get(i, []):
		if not bool(v.get("actual", false)):
			continue
		var obj := str(v.get("object", ""))
		var pos := home
		var slot := -1
		if not obj in HOUSE_OBJECTS:
			slot = int(OBJECT_SLOTS.get(obj, 0))
			while slot in used and slot < 4:
				slot = (slot + 1) % 4
			used.append(slot)
			match slot:
				0: pos = home + f * (HOUSE_W * 0.5 + 40.0) + n * 52.0
				1: pos = home + f * (HOUSE_W * 0.5 + 40.0) - n * 52.0
				2: pos = home - f * (HOUSE_W * 0.5 + 44.0) + n * 40.0
				3: pos = home - f * (HOUSE_W * 0.5 + 44.0) - n * 40.0
				4: pos = curb + n * 34.0
				_: pos = curb - n * 34.0 + f * (WALK_W * 0.6 if obj == "hoop" else 0.0)
		result.append({"v": v, "object": obj, "pos": pos, "slot": slot,
				"scale": 0.7 if bool(v.get("borderline", false)) else 1.0})
	return result


func _refresh_static_obstacles() -> void:
	_static_obstacles.clear()
	for house in _property_violations:
		for entry in _violation_layout(int(house)):
			if OBJECT_HALF.has(entry.object):
				var half: Vector2 = OBJECT_HALF[entry.object] * float(entry.scale)
				_static_obstacles.append(Rect2(entry.pos - half, half * 2.0))


func _draw_yard_violations(i: int) -> void:
	for entry in _violation_layout(i):
		if entry.slot >= 0:
			_draw_object(str(entry.object), entry.pos - Vector2(_cam_x, _cam), float(entry.scale), i)


func _draw_object(obj: String, p: Vector2, s: float, i: int) -> void:
	var shade := Color(0, 0, 0, 0.2)
	match obj:
		"weeds":
			for k in 9:
				var q := p + Vector2(sin(k * 2.1) * 20.0, cos(k * 1.7) * 14.0) * s
				draw_line(q, q + Vector2(sin(k) * 4.0, -24.0 * s), Color("d4c54c"), 3.0, true)
		"dead_lawn":
			_ellipse(p, 32.0 * s, 24.0 * s, Color("a38b48"))
			_ellipse(p + Vector2(8, 4) * s, 14.0 * s, 10.0 * s, Color("7d6a38"))
		"bins":
			for b in 2:
				var bc := p + Vector2(0, -11.0 + b * 22.0) * s
				_rr(Rect2(bc - Vector2(9, 11) * s, Vector2(18, 22) * s), Color("315b74") if b == 0 else Color("3f7654"), 3)
				draw_line(bc + Vector2(-8, -7) * s, bc + Vector2(8, -7) * s, Color("1d2d35"), 3.0)
		"rv":
			_ellipse(p + Vector2(7, 9), 26.0 * s, 44.0 * s, shade)
			_rr(Rect2(p + Vector2(-22, -42) * s, Vector2(44, 84) * s), Color("f0eee6"), 7)
			_rr(Rect2(p + Vector2(-16, -38) * s, Vector2(32, 18) * s), Color("8fb8cf"), 4)
			draw_line(p + Vector2(-22, 6) * s, p + Vector2(22, 6) * s, Color("c4543e"), 5.0 * s)
			draw_string(ThemeDB.fallback_font, p + Vector2(-20, 32) * s, "RV", HORIZONTAL_ALIGNMENT_CENTER, 40.0 * s, int(16.0 * s), Color("4a4f58"))
		"boat":
			_ellipse(p + Vector2(6, 8), 22.0 * s, 40.0 * s, shade)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-17, -10) * s, p + Vector2(0, -42) * s,
					p + Vector2(17, -10) * s, p + Vector2(14, 36) * s, p + Vector2(-14, 36) * s]), Color("e8ecef"))
			draw_polyline(PackedVector2Array([p + Vector2(-17, -10) * s, p + Vector2(0, -42) * s,
					p + Vector2(17, -10) * s, p + Vector2(14, 36) * s, p + Vector2(-14, 36) * s, p + Vector2(-17, -10) * s]),
					Color("2f5d8a"), 3.0)
			_rr(Rect2(p + Vector2(-9, -2) * s, Vector2(18, 20) * s), Color("2f5d8a"), 3)
		"van":
			_ellipse(p + Vector2(7, 9), 25.0 * s, 42.0 * s, shade)
			_rr(Rect2(p + Vector2(-22, -40) * s, Vector2(44, 80) * s), Color("f2b632"), 6)
			_rr(Rect2(p + Vector2(-16, -38) * s, Vector2(32, 14) * s), Color("8fb8cf"), 3)
			draw_string(ThemeDB.fallback_font, p + Vector2(-20, 6) * s, "ACME", HORIZONTAL_ALIGNMENT_CENTER, 40.0 * s, int(13.0 * s), Color("1c1b1f"))
		"car":
			var broken := false
			for v in _property_violations.get(i, []):
				if str(v.get("id", "")) == "broken_vehicle":
					broken = true
			_draw_car(p.x, p.y, Color("767c86") if broken else Color("3a6fd8"))
			if broken:
				draw_line(p + Vector2(-16, -8), p + Vector2(16, 18), Color("e0533d"), 4.0)
				draw_line(p + Vector2(16, -8), p + Vector2(-16, 18), Color("e0533d"), 4.0)
		"shed":
			_rr(Rect2(p + Vector2(-16, -14) * s, Vector2(32, 28) * s), Color("9a6d45"), 3)
			draw_line(p + Vector2(0, -14) * s, p + Vector2(0, 14) * s, Color("6f4a2c"), 2.0)
		"fence":
			for k in 6:
				var q := p + Vector2(0, -40.0 + k * 16.0) * s
				draw_line(q, q + Vector2(0, 11.0), Color("efe0bd"), 5.0)
			draw_line(p + Vector2(0, -40) * s, p + Vector2(0, 56) * s, Color("cbb995"), 2.0)
		"hoop":
			draw_line(p, p + Vector2(0, -34) * s, Color("52616f"), 4.0)
			_rr(Rect2(p + Vector2(-13, -48) * s, Vector2(26, 16) * s), Color("f4f4f4"), 2)
			draw_circle(p + Vector2(0, -28) * s, 6.0 * s, Color("e07a1f"), false, 2.5)
		"sign":
			draw_line(p, p + Vector2(0, -22) * s, Color("5b4634"), 3.0)
			_rr(Rect2(p + Vector2(-14, -38) * s, Vector2(28, 18) * s), Color("e0533d"), 3)
			draw_line(p + Vector2(-8, -29) * s, p + Vector2(8, -29) * s, Color.WHITE, 2.0)
		"decorations":
			_ellipse(p, 16.0 * s, 20.0 * s, Color("d94b45"))
			draw_circle(p + Vector2(0, -22) * s, 8.0 * s, Color("f2c29b"))
			for k in 6:
				draw_circle(p + Vector2(-24 + k * 10, 24) * s, 3.0, [Color("ffd36e"), Color("ff6b5a"), Color("7ee081")][k % 3])
		"shrubs":
			for k in 3:
				_ellipse(p + Vector2(-14 + k * 14, sin(k * 2.0) * 8.0) * s, 20.0 * s, 17.0 * s, Color("1f6b43").lightened(k * 0.05))
		"debris":
			_rr(Rect2(p + Vector2(-24, -20) * s, Vector2(48, 40) * s), Color("d9822b"), 3)
			draw_rect(Rect2(p + Vector2(-24, -20) * s, Vector2(48, 40) * s), Color("8a4f12"), false, 2.0)
			for k in 4:
				draw_circle(p + Vector2(-14 + k * 9, -4 + (k % 2) * 8) * s, 5.0 * s, Color("6b5a4a"))
		"dog":
			for k in 4:
				draw_circle(p + Vector2(-16 + k * 11, sin(k * 3.0) * 12.0) * s, 4.0 * s, Color("6b4a2a"))


func _draw_house_violations(i: int, c: Vector2, side: int, rect: Rect2) -> void:
	for entry in _violation_layout(i):
		var s := float(entry.scale)
		match str(entry.object):
			"paint":
				draw_rect(Rect2(rect.position.x, rect.position.y, HOUSE_W, HOUSE_D * 0.4 * s), Color("d94fb5", 0.8))
			"siding", "damage":
				for k in 3:
					var q := c + Vector2(-30 + k * 28, -30 + k * 18) * s
					draw_rect(Rect2(q, Vector2(22, 16) * s), Color("2b2622"))
					draw_line(q, q + Vector2(30, -14) * s, Color("2b2622"), 2.0)
			"addition":
				var back_x := c.x + side * (HOUSE_W * 0.5 + 24.0)
				draw_rect(Rect2(back_x - 24.0, c.y - 40.0 * s, 48.0, 80.0 * s), Color("c9b48a"))
				draw_rect(Rect2(back_x - 24.0, c.y - 40.0 * s, 48.0, 80.0 * s), Color("7a6a44"), false, 3.0)
				for k in 4:
					draw_line(Vector2(back_x - 24.0, c.y - 40.0 * s + k * 26.0 * s), Vector2(back_x + 24.0, c.y - 40.0 * s + k * 26.0 * s), Color("8a6747"), 2.0)
			"rental":
				var sign_c := Vector2(c.x - side * (HOUSE_W * 0.5 + 18.0), c.y - 46.0)
				_rr(Rect2(sign_c - Vector2(14, 10), Vector2(28, 20)), Color("2f5d8a"), 3)
				draw_string(ThemeDB.fallback_font, sign_c + Vector2(-14, 6), "STR", HORIZONTAL_ALIGNMENT_CENTER, 28.0, 13, Color.WHITE)
				_rr(Rect2(Vector2(c.x - side * (HOUSE_W * 0.5 + 8.0) - 5.0, c.y + 20.0), Vector2(10, 12)), Color("b8bdc8"), 2)
			"noise":
				var origin := Vector2(c.x + side * 10.0, c.y)
				for k in 3:
					draw_arc(origin, 20.0 + k * 14.0 + sin(_time * 5.0 + k) * 3.0, -0.8, 0.8, 10, Color("ffd36e", 0.8 - k * 0.2), 3.0)
				draw_string(ThemeDB.fallback_font, origin + Vector2(-8, -34), "♪", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 24, Color("ffd36e"))


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
	_draw_map(Rect2(w - MINI_MAP_SIZE.x - 16.0, 16.0, MINI_MAP_SIZE.x, MINI_MAP_SIZE.y))
	var camera_c := Vector2(w - 66.0, h - 72.0)
	draw_circle(camera_c + Vector2(3.0, 5.0), 42.0, Color(0, 0, 0, 0.25))
	draw_circle(camera_c, 42.0, Color("f4ecd8"))
	_rr(Rect2(camera_c - Vector2(25.0, 17.0), Vector2(50.0, 36.0)), Color("273444"), 7)
	_rr(Rect2(camera_c + Vector2(-13.0, -24.0), Vector2(26.0, 10.0)), Color("273444"), 4)
	draw_circle(camera_c + Vector2(0.0, 1.0), 12.0, Color("71b9dc"))
	draw_circle(camera_c + Vector2(0.0, 1.0), 7.0, Color("182735"))
	if _dragging:
		var knob := _anchor + (_finger - _anchor).limit_length(STICK_RANGE)
		draw_arc(_anchor, STICK_RANGE * 0.62, 0.0, TAU, 40, Color(1, 1, 1, 0.18), 3.0, true)
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
	for button in [[172.0, "ALBUM"], [262.0, "CART"]]:
		var bc := Vector2(w - 66.0, h - float(button[0]))
		var on: bool = button[1] == "CART" and _cart
		draw_circle(bc + Vector2(2.0, 4.0), 36.0, Color(0, 0, 0, 0.25))
		draw_circle(bc, 36.0, Color("7ee081") if on else Color("f4ecd8"))
		draw_string(font, bc + Vector2(-36.0, 6.0), str(button[1]), HORIZONTAL_ALIGNMENT_CENTER, 72.0, 16, Color("273444"))
	if _evidence.size() > 0:
		draw_string(font, Vector2(w - 66.0 - 12.0, h - 172.0 - 22.0), str(_evidence.size()), HORIZONTAL_ALIGNMENT_CENTER, 24.0, 16, Color("273444"))
	var clock := "%s · %s" % [GameState.weekday_name(), GameState.season_name()]
	var clock_size := font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	_rr(Rect2(16.0, 16.0, clock_size.x + 24.0, 34.0), Color(0, 0, 0, 0.5), 10)
	draw_string(font, Vector2(28.0, 40.0), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffd36e"))
	var prompt := ""
	if _near >= 0:
		var kind: String = _pins.get(_near, "")
		prompt = "%s · %s" % [_address(_near),
				("READY TO INSPECT" if kind == "lawn" or kind == "card" else "PROPERTY INSPECTED")]
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


func _draw_camera_frame(w: float, h: float) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.18))
	var frame := _camera_frame_rect()
	var bracket := Color("ffd36e")
	var length := 48.0
	for corner in [frame.position, Vector2(frame.end.x, frame.position.y),
			Vector2(frame.position.x, frame.end.y), frame.end]:
		var sx := 1.0 if corner.x == frame.position.x else -1.0
		var sy := 1.0 if corner.y == frame.position.y else -1.0
		draw_line(corner, corner + Vector2(sx * length, 0), bracket, 5.0, true)
		draw_line(corner, corner + Vector2(0, sy * length), bracket, 5.0, true)
	var title := _address(_near) if _near >= 0 else "EVIDENCE"
	draw_string(font, Vector2(0, frame.position.y - 28.0), title, HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color.WHITE)
	var info := _evaluate_frame()
	var quality: int = info.quality
	var meter_col := Color("e0533d") if quality < USABLE_QUALITY else (Color("f2b632") if quality < 70 else Color("7ee081"))
	var meter := Rect2(frame.position.x + 190.0, frame.end.y + 30.0, frame.size.x - 190.0, 22.0)
	_rr(meter, Color(0, 0, 0, 0.5), 8)
	_rr(Rect2(meter.position, Vector2(meter.size.x * quality / 100.0, meter.size.y)), meter_col, 8)
	draw_string(font, meter.position + Vector2(0, -6), "PHOTO QUALITY %d%%" % quality, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var buttons := _zoom_buttons()
	for btn_name in ["minus", "plus", "cancel"]:
		var r: Rect2 = buttons[btn_name]
		_rr(r, Color(0.04, 0.08, 0.12, 0.85), 12)
		var label := "−" if btn_name == "minus" else ("+" if btn_name == "plus" else "CANCEL")
		draw_string(font, r.position + Vector2(0, r.size.y * 0.66), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				34 if btn_name != "cancel" else 18, Color.WHITE)
	draw_string(font, Vector2(frame.position.x, frame.end.y + 100.0), "ZOOM %.1fx · stand close, center the lot" % _zoom,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.8))


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


func _draw_full_map(w: float, h: float) -> void:
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.05, 0.08, 0.94))
	var panel := Rect2(24.0, 28.0, w - 48.0, h - 56.0)
	_rr(panel, Color("d9e2d0"), 22)
	var map_rect := Rect2(panel.position + Vector2(24.0, 82.0), panel.size - Vector2(48.0, 132.0))
	_rr(map_rect, Color("79b66a"), 14)
	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(24.0, 45.0), "NEIGHBORHOOD · 2,000 FT",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 26, Color("1d3340"))
	draw_string(font, panel.position + Vector2(24.0, 71.0), "Tap anywhere to return to the street",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 17, Color("435a62"))
	var road_col := Color("414a56")
	var walk_col := Color("d7d9d5")
	var main_route := PackedVector2Array()
	for point_i in 65:
		var wy := WORLD_H * float(point_i) / 64.0
		main_route.append(_map_point(Vector2(_road_x(wy), wy), map_rect))
	draw_polyline(main_route, walk_col, 15.0, true)
	draw_polyline(main_route, road_col, 10.0, true)
	for connector in CONNECTOR_XS:
		var a := _map_point(Vector2(float(connector), float(JUNCTIONS[0])), map_rect)
		var b := _map_point(Vector2(float(connector), float(JUNCTIONS[-1])), map_rect)
		draw_line(a, b, walk_col, 15.0, true)
		draw_line(a, b, road_col, 10.0, true)
	for junction in JUNCTIONS:
		var a := _map_point(Vector2(CULDESAC_X, float(junction)), map_rect)
		var b := _map_point(Vector2(WORLD_W - CULDESAC_X, float(junction)), map_rect)
		draw_line(a, b, walk_col, 15.0, true)
		draw_line(a, b, road_col, 10.0, true)
	for lane_i in CURVED_LANE_COUNT:
		var lane := PackedVector2Array()
		for point_i in 24:
			var t := float(point_i) / 23.0
			lane.append(_map_point(_curved_lane_point(lane_i, t), map_rect))
		draw_polyline(lane, road_col, 8.0, true)
	for i in HOUSE_COUNT:
		var hp := _map_point(_house_c(i), map_rect)
		var roof: Color = _houses[i].roof
		draw_rect(Rect2(hp - Vector2(5.0, 4.0), Vector2(10.0, 8.0)), roof)
		var map_kind := str(_pins.get(i, ""))
		if map_kind in ["lawn", "card"]:
			draw_circle(hp, 8.0, Color("ffd36e", 0.45), false, 2.0)
		elif map_kind == "done":
			draw_circle(hp, 7.0, Color("50c878"), false, 2.0)
		if _evidence.has(i):
			draw_circle(hp, 3.0, Color("71b9dc"))
	var player := _map_point(Vector2(_player_x, _player_y), map_rect)
	draw_circle(player, 9.0, Color("ffd36e"))
	draw_circle(player, 14.0, Color("1d3340"), false, 3.0)
	# The pale rectangle shows the approximate street area visible below.
	var view_size := Vector2(size.x / WORLD_W * map_rect.size.x,
			size.y / WORLD_H * map_rect.size.y)
	draw_rect(Rect2(player - view_size * 0.5, view_size), Color(1, 1, 1, 0.65), false, 2.0)


func _map_point(world_point: Vector2, rect: Rect2) -> Vector2:
	return rect.position + Vector2(world_point.x / WORLD_W * rect.size.x,
			world_point.y / WORLD_H * rect.size.y)


func _gallery_items() -> Array:
	var items: Array = []
	for house in _evidence:
		items.append({"house": int(house), "e": _evidence[house]})
	items.sort_custom(func(a, b): return str(a.e.get("time", "")) > str(b.e.get("time", "")))
	return items


func _thumb(path: String) -> Texture2D:
	if _thumbs.has(path):
		return _thumbs[path]
	var tex: Texture2D = null
	var image := Image.load_from_file(path)
	if image != null and not image.is_empty():
		tex = ImageTexture.create_from_image(image)
	_thumbs[path] = tex
	return tex


func _gallery_panel() -> Rect2:
	return Rect2(24.0, 28.0, size.x - 48.0, size.y - 56.0)


func _gallery_cell(k: int) -> Rect2:
	var panel := _gallery_panel()
	var cw := (panel.size.x - 72.0) * 0.5
	var ch := cw * 0.75 + 56.0
	return Rect2(panel.position.x + 24.0 + (k % 2) * (cw + 24.0), panel.position.y + 90.0 + (k / 2) * (ch + 14.0), cw, ch)


func _tap_gallery(pos: Vector2) -> bool:
	var panel := _gallery_panel()
	var items := _gallery_items()
	var pages := maxi(1, ceili(float(items.size()) / GALLERY_PAGE))
	if Rect2(panel.end.x - 130.0, panel.end.y - 76.0, 110.0, 56.0).has_point(pos):
		_gallery_open = false
		_gallery_sel = -1
	elif _gallery_sel >= 0:
		_gallery_sel = -1
	elif Rect2(panel.position.x + 20.0, panel.end.y - 76.0, 110.0, 56.0).has_point(pos):
		_gallery_page = maxi(0, _gallery_page - 1)
	elif Rect2(panel.position.x + 140.0, panel.end.y - 76.0, 110.0, 56.0).has_point(pos):
		_gallery_page = mini(pages - 1, _gallery_page + 1)
	else:
		for k in GALLERY_PAGE:
			var idx := _gallery_page * GALLERY_PAGE + k
			if idx < items.size() and _gallery_cell(k).has_point(pos):
				_gallery_sel = idx
	queue_redraw()
	return true


func _violation_label(house: int, id: String) -> String:
	for v in _property_violations.get(house, []):
		if str(v.get("id", "")) == id:
			return str(v.get("label", id))
	return id


func _draw_gallery(w: float, h: float) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.05, 0.08, 0.94))
	var panel := _gallery_panel()
	_rr(panel, Color("d9e2d0"), 22)
	var items := _gallery_items()
	var pages := maxi(1, ceili(float(items.size()) / GALLERY_PAGE))
	draw_string(font, panel.position + Vector2(24.0, 50.0), "EVIDENCE ALBUM · %d PHOTOS" % items.size(),
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 26, Color("1d3340"))
	if items.is_empty():
		draw_string(font, panel.position + Vector2(24.0, 140.0), "No photos yet. Stand near a flagged lot and use the camera.",
				HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 20, Color("435a62"))
	if _gallery_sel >= 0 and _gallery_sel < items.size():
		var item: Dictionary = items[_gallery_sel]
		var e: Dictionary = item.e
		var big := Rect2(panel.position + Vector2(24.0, 80.0), Vector2(panel.size.x - 48.0, (panel.size.x - 48.0) * 0.75))
		_rr(big, Color("1d3340"), 12)
		var tex := _thumb(str(e.get("path", "")))
		if tex != null:
			draw_texture_rect(tex, big, false)
		var y := big.end.y + 34.0
		draw_string(font, Vector2(big.position.x, y), "%s · %s" % [str(e.get("address", "")), str(e.get("time", "")).replace("T", " ")],
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 22, Color("1d3340"))
		draw_string(font, Vector2(big.position.x, y + 30.0), "Quality %d%% · %d shot(s)" % [int(e.get("quality", 0)), int(e.get("shots", 1))],
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 20, Color("435a62"))
		var labels: Array = []
		for id in e.get("documented", []):
			labels.append(_violation_label(int(item.house), str(id)))
		draw_string(font, Vector2(big.position.x, y + 60.0), "Documents: %s" % (", ".join(labels) if not labels.is_empty() else "nothing clearly visible"),
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 20, Color("435a62"))
		draw_string(font, Vector2(big.position.x, y + 92.0), "Retake: walk back to the lot and use the camera. Best shot is kept.",
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 17, Color("435a62"))
		draw_string(font, Vector2(big.position.x, y + 120.0), "Tap anywhere to go back",
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 17, Color("435a62"))
	else:
		for k in GALLERY_PAGE:
			var idx := _gallery_page * GALLERY_PAGE + k
			if idx >= items.size():
				break
			var cell := _gallery_cell(k)
			var e: Dictionary = items[idx].e
			var img_rect := Rect2(cell.position, Vector2(cell.size.x, cell.size.x * 0.75))
			_rr(img_rect, Color("1d3340"), 10)
			var tex := _thumb(str(e.get("path", "")))
			if tex != null:
				draw_texture_rect(tex, img_rect, false)
			var q := int(e.get("quality", 0))
			draw_string(font, cell.position + Vector2(0.0, img_rect.size.y + 22.0), str(e.get("address", "")),
					HORIZONTAL_ALIGNMENT_LEFT, cell.size.x, 17, Color("1d3340"))
			draw_string(font, cell.position + Vector2(0.0, img_rect.size.y + 44.0), "%d%% · %d violation(s) shown" % [q, e.get("documented", []).size()],
					HORIZONTAL_ALIGNMENT_LEFT, cell.size.x, 15, Color("2f9e57") if q >= 70 else Color("b3261e"))
	for spec in [[Rect2(panel.position.x + 20.0, panel.end.y - 76.0, 110.0, 56.0), "PREV"],
			[Rect2(panel.position.x + 140.0, panel.end.y - 76.0, 110.0, 56.0), "NEXT"],
			[Rect2(panel.end.x - 130.0, panel.end.y - 76.0, 110.0, 56.0), "CLOSE"]]:
		_rr(spec[0], Color("1d3340"), 12)
		draw_string(font, (spec[0] as Rect2).position + Vector2(0.0, 36.0), str(spec[1]), HORIZONTAL_ALIGNMENT_CENTER, 110.0, 20, Color.WHITE)
	draw_string(font, Vector2(panel.position.x + 270.0, panel.end.y - 40.0), "%d / %d" % [_gallery_page + 1, pages],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("1d3340"))


# ---------- ambient life: traffic, trucks, crews, kids ----------

func _build_ambient() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.day * 7919 + 13
	var cols := [Color("e0533d"), Color("3a6fd8"), Color("e8e8ee"), Color("2f9e57"), Color("8a6fc4")]
	_traffic.clear()
	for k in 4:
		_traffic.append({"kind": "car", "dir": -1 if k % 2 == 0 else 1, "y": rng.randf_range(300.0, WORLD_H - 300.0),
				"speed": rng.randf_range(80.0, 125.0), "col": cols[rng.randi() % cols.size()],
				"pause": 0.0, "travel": 0.0, "next_stop": INF})
	if not _weekend:
		_traffic.append({"kind": "delivery", "dir": 1, "y": rng.randf_range(300.0, WORLD_H - 300.0), "speed": 70.0,
				"col": Color("d9d4c7"), "pause": 0.0, "travel": 0.0, "next_stop": rng.randf_range(250.0, 800.0)})
		if GameState.weekday() in [1, 3]:
			_traffic.append({"kind": "garbage", "dir": -1, "y": rng.randf_range(300.0, WORLD_H - 300.0), "speed": 48.0,
					"col": Color("2f9e57"), "pause": 0.0, "travel": 0.0, "next_stop": rng.randf_range(200.0, 500.0)})
	_crews.clear()
	if not _weekend:
		for k in 3:
			_crews.append({"house": rng.randi_range(0, MAIN_HOUSE_COUNT - 1), "phase": rng.randf_range(0.0, TAU)})
	_kids.clear()
	for k in (10 if _weekend else 4):
		var bulb := k % 16
		_kids.append({"c": Vector2(CULDESAC_X if bulb % 2 == 0 else WORLD_W - CULDESAC_X, float(JUNCTIONS[(bulb / 2) % 8])),
				"r": rng.randf_range(36.0, 52.0), "phase": rng.randf_range(0.0, TAU),
				"speed": rng.randf_range(0.8, 1.6), "tone": k % 4})


func _lane_x(v: Dictionary) -> float:
	# Right-hand traffic: northbound (dir -1) keeps to the +x side of the centerline.
	return _road_x(float(v.y)) - int(v.dir) * 10.0


func _kid_position(k: Dictionary) -> Vector2:
	return (k.c as Vector2) + Vector2.from_angle(float(k.phase) + _time * float(k.speed)) * float(k.r)


func _crew_yard_center(crew: Dictionary) -> Vector2:
	var hy := house_y(int(crew.house))
	return Vector2(_road_x(hy) + _side(int(crew.house)) * (ROAD_HALF + WALK_W + YARD_GAP * 0.5), hy)


func _crew_worker_position(crew: Dictionary) -> Vector2:
	return _crew_yard_center(crew) + Vector2(sin(_time * 0.8 + float(crew.phase)) * 20.0,
			cos(_time * 0.5 + float(crew.phase)) * 58.0)


func _crew_truck_position(crew: Dictionary) -> Vector2:
	var hy := house_y(int(crew.house))
	return Vector2(_road_x(hy) + _side(int(crew.house)) * PARK_X, hy + 95.0)


func _update_ambient(delta: float) -> void:
	var player := Vector2(_player_x, _player_y)
	_obstacles = _static_obstacles.duplicate()
	for v in _traffic:
		var lane := _lane_x(v)
		var half := Vector2(18.0, 40.0) if v.kind == "car" else Vector2(22.0, 56.0)
		_obstacles.append(Rect2(Vector2(lane, float(v.y)) - half, half * 2.0))
		if float(v.pause) > 0.0:
			v.pause = float(v.pause) - delta
			continue
		var ahead := (player.y - float(v.y)) * int(v.dir)
		if ahead > 0.0 and ahead < 150.0 and absf(player.x - lane) < 52.0:
			continue
		var step := float(v.speed) * delta
		v.y = fposmod(float(v.y) + int(v.dir) * step, WORLD_H)
		v.travel = float(v.travel) + step
		if v.kind != "car" and float(v.travel) >= float(v.next_stop):
			v.pause = 2.5
			v.next_stop = float(v.travel) + randf_range(250.0, 700.0)
	for crew in _crews:
		var truck := _crew_truck_position(crew)
		_obstacles.append(Rect2(truck - Vector2(20.0, 48.0), Vector2(40.0, 96.0)))


func _draw_car_at(x: float, y: float, col: Color, k: float, rot: float) -> void:
	_set_world_transform(Vector2(x, y), k, rot)
	_draw_car(x, y, col)
	_set_world_transform()


func _draw_truck(x: float, y: float, kind: String) -> void:
	var delivery := kind == "delivery"
	var body := Color("e8e1d0") if delivery else Color("2f9e57")
	var accent := Color("8a5a34") if delivery else Color("1c5a3e")
	var length := 56.0
	_ellipse(Vector2(x + 7.0, y + 8.0), 28.0, length + 4.0, Color(0, 0, 0, 0.24))
	_rr(Rect2(x - 22.0, y - length, 44.0, 32.0), accent, 8)
	_rr(Rect2(x - 16.0, y - length + 4.0, 32.0, 12.0), Color("bfe2f5"), 3)
	_rr(Rect2(x - 23.0, y - length + 30.0, 46.0, length * 2.0 - 30.0), body, 5)
	if delivery:
		draw_line(Vector2(x - 23.0, y + 4.0), Vector2(x + 23.0, y + 4.0), accent, 6.0)
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, y + 30.0), "PKG", HORIZONTAL_ALIGNMENT_CENTER, 40.0, 14, accent)
	else:
		_rr(Rect2(x - 18.0, y + length - 14.0, 36.0, 12.0), Color("1c2b24"), 3)
		draw_circle(Vector2(x, y + 10.0), 10.0, Color("1c5a3e"), false, 3.0)


func _draw_traffic() -> void:
	for v in _traffic:
		if not _on_screen(float(v.y), 140.0):
			continue
		var x := _lane_x(v) - _cam_x
		var y := float(v.y) - _cam
		var rot := 0.0 if int(v.dir) < 0 else PI
		if v.kind == "car":
			_draw_car_at(x, y, v.col, 0.8, rot)
		else:
			_set_world_transform(Vector2(x, y), 0.85, rot)
			_draw_truck(x, y, str(v.kind))
			_set_world_transform()


func _draw_crews() -> void:
	for crew in _crews:
		var hy := house_y(int(crew.house))
		if not _on_screen(hy, 200.0):
			continue
		var t := _crew_truck_position(crew) - Vector2(_cam_x, _cam)
		_set_world_transform(t, 0.85, 0.0)
		_draw_truck(t.x, t.y, "delivery")
		_rr(Rect2(t + Vector2(-16.0, 62.0), Vector2(32.0, 40.0)), Color("52616f"), 3)
		_set_world_transform()
		var w := _crew_worker_position(crew) - Vector2(_cam_x, _cam)
		_rr(Rect2(w + Vector2(-9.0, -34.0), Vector2(18.0, 14.0)), Color("e07a1f"), 3)
		_draw_neighbor(w, int(crew.house) % 4, 30.0)


func _draw_kids() -> void:
	for k in _kids:
		var p := _kid_position(k)
		if not _on_screen(p.y, 100.0):
			continue
		var sp := p - Vector2(_cam_x, _cam)
		_set_world_transform(sp, 0.65, 0.0)
		_draw_neighbor(sp, int(k.tone), 30.0)
		_set_world_transform()
		var ball_a := float(k.phase) + _time * float(k.speed) * 1.4 + 2.0
		var bp := (k.c as Vector2) + Vector2.from_angle(ball_a) * (float(k.r) + 16.0) - Vector2(_cam_x, _cam)
		bp.y -= absf(sin(_time * 5.0 + float(k.phase))) * 9.0
		draw_circle(bp, 5.0, [Color("ff6b5a"), Color("ffd36e"), Color("71b9dc"), Color.WHITE][int(k.tone)])


func _draw_cart(pos: Vector2) -> void:
	draw_set_transform(pos + Vector2(6.0, 10.0), _angle, Vector2.ONE)
	_ellipse(Vector2.ZERO, 26.0, 36.0, Color(0, 0, 0, 0.22))
	draw_set_transform(pos, _angle, Vector2.ONE)
	for wheel in [Vector2(-22, -22), Vector2(22, -22), Vector2(-22, 24), Vector2(22, 24)]:
		_rr(Rect2(wheel - Vector2(4, 9), Vector2(8, 18)), Color("171b24"), 2)
	_rr(Rect2(-20.0, -34.0, 40.0, 70.0), Color("f4ecd8"), 10)
	_rr(Rect2(-18.0, 4.0, 36.0, 26.0), Color("2f9e57"), 6)
	_rr(Rect2(-22.0, -38.0, 44.0, 8.0), Color("4a4f58"), 4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
