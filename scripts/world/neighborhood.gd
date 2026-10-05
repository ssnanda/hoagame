extends RefCounted
## Neighborhood geometry: streets, cul-de-sacs, lots and landmarks.
## Single source of truth. The world renderer, minimap, full map, collision and
## validation all read from here. No drawing and no game rules in this file.

const LotScript := preload("res://scripts/world/lot.gd")

const WORLD_W := 2200.0
const WORLD_H := 8600.0
const WALK_W := 30.0
const AVENUE_HALF := 58.0
const STREET_HALF := 44.0
const BULB_R := 104.0
const SETBACK := 54.0           ## sidewalk edge to house front
const SIDE_GAP := 22.0          ## side yard on each side of a house
const BACKYARD := 60.0
const SPINE_X := 1100.0
const SPINE_Y0 := 760.0
const SPINE_Y1 := 7840.0
const ARM_LEN := 720.0
const ARM_YS_LEFT := [1350.0, 2450.0, 3550.0, 4650.0, 5750.0, 6850.0]
const ARM_YS_RIGHT := [1900.0, 3000.0, 4100.0, 5200.0, 6300.0, 7400.0]
const BULB_LOTS := 6
const BULB_ENTRY_GAP := 0.62    ## radians kept clear on each side of the street mouth
const BUCKET := 256.0

## Footprint (front-to-back depth, frontage width) per house archetype.
## 0 ranch, 1 two-story, 2 craftsman, 3 brick traditional, 4 modern, 5 narrow-lot
const ARCH_SIZE := [Vector2(110, 148), Vector2(104, 126), Vector2(118, 138),
		Vector2(122, 142), Vector2(108, 150), Vector2(100, 112)]
const STREET_NAMES := ["Briarwood Court", "Hawthorne Drive", "Cedar Ridge Way", "Willow Bend Court",
		"Fox Hollow Drive", "Heritage Oak Lane", "Aspen Glen Court", "Stonebridge Way",
		"Magnolia Court", "Juniper Hill Drive", "Dogwood Lane", "Sycamore Court"]

class Street:
	var id := 0
	var name := ""
	var kind := "street"        ## avenue | street
	var half := 44.0
	var path := PackedVector2Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var bulbs: Array = []       ## each: {"center": Vector2, "entry": Vector2 toward the street}

var streets: Array = []
var lots: Array = []
## Landmarks: {"type": lake|park|woods|pond|clubhouse, "rect": Rect2} (lake/pond use the rect's ellipse)
var landmarks: Array = []
var street_trees: Array[Vector3] = []
var woods_trees: Array[Vector3] = []
var _buckets: Dictionary = {}
var _bulbs: Array = []
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 7771
	_make_streets()
	_make_landmarks()
	_index_roads()
	for street in streets:
		for bulb in street.bulbs:
			_gen_bulb_lots(street, bulb)
	for street in streets:
		_gen_straight_lots(street)
	_mark_corners()
	_number_lots()
	_plant_trees()


func spine_x(y: float) -> float:
	return SPINE_X + sin(y / 520.0) * 55.0 + sin(y / 190.0) * 14.0


# ---------------------------------------------------------------- streets

func _make_streets() -> void:
	var spine := Street.new()
	spine.id = 0
	spine.name = "Maple Grove Lane"
	spine.kind = "avenue"
	spine.half = AVENUE_HALF
	var y := SPINE_Y0
	while y < SPINE_Y1:
		spine.path.append(Vector2(spine_x(y), y))
		y += 40.0
	spine.path.append(Vector2(spine_x(SPINE_Y1), SPINE_Y1))
	spine.bulbs.append({"center": spine.path[0], "entry": (spine.path[1] - spine.path[0]).normalized()})
	spine.bulbs.append({"center": spine.path[-1], "entry": (spine.path[-2] - spine.path[-1]).normalized()})
	_finish_street(spine)
	var arm_index := 0
	for k in ARM_YS_LEFT.size():
		_make_arm(-1.0, float(ARM_YS_LEFT[k]), arm_index, k)
		arm_index += 1
		_make_arm(1.0, float(ARM_YS_RIGHT[k]), arm_index, k)
		arm_index += 1


func _make_arm(dir: float, y_arm: float, arm_index: int, phase: int) -> void:
	var arm := Street.new()
	arm.id = streets.size()
	arm.name = STREET_NAMES[arm_index % STREET_NAMES.size()]
	arm.half = STREET_HALF
	var sx := spine_x(y_arm)
	var u := 0.0
	while u <= ARM_LEN + 0.1:
		var wobble := sin(u / 160.0 + float(phase)) * 16.0 * clampf(u / 200.0, 0.0, 1.0)
		arm.path.append(Vector2(sx + dir * u, y_arm + wobble))
		u += 40.0
	arm.bulbs.append({"center": arm.path[-1], "entry": (arm.path[-2] - arm.path[-1]).normalized()})
	_finish_street(arm)


func _finish_street(street: Street) -> void:
	street.cum.append(0.0)
	for i in range(1, street.path.size()):
		street.cum.append(street.cum[i - 1] + street.path[i].distance_to(street.path[i - 1]))
	street.length = street.cum[street.cum.size() - 1]
	streets.append(street)
	for bulb in street.bulbs:
		_bulbs.append({"street": street.id, "center": bulb.center})


## Position and unit tangent at arc length `s` along a street.
func sample(street: Street, s: float) -> Array:
	s = clampf(s, 0.0, street.length)
	var i := 1
	while i < street.cum.size() - 1 and street.cum[i] < s:
		i += 1
	var a := street.path[i - 1]
	var b := street.path[i]
	var span := maxf(street.cum[i] - street.cum[i - 1], 0.001)
	var t := clampf((s - street.cum[i - 1]) / span, 0.0, 1.0)
	return [a.lerp(b, t), (b - a).normalized()]


func _index_roads() -> void:
	_buckets.clear()
	for street in streets:
		var reach: float = street.half + WALK_W + 10.0
		for i in range(1, street.path.size()):
			var a: Vector2 = street.path[i - 1]
			var b: Vector2 = street.path[i]
			var y0 := minf(a.y, b.y) - reach
			var y1 := maxf(a.y, b.y) + reach
			for key in range(int(floor(y0 / BUCKET)), int(floor(y1 / BUCKET)) + 1):
				if not _buckets.has(key):
					_buckets[key] = []
				_buckets[key].append([street.id, a, b, street.half])


## Signed distance to the nearest asphalt edge (negative on the road).
## `skip` ignores one street, `only` considers just one street.
func edge_distance(p: Vector2, skip := -1, only := -1) -> float:
	var best := INF
	for entry in _buckets.get(int(floor(p.y / BUCKET)), []):
		var sid: int = entry[0]
		if sid == skip or (only >= 0 and sid != only):
			continue
		var d := Geometry2D.get_closest_point_to_segment(p, entry[1], entry[2]).distance_to(p) - float(entry[3])
		if d < best:
			best = d
	for bulb in _bulbs:
		var sid2: int = bulb.street
		if sid2 == skip or (only >= 0 and sid2 != only):
			continue
		var c: Vector2 = bulb.center
		if absf(c.y - p.y) > BULB_R + 220.0:
			continue
		best = minf(best, p.distance_to(c) - BULB_R)
	return best


func street_at(p: Vector2) -> int:
	var best := INF
	var found := -1
	for street in streets:
		var d := edge_distance(p, -1, street.id)
		if d < best:
			best = d
			found = street.id
	return found


## True for road, sidewalk and driveway surface the inspector may stand on.
func is_walkable(p: Vector2) -> bool:
	if p.x < 4.0 or p.x > WORLD_W - 4.0 or p.y < 4.0 or p.y > WORLD_H - 4.0:
		return false
	if edge_distance(p) <= WALK_W * 0.8:
		return true
	return driveway_at(p) >= 0


func driveway_at(p: Vector2) -> int:
	for lot in _lots_near(p, 120.0):
		var closest := Geometry2D.get_closest_point_to_segment(p, lot.curb, lot.driveway_end)
		if closest.distance_to(p) <= lot.driveway_width * 0.5 + 4.0:
			return lot.id
	return -1


func _lots_near(p: Vector2, radius: float) -> Array:
	var result: Array = []
	for lot in lots:
		if absf(lot.center.y - p.y) < radius + 150.0 and lot.center.distance_to(p) < radius + 260.0:
			result.append(lot)
	return result


# ---------------------------------------------------------------- landmarks

func _make_landmarks() -> void:
	landmarks = [
		{"type": "park", "rect": Rect2(110, 1760, 620, 280)},
		{"type": "woods", "rect": Rect2(110, 2860, 620, 280)},
		{"type": "clubhouse", "rect": Rect2(200, 3960, 520, 280)},
		{"type": "pond", "rect": Rect2(200, 5060, 460, 280)},
		{"type": "park", "rect": Rect2(110, 6160, 620, 280)},
		{"type": "woods", "rect": Rect2(1470, 2310, 620, 280)},
		{"type": "lake", "rect": Rect2(1560, 3410, 520, 280)},
		{"type": "park", "rect": Rect2(1470, 4510, 620, 280)},
		{"type": "woods", "rect": Rect2(1470, 5610, 620, 280)},
		{"type": "park", "rect": Rect2(1470, 6710, 620, 280)},
	]


func landmark_at(p: Vector2) -> Dictionary:
	for mark in landmarks:
		var r: Rect2 = mark.rect
		if str(mark.type) in ["lake", "pond"]:
			var c := r.get_center()
			var n := Vector2((p.x - c.x) / (r.size.x * 0.5), (p.y - c.y) / (r.size.y * 0.5))
			if n.length() <= 1.08:
				return mark
		elif r.grow(6.0).has_point(p):
			return mark
	return {}


func is_water(p: Vector2) -> bool:
	var mark := landmark_at(p)
	return not mark.is_empty() and str(mark.type) in ["lake", "pond"]


# ---------------------------------------------------------------- lots

func _gen_straight_lots(street: Street) -> void:
	for side in [-1, 1]:
		var s := WALK_W + 80.0
		while s < street.length - 40.0:
			var arch := _rng.randi_range(0, ARCH_SIZE.size() - 1)
			var lot = _try_straight(street, side, s, arch)
			if lot != null:
				lots.append(lot)
				lot.id = lots.size() - 1
				s += float(lot.house_size.y) + SIDE_GAP * 2.0
			else:
				s += 30.0


func _try_straight(street: Street, side: int, s: float, arch: int):
	var size: Vector2 = ARCH_SIZE[arch]
	var frontage := size.y + SIDE_GAP * 2.0
	if s + frontage > street.length:
		return null
	var mid := s + frontage * 0.5
	var smp := sample(street, mid)
	var pos: Vector2 = smp[0]
	var t: Vector2 = smp[1]
	var n := Vector2(-t.y, t.x) * float(side)
	var edge: float = street.half + WALK_W
	var lot = LotScript.new()
	lot.street_id = street.id
	lot.street_name = street.name
	lot.side = side
	lot.archetype = arch
	lot.house_size = size
	lot.s_along = mid
	lot.front = -n
	var front_pt := pos + n * (edge + SETBACK)
	lot.center = front_pt + n * (size.x * 0.5)
	var depth := SETBACK + size.x + BACKYARD
	lot.polygon = PackedVector2Array([pos - t * frontage * 0.5 + n * edge, pos + t * frontage * 0.5 + n * edge,
			pos + t * frontage * 0.5 + n * (edge + depth), pos - t * frontage * 0.5 + n * (edge + depth)])
	var lateral := (size.y * 0.5 - 30.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
	_attach_driveway(lot, street, front_pt + t * lateral, pos + t * lateral + n * edge, n, t * signf(lateral))
	return lot if _lot_ok(lot, street.id) else null


## Puts the driveway on the lot and snaps its curb end to the sidewalk edge.
func _attach_driveway(lot, street: Street, house_end: Vector2, curb_guess: Vector2, outward: Vector2, lateral_dir: Vector2) -> void:
	var curb := curb_guess
	for _i in 4:
		# Walk along the outward normal until we sit exactly on the sidewalk's outer edge.
		curb += outward * (WALK_W - edge_distance(curb, -1, street.id))
	lot.curb = curb
	lot.driveway_end = house_end
	lot.driveway_width = 34.0 + 4.0 * float(lot.archetype % 3)
	# Mailbox goes on whichever side of the driveway keeps clear of other roads.
	var offset: float = lot.driveway_width * 0.5 + 22.0
	var a: Vector2 = curb + lateral_dir * offset + outward * 8.0
	var b: Vector2 = curb - lateral_dir * offset + outward * 8.0
	lot.mailbox = a if edge_distance(a) >= edge_distance(b) else b


func _gen_bulb_lots(street: Street, bulb: Dictionary) -> void:
	var center: Vector2 = bulb.center
	var entry: Vector2 = bulb.entry
	var r_in := BULB_R + WALK_W
	var avail := TAU - 2.0 * BULB_ENTRY_GAP
	for k in BULB_LOTS:
		var th := entry.angle() + BULB_ENTRY_GAP + avail * (float(k) + 0.5) / float(BULB_LOTS)
		var radial := Vector2.from_angle(th)
		var tangent := Vector2(-radial.y, radial.x)
		var arch := _rng.randi_range(0, ARCH_SIZE.size() - 1)
		var size: Vector2 = ARCH_SIZE[arch]
		var half_angle := avail / float(BULB_LOTS) * 0.5
		var r_out := r_in + SETBACK + size.x + BACKYARD
		var lot = LotScript.new()
		lot.street_id = street.id
		lot.street_name = street.name
		lot.kind = "cul_de_sac"
		lot.group = "%s bulb %d" % [street.name, street.bulbs.find(bulb)]
		lot.archetype = arch
		lot.house_size = size
		lot.front = -radial
		lot.s_along = street.length + 1000.0 * float(street.bulbs.find(bulb)) + th
		var front_pt := center + radial * (r_in + SETBACK)
		lot.center = front_pt + radial * (size.x * 0.5)
		var poly := PackedVector2Array()
		for j in 7:
			poly.append(center + Vector2.from_angle(th - half_angle + 2.0 * half_angle * float(j) / 6.0) * r_in)
		for j in 7:
			poly.append(center + Vector2.from_angle(th + half_angle - 2.0 * half_angle * float(j) / 6.0) * r_out)
		lot.polygon = poly
		var lateral := (size.y * 0.5 - 30.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var curb_guess := center + (front_pt + tangent * lateral - center).normalized() * r_in
		_attach_driveway(lot, street, front_pt + tangent * lateral, curb_guess,
				(curb_guess - center).normalized(), tangent * signf(lateral))
		if _lot_ok(lot, street.id):
			lots.append(lot)
			lot.id = lots.size() - 1


func _lot_ok(lot, own: int) -> bool:
	for p in lot.polygon:
		if p.x < 12.0 or p.x > WORLD_W - 12.0 or p.y < 12.0 or p.y > WORLD_H - 12.0:
			return false
		if edge_distance(p, own) < WALK_W - 2.0:
			return false
		if not landmark_at(p).is_empty():
			return false
	for p in lot.footprint(6.0):
		if edge_distance(p, own) < WALK_W + 14.0:
			return false
	var radius := 0.0
	for p in lot.polygon:
		radius = maxf(radius, p.distance_to(lot.center))
	var shrunk := _shrink(lot.polygon, lot.center, 0.97)
	for other in lots:
		if other.center.distance_squared_to(lot.center) > pow(radius + 260.0, 2.0):
			continue
		if not Geometry2D.intersect_polygons(shrunk, _shrink(other.polygon, other.center, 0.97)).is_empty():
			return false
	return true


func _shrink(poly: PackedVector2Array, about: Vector2, k: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in poly:
		result.append(about + (p - about) * k)
	return result


## A lot whose side boundary runs close to another street is a corner lot. It gets
## landscaping along that second edge (the world view draws a hedge there).
func _mark_corners() -> void:
	for lot in lots:
		if lot.kind == "cul_de_sac":
			continue
		var best := INF
		var edge := PackedVector2Array()
		var n: int = lot.polygon.size()
		for i in n:
			var a: Vector2 = lot.polygon[i]
			var b: Vector2 = lot.polygon[(i + 1) % n]
			var mid := (a + b) * 0.5
			if edge_distance(mid, -1, lot.street_id) < WALK_W + 6.0:
				continue   # the frontage edge
			var d := edge_distance(mid, lot.street_id)
			if d < best:
				best = d
				edge = PackedVector2Array([a, b])
		if best < 150.0 and not edge.is_empty():
			lot.kind = "corner"
			lot.corner_edge = edge


func _number_lots() -> void:
	for street in streets:
		var mine: Array = []
		for lot in lots:
			if lot.street_id == street.id:
				mine.append(lot)
		mine.sort_custom(func(a, b): return a.s_along < b.s_along)
		var counters := {-1: 0, 0: 0, 1: 0}
		var base: int = 100 * (street.id + 1)
		for lot in mine:
			var k: int = counters[lot.side]
			if lot.side == 0:
				lot.number = base + 2 * (counters[-1] + counters[1] + k) + 10
			else:
				lot.number = base + 2 * k + (1 if lot.side < 0 else 0)
			counters[lot.side] = k + 1
			lot.address = "%d %s" % [lot.number, lot.street_name]


# ---------------------------------------------------------------- trees

func _plant_trees() -> void:
	street_trees.clear()
	woods_trees.clear()
	for lot in lots:
		lot.trees.clear()
		for sign in [-1.0, 1.0]:
			if _rng.randf() < 0.55:
				continue
			var radius := _rng.randf_range(24.0, 38.0)
			var p: Vector2 = lot.local_point(-lot.house_size.x * 0.5 - 26.0, sign * (lot.house_size.y * 0.5 - 14.0))
			if Geometry2D.is_point_in_polygon(p, lot.polygon) and edge_distance(p, lot.street_id) > WALK_W + 30.0:
				lot.trees.append(Vector3(p.x, p.y, radius))
	for street in streets:
		for side in [-1, 1]:
			var s := 60.0 + _rng.randf_range(0.0, 60.0)
			while s < street.length - 60.0:
				var smp := sample(street, s)
				var t: Vector2 = smp[1]
				var p: Vector2 = smp[0] + Vector2(-t.y, t.x) * float(side) * (street.half + WALK_W + 12.0)
				if _tree_site_clear(p, street.id):
					street_trees.append(Vector3(p.x, p.y, _rng.randf_range(20.0, 30.0)))
				s += _rng.randf_range(150.0, 230.0)
	for mark in landmarks:
		if str(mark.type) != "woods":
			continue
		var r: Rect2 = mark.rect
		for _i in 22:
			woods_trees.append(Vector3(r.position.x + _rng.randf() * r.size.x, r.position.y + _rng.randf() * r.size.y,
					_rng.randf_range(26.0, 46.0)))


func _tree_site_clear(p: Vector2, own: int) -> bool:
	if edge_distance(p, own) < WALK_W + 4.0 or not landmark_at(p).is_empty():
		return false
	for lot in _lots_near(p, 40.0):
		if lot.curb.distance_to(p) < 62.0 or lot.mailbox.distance_to(p) < 34.0:
			return false
	return true


# ---------------------------------------------------------------- validation

## Human-readable layout problems. Empty means the neighborhood is sound.
func validate() -> Array:
	var warnings: Array = []
	var per_bulb := {}
	for lot in lots:
		var label := "Lot %d (%s)" % [lot.id, lot.address]
		for p in lot.footprint():
			if edge_distance(p) < WALK_W + 4.0:
				warnings.append("%s: house overlaps road or sidewalk" % label)
				break
		for p in lot.footprint():
			if not landmark_at(p).is_empty():
				warnings.append("%s: house overlaps a landmark" % label)
				break
		var curb_gap := absf(edge_distance(lot.curb, -1, lot.street_id) - WALK_W)
		if curb_gap > 6.0:
			warnings.append("%s: driveway does not meet the sidewalk (%.0f px off)" % [label, curb_gap])
		if not Geometry2D.is_point_in_polygon(lot.driveway_end, lot.footprint(4.0)):
			warnings.append("%s: driveway misses the house" % label)
		if not is_walkable(lot.driveway_mid()):
			warnings.append("%s: inspection point is unreachable" % label)
		if lot.kind == "cul_de_sac":
			per_bulb[lot.group] = int(per_bulb.get(lot.group, 0)) + 1
		if lot.mailbox.x < 0.0 or lot.mailbox.x > WORLD_W or edge_distance(lot.mailbox) < WALK_W - 6.0:
			warnings.append("%s: mailbox on the road" % label)
	for key in per_bulb:
		if int(per_bulb[key]) < 4:
			warnings.append("Cul-de-sac %s has only %d homes" % [key, int(per_bulb[key])])
	return warnings


## Flood-fills the walkable surface from `start` and reports every lot whose
## inspection point cannot be reached on foot. Slow-ish (grid search); tools only.
func unreachable_lots(start: Vector2, step := 14.0) -> Array:
	var seen := {}
	var queue: Array = []
	var key := func(p: Vector2) -> Vector2i: return Vector2i(roundi(p.x / step), roundi(p.y / step))
	seen[key.call(start)] = true
	queue.append(start)
	var head := 0
	while head < queue.size():
		var p: Vector2 = queue[head]
		head += 1
		for d in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
			var q: Vector2 = p + d
			var k: Vector2i = key.call(q)
			if seen.has(k) or not is_walkable(q):
				continue
			seen[k] = true
			queue.append(q)
	var missing: Array = []
	for lot in lots:
		var near_reached := false
		var target: Vector2 = lot.driveway_mid()
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if seen.has(Vector2i(roundi(target.x / step) + dx, roundi(target.y / step) + dy)):
					near_reached = true
		if not near_reached:
			missing.append(lot.id)
	return missing


# ---------------------------------------------------------------- navigation

var _nav: AStarGrid2D
var _nav_step := 14.0


## Grid path-finding over the same walkable surface the player uses. Used by the
## training-video director and available for in-game route hints.
func build_nav(step := 14.0) -> void:
	_nav_step = step
	_nav = AStarGrid2D.new()
	_nav.region = Rect2i(0, 0, int(WORLD_W / step) + 1, int(WORLD_H / step) + 1)
	_nav.cell_size = Vector2(step, step)
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()
	for x in _nav.region.size.x:
		for y in _nav.region.size.y:
			if not is_walkable(Vector2(x, y) * step):
				_nav.set_point_solid(Vector2i(x, y), true)


## Waypoints from `from` to `to`, or an empty array when unreachable.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _nav == null:
		build_nav()
	var a := Vector2i((from / _nav_step).round())
	var b := Vector2i((to / _nav_step).round())
	for cell in [a, b]:
		if _nav.is_in_boundsv(cell) and _nav.is_point_solid(cell):
			var found := false
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					var c: Vector2i = cell + Vector2i(dx, dy)
					if not found and _nav.is_in_boundsv(c) and not _nav.is_point_solid(c):
						_nav.set_point_solid(cell, false)
						found = true
	var cells := _nav.get_id_path(a, b)
	var result := PackedVector2Array()
	for cell in cells:
		result.append(Vector2(cell) * _nav_step)
	return result
