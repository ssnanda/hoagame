extends SceneTree
## Walkability QA (sections 22-29, 56-58): sloppy thumb input along every sidewalk must keep the
## player moving and near the walk; steering assist must help parallel walking without
## stopping deliberate crossings; front lawns are cuttable but houses and back yards are not.
##   godot --headless --path . --script res://tools/qa_walk.gd
const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const PlayerController := preload("res://scripts/world/player_controller.gd")

var problems := 0


func _init() -> void:
	var hood = Neighborhood.new()
	hood.build()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# A. Sloppy walking along each street's sidewalk, assist on vs off.
	var err_on := 0.0
	var err_off := 0.0
	var stuck := 0
	var samples := 0
	for street in hood.streets:
		for side in [-1, 1]:
			for mode in 2:
				var pc := PlayerController.new()
				pc.assist_enabled = mode == 0
				var start := _walk_point(hood, street, 80.0, side)
				pc.position = start
				var total_err := 0.0
				var steps := 0
				var progress_from := pc.position
				for step in 600:
					# Intended direction: along the street. Thumb error: slowly wandering +-30 degrees.
					var tan: Vector2 = hood.sample(street, minf(80.0 + step * 1.2, street.length - 30.0))[1]
					var wobble := sin(step * 0.07 + side) * 0.22 + rng.randf_range(-0.06, 0.06)
					pc.update(1.0 / 60.0, tan.rotated(wobble), hood, [], [])
					var frame := hood.sidewalk_frame(pc.position)
					if not frame.is_empty():
						total_err += (frame.to_center as Vector2).length()
						steps += 1
				if pc.position.distance_to(progress_from) < 60.0:
					stuck += 1
				if steps > 0:
					if mode == 0:
						err_on += total_err / steps
					else:
						err_off += total_err / steps
					samples += 1
	print("WALK: sidewalk centre error with assist %.1f px vs without %.1f px; stuck runs %d" % [err_on / maxf(samples * 0.5, 1.0), err_off / maxf(samples * 0.5, 1.0), stuck])
	_check(stuck == 0, "player got stuck walking along a sidewalk")
	_check(err_on <= err_off * 0.9, "steering assist did not reduce the sidewalk error by at least 10%")
	# B. Deliberate crossing is never stopped by assist: walk from the sidewalk straight at a house front.
	var lot = hood.lots[40]
	var pc2 := PlayerController.new()
	pc2.position = lot.inspect_anchor()
	var goal: Vector2 = lot.center + lot.front * (lot.house_size.x * 0.5 + 30.0)
	var dir: Vector2 = (goal - pc2.position).normalized()
	var before := pc2.position
	for step in 90:
		pc2.update(1.0 / 60.0, dir, hood, [], [])
	var free := PlayerController.WALK_SPEED * 1.5 * 0.7
	_check(pc2.position.distance_to(before) > 60.0, "crossing toward the lawn was blocked or fought (%.0f px)" % pc2.position.distance_to(before))
	# C. Terrain rules: front lawn, driveway and verge walkable; house and back yard not.
	var lawn: Vector2 = lot.local_point(lot.house_size.x * 0.5 + 34.0, 0.0)
	_check(hood.is_walkable(lawn), "open front lawn is not walkable")
	_check(not hood.is_walkable(lot.center), "the house itself is walkable")
	_check(not hood.is_walkable(lot.local_point(-lot.house_size.x * 0.5 - 20.0, 0.0)), "back yard is walkable")
	_check(hood.is_walkable(lot.inspect_anchor()), "inspection anchor not walkable")
	# D. Every anchor has a route from the spawn point.
	var spawn := Vector2(hood.spine_x(6900.0) - (hood.AVENUE_HALF + hood.WALK_W * 0.5), 6900.0)
	var missing: Array = hood.unreachable_lots(spawn)
	_check(missing.is_empty(), "%d lot(s) unreachable: %s" % [missing.size(), str(missing.slice(0, 6))])
	print("QA WALK: %d problem(s)" % problems)
	quit(1 if problems > 0 else 0)


func _walk_point(hood, street, s: float, side: int) -> Vector2:
	var smp: Array = hood.sample(street, s)
	var t: Vector2 = smp[1]
	return (smp[0] as Vector2) + Vector2(-t.y, t.x) * float(side) * (street.half + hood.WALK_W * 0.5)


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("  FAIL: ", msg)
		problems += 1
