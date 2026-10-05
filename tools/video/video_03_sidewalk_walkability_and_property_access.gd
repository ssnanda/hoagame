extends "res://tools/video/video_lib.gd"
## VIDEO 03: sidewalk walkability and property access. A continuous tour with the virtual thumb:
## avenue sidewalk -> side street -> corner lot -> cul-de-sac ring -> a house with a driveway car,
## a street tree and a mailbox (walk to its inspection anchor) -> cut across the front lawn ->
## try to walk into the house (blocked) -> back to the sidewalk. No teleport while recording.
## Seed 3033. Setup (hidden): new game, tutorial skipped.

var arm
var target_lot


func _setup() -> void:
	var spawn: Vector2 = street.spawn_point()
	# The side street closest to the start, west of the avenue.
	var best := INF
	for st in hood.streets:
		if st.id == 0:
			continue
		var d: float = absf((st.path[0] as Vector2).y - spawn.y)
		if d < best and (st.path[st.path.size() - 1] as Vector2).x < (st.path[0] as Vector2).x:
			best = d
			arm = st
	# A cul-de-sac house with a driveway car and a nearby street tree.
	var driveway_cars := {}
	for p in street.ambient.parked:
		if str(p.kind) == "driveway":
			driveway_cars[int(p.lot)] = true
	for lot in hood.lots:
		if lot.street_id == arm.id and lot.kind == "cul_de_sac" and driveway_cars.has(lot.id):
			target_lot = lot
			break
	if target_lot == null:
		for lot in hood.lots:
			if lot.street_id == arm.id and lot.kind == "cul_de_sac":
				target_lot = lot
				break
	print("VIDEO03 arm=", arm.name, " target=", target_lot.address, " has_car=", driveway_cars.has(target_lot.id))


func _corner_lot_near(p: Vector2):
	var best = null
	var bd := INF
	for lot in hood.lots:
		if lot.kind == "corner":
			var d: float = lot.inspect_anchor().distance_to(p)
			if d < bd:
				bd = d
				best = lot
	return best


func _ready() -> void:
	await boot_hidden(3033, true, "VIDEO 03", "SIDEWALK / PROPERTY ACCESS TEST", _setup)
	await wait(2.5)
	var slow := 0.5
	# --- A. a long walk down the avenue sidewalk (trees, parked cars, driveways, crosswalks) -----------------------
	var av = hood.streets[0]
	var s0 := nearest_s(av, street.player.position)
	var s_mouth := nearest_s(av, arm.path[0])
	var side := best_side(av, s0, street.player.position)
	var pts: Array = []
	var s := s0
	var far_end := maxf(s_mouth - 900.0, 80.0)                  # walk well past the side street first
	while s > far_end:
		pts.append(sidewalk_point(av, s, side))
		s -= 70.0
	await follow(pts, slow)
	await wait(2.0)
	# --- B. back to the side street's corner lot ---------------------------------------------------------------------------
	var corner = _corner_lot_near(arm.path[0])
	if corner != null:
		await walk_to(corner.inspect_anchor(), 36.0, 60.0, false, slow)
		await wait(3.0)                                         # corner lot: fence/hedge, street sign, mailbox
	# --- C. along the side street -----------------------------------------------------------------------------------------------
	var arm_side := best_side(arm, 60.0, street.player.position)
	var pts2: Array = []
	s = 90.0
	while s < arm.length - 130.0:
		pts2.append(sidewalk_point(arm, s, arm_side))
		s += 70.0
	await follow(pts2, slow)
	await wait(1.5)
	# --- D. all the way around the cul-de-sac ring --------------------------------------------------------------
	var bulb: Vector2 = arm.bulbs[0].center
	var ring: Array = []
	var a0: float = (street.player.position - bulb).angle()
	for k in 26:
		var ang: float = a0 + 0.24 * float(k) * (1.0 if arm_side > 0 else -1.0)
		ring.append(bulb + Vector2.from_angle(ang) * (Neighborhood.BULB_R + Neighborhood.WALK_W * 0.5))
	await follow(ring, slow)
	await wait(1.5)
	# --- E. the house with a driveway car, tree and mailbox: its inspection anchor ----------------------------
	await walk_to(target_lot.inspect_anchor(), 30.0, 60.0, false, slow)
	await wait(3.0)
	await pinch(Vector2(360.0, 620.0), 120.0, 300.0, 1.4)     # a closer look at the frontage
	await wait(3.5)
	# --- F. cut across the front lawn, then try the house and the side yard (both blocked) -----------------
	var hx: float = target_lot.house_size.x * 0.5
	var lawn: Vector2 = target_lot.local_point(hx + 30.0, 0.0)
	await walk_to(lawn, 24.0, 20.0, false, slow)
	await wait(1.5)
	await push_direction(-target_lot.front, 2.6)             # into the house: it stops the player
	await wait(1.5)
	await push_direction(target_lot.right() * 1.0 - target_lot.front * 0.5, 2.4)   # toward the side yard: also closed
	await wait(1.5)
	await walk_to(target_lot.inspect_anchor() + target_lot.front * 12.0, 30.0, 20.0, false, slow)
	await tap_hud(street.hud_view.zoom_reset_rect())
	await wait(2.0)
	# --- G. a deliberate drift off the sidewalk onto the verge: allowed, and gently steered back -------------
	await push_direction(target_lot.front.rotated(0.9), 1.6)
	await wait(1.5)
	# --- H. a second house in the ring: another anchor -----------------------------------------------------------------
	var other = null
	for lot in hood.lots:
		if lot.street_id == arm.id and lot.kind == "cul_de_sac" and lot.id != target_lot.id:
			if other == null or lot.inspect_anchor().distance_to(target_lot.inspect_anchor()) > other.inspect_anchor().distance_to(target_lot.inspect_anchor()):
				other = lot
	if other != null:
		await walk_to(other.inspect_anchor(), 30.0, 60.0, false, slow)
		await wait(3.0)
	await finish()
