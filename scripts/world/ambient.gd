extends RefCounted
## Life in the neighborhood: walkers, traffic, delivery and garbage trucks, crews,
## kids and parked cars. Simulation only; the world view draws it.

const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotScript := preload("res://scripts/world/lot.gd")

const PARK_OFFSET := 22.0
const CAR_SCALE := 0.8
const CAR_COLORS := [Color("e0533d"), Color("3a6fd8"), Color("f2b632"), Color("e8e8ee"), Color("2f9e57"), Color("8a6fc4"), Color("3d3f46")]

var hood: Neighborhood
var time := 0.0
var walkers: Array = []
var traffic: Array = []
var kids: Array = []
var crews: Array = []
var parked: Array = []       ## {lot, kind: driveway|curb, color}
var _rng := RandomNumberGenerator.new()


func setup(neighborhood: Neighborhood, day: int, weekday: int, skip_driveways: Dictionary) -> void:
	hood = neighborhood
	_rng.seed = day * 7919 + 13
	var weekend := weekday >= 5
	walkers.clear()
	for k in (16 if weekend else 11):
		var street = hood.streets[0] if k < 6 else hood.streets[1 + _rng.randi_range(0, hood.streets.size() - 2)]
		walkers.append({"street": street.id, "side": -1 if k % 2 == 0 else 1,
				"s0": _rng.randf_range(0.0, street.length * 2.0), "speed": _rng.randf_range(24.0, 44.0),
				"tone": k % 4, "dog": k % 3 == 1})
	traffic.clear()
	for k in 4:
		traffic.append({"kind": "car", "dir": 1 if k % 2 == 0 else -1, "s": _rng.randf_range(0.0, hood.streets[0].length),
				"speed": _rng.randf_range(80.0, 120.0), "color": CAR_COLORS[_rng.randi() % CAR_COLORS.size()],
				"pause": 0.0, "travel": 0.0, "next_stop": INF})
	if not weekend:
		traffic.append({"kind": "delivery", "dir": 1, "s": _rng.randf_range(0.0, hood.streets[0].length), "speed": 70.0,
				"color": Color("e8e1d0"), "pause": 0.0, "travel": 0.0, "next_stop": _rng.randf_range(250.0, 800.0)})
		if weekday in [1, 3]:
			traffic.append({"kind": "garbage", "dir": -1, "s": _rng.randf_range(0.0, hood.streets[0].length), "speed": 48.0,
					"color": Color("2f9e57"), "pause": 0.0, "travel": 0.0, "next_stop": _rng.randf_range(200.0, 500.0)})
	crews.clear()
	if not weekend:
		for k in 3:
			crews.append({"lot": _rng.randi_range(0, hood.lots.size() - 1), "phase": _rng.randf_range(0.0, TAU)})
	kids.clear()
	var bulbs: Array = []
	for street in hood.streets:
		for bulb in street.bulbs:
			bulbs.append(bulb.center)
	for k in (10 if weekend else 4):
		kids.append({"c": bulbs[(k * 3) % bulbs.size()], "r": _rng.randf_range(34.0, 62.0),
				"phase": _rng.randf_range(0.0, TAU), "speed": _rng.randf_range(0.8, 1.5), "tone": k % 4})
	_rebuild_parked(day, skip_driveways)


func _rebuild_parked(day: int, skip_driveways: Dictionary) -> void:
	parked.clear()
	for lot: LotScript in hood.lots:
		var roll := (lot.id * 37 + day * 11) % 100
		var color: Color = CAR_COLORS[(lot.id * 5 + day) % CAR_COLORS.size()]
		if roll < 48 and not skip_driveways.has(lot.id):
			parked.append({"lot": lot.id, "kind": "driveway", "color": color})
		elif roll >= 85 and lot.street_id != 0:
			parked.append({"lot": lot.id, "kind": "curb", "color": color})


func update(delta: float, player: Vector2) -> void:
	time += delta
	var spine = hood.streets[0]
	for v in traffic:
		if float(v.pause) > 0.0:
			v.pause = float(v.pause) - delta
			continue
		var here := traffic_pose(v)
		var ahead := (player - (here.pos as Vector2)).dot(here.heading as Vector2)
		if ahead > 0.0 and ahead < 150.0 and absf((player - (here.pos as Vector2)).dot(Vector2((here.heading as Vector2).y, -(here.heading as Vector2).x))) < 52.0:
			continue
		var step := float(v.speed) * delta
		v.s = fposmod(float(v.s) + float(v.dir) * step, spine.length)
		v.travel = float(v.travel) + step
		if v.kind != "car" and float(v.travel) >= float(v.next_stop):
			v.pause = 2.5
			v.next_stop = float(v.travel) + _rng.randf_range(250.0, 700.0)


## Position and heading of a moving vehicle (right-hand traffic on the avenue).
func traffic_pose(v: Dictionary) -> Dictionary:
	var spine = hood.streets[0]
	var smp: Array = hood.sample(spine, float(v.s))
	var t: Vector2 = smp[1]
	var n := Vector2(-t.y, t.x)
	return {"pos": (smp[0] as Vector2) + n * float(v.dir) * 10.0, "heading": t * float(v.dir)}


func walker_position(w: Dictionary) -> Vector2:
	var street = hood.streets[int(w.street)]
	var span: float = street.length
	var x := fposmod(float(w.s0) + time * float(w.speed), span * 2.0)
	var s := x if x <= span else span * 2.0 - x
	var smp: Array = hood.sample(street, s)
	var t: Vector2 = smp[1]
	return (smp[0] as Vector2) + Vector2(-t.y, t.x) * float(w.side) * (street.half + Neighborhood.WALK_W * 0.5)


func kid_position(k: Dictionary) -> Vector2:
	return (k.c as Vector2) + Vector2.from_angle(float(k.phase) + time * float(k.speed)) * float(k.r)


func parked_pose(entry: Dictionary) -> Dictionary:
	var lot: LotScript = hood.lots[int(entry.lot)]
	if str(entry.kind) == "driveway":
		var dir := (lot.driveway_end - lot.curb).normalized()
		# Nose toward the house, tucked into the upper end of the driveway.
		return {"pos": lot.curb.lerp(lot.driveway_end, 0.62), "heading": dir}
	var tangent := Vector2(-lot.front.y, lot.front.x)
	return {"pos": lot.curb + lot.front * (Neighborhood.WALK_W + PARK_OFFSET), "heading": tangent}


func crew_truck_pose(crew: Dictionary) -> Dictionary:
	var lot: LotScript = hood.lots[int(crew.lot)]
	var tangent := Vector2(-lot.front.y, lot.front.x)
	return {"pos": lot.curb + lot.front * (Neighborhood.WALK_W + PARK_OFFSET) + tangent * 70.0, "heading": tangent}


func crew_worker_position(crew: Dictionary) -> Vector2:
	var lot: LotScript = hood.lots[int(crew.lot)]
	var sweep := sin(time * 0.8 + float(crew.phase)) * (lot.house_size.y * 0.35)
	return lot.local_point(lot.house_size.x * 0.5 + 30.0 + cos(time * 0.5 + float(crew.phase)) * 10.0, sweep)


## Everything the inspector must not walk through, as oriented boxes.
func obstacles() -> Array:
	var result: Array = []
	for v in traffic:
		var pose := traffic_pose(v)
		var half := Vector2(40.0, 16.0) if v.kind == "car" else Vector2(52.0, 20.0)
		result.append({"pos": pose.pos, "rot": (pose.heading as Vector2).angle(), "half": half})
	for entry in parked:
		var pose := parked_pose(entry)
		result.append({"pos": pose.pos, "rot": (pose.heading as Vector2).angle(), "half": Vector2(36.0, 17.0)})
	for crew in crews:
		var pose := crew_truck_pose(crew)
		result.append({"pos": pose.pos, "rot": (pose.heading as Vector2).angle(), "half": Vector2(50.0, 20.0)})
	return result


## Moving people the inspector should side-step.
func circles() -> Array:
	var result: Array = []
	for w in walkers:
		result.append(walker_position(w))
	for k in kids:
		result.append(kid_position(k))
	for crew in crews:
		result.append(crew_worker_position(crew))
	return result
