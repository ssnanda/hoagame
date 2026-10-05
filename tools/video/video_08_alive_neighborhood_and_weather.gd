extends "res://tools/video/video_lib.gd"
## VIDEO 08: a living neighborhood and the real weather system. Segment A: a sunny weekday morning: the golf cart
## along the avenue, then on foot toward people (jogger, dog walker, mail carrier, gardener, contractor, visitor car,
## neighbors chatting) and a porch resident at a complaint house. Segment B: a different day whose actual forecast is
## thunderstorms (new morning brief, then rain and lightning). Seed 8088.
## Setup (hidden): choose the two days from Weather.for_day. A dip to black separates the segments.

var sunny_day := -1
var storm_day := -1


func _find_days() -> void:
	for d in range(2, 28):
		var season := ((d - 1) / 14) % 4
		var weekday := (d - 1) % 7
		var w: int = Weather.for_day(d, season)
		if weekday < 5 and sunny_day < 0 and w == Weather.SUNNY and season in [0, 1]:
			sunny_day = d
		if weekday < 5 and storm_day < 0 and w == Weather.STORM:
			storm_day = d
	if sunny_day < 0:
		sunny_day = 2
	if storm_day < 0:
		for d in range(2, 40):
			if Weather.for_day(d, ((d - 1) / 14) % 4) in [Weather.RAIN, Weather.STORM]:
				storm_day = d
				break


func _setup() -> void:
	_find_days()
	GameState.day = sunny_day
	main._new_day()
	main._morning_queue.clear()
	main._close_overlay()
	await wait(0.4)
	print("VIDEO08 sunny_day=", sunny_day, " storm_day=", storm_day, " weather_now=", Weather.name_of(street.weather))


func _actor_getters() -> Array:
	var amb = street.ambient
	var out: Array = []
	for w in amb.walkers:
		if bool(w.get("jog", false)):
			out.append(["jogger", func(): return amb.walker_position(w)])
			break
	for w in amb.walkers:
		if bool(w.get("dog", false)) and not bool(w.get("jog", false)):
			out.append(["dog walker", func(): return amb.walker_position(w)])
			break
	for w in amb.walkers:
		if bool(w.get("mail", false)):
			out.append(["mail carrier", func(): return amb.walker_position(w)])
			break
	for g in amb.gardeners:
		out.append(["gardener", func(): return amb.gardener_position(g)])
		break
	for c in amb.crews:
		out.append(["crew:" + str(c.kind), func(): return amb.crew_worker_position(c)])
		break
	for m in amb.movers:
		out.append(["visitor car", func(): return amb.mover_pose(m).pos if bool(amb.mover_pose(m).visible) else Vector2.INF])
		break
	for t in amb.talkers:
		out.append(["neighbors chatting", func(): return amb.talker_positions(t)[0]])
		break
	return out


func _ready() -> void:
	await boot_hidden(8088, true, "VIDEO 08", "ALIVE NEIGHBORHOOD + WEATHER", _setup)
	await wait(2.0)
	# --- A1. the golf cart along the avenue --------------------------------------------------------
	var w_cart: Vector2 = Vector2(street.hud_view.size.x - 66.0, street.hud_view.size.y - 262.0)
	await tap_hud_point(w_cart)                  # get in (real CART button)
	await wait(1.4)
	var av = hood.streets[0]
	var s0 := nearest_s(av, street.player.position)
	var pts: Array = []
	for k in 14:
		pts.append(sidewalk_point(av, maxf(s0 - 90.0 * (k + 1), 40.0), best_side(av, s0, street.player.position)))
	await follow(pts, 0.8, 50.0, 40.0)
	await tap_hud_point(w_cart)                  # park and step out
	await wait(1.6)
	# --- A2. on foot toward the people and activity -------------------------------------------------
	var seen: Array = []
	for item in _actor_getters():
		var first: Vector2 = item[1].call()
		if first == Vector2.INF or first.distance_to(street.player.position) > 1400.0:
			seen.append(str(item[0]) + " too far, skipped")
			continue
		var got: bool = await chase(item[1], 120.0, 20.0, 0.8)
		seen.append(str(item[0]) + (" reached" if got else " not reached"))
		await wait(2.5)
	print("VIDEO08 actors: ", seen)
	# --- A3. a porch resident at a complaint house --------------------------------------------------------
	var target := -1
	var best := INF
	for h in main.sim.assignments:
		var d: float = street.player.position.distance_to(hood.lots[int(h)].inspect_anchor())
		if d < best:
			best = d
			target = int(h)
	street.select_objective(target)
	await walk_to(hood.lots[target].inspect_anchor(), 40.0, 60.0, false, 0.75)
	await wait(4.0)                              # the resident steps onto the porch
	# --- B. a stormy day (the real forecast) -----------------------------------------------------------------
	var fade := await fade_black(0.7)
	GameState.day = storm_day
	main._new_day()                              # the real morning brief appears with the forecast
	build_nav()                                  # a new day has new parked cars: refresh the route planner
	await wait(0.5)
	await unfade(fade, 0.6)
	await wait(2.5)
	await press("START THE DAY")
	await dismiss_modals()
	await wait(1.5)
	var av_s := nearest_s(av, street.player.position)
	var pts2: Array = []
	var dir_s := -1.0 if av_s > av.length * 0.5 else 1.0
	for k in 30:
		pts2.append(sidewalk_point(av, clampf(av_s + dir_s * 70.0 * (k + 1), 40.0, av.length - 40.0), best_side(av, av_s, street.player.position)))
	await follow(pts2, 0.55, 40.0, 45.0)
	await wait(6.0)                              # rain, gloom, lightning
	await finish()
