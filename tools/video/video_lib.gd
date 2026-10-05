extends Node
## Shared driver for the gameplay review videos. Runs the REAL game scene and plays it
## through the real input path (mouse/touch events pushed into the viewport, real buttons),
## so what the video shows is what a player would get. Capture-only code lives here, never in
## the shipping scripts (except the tiny Encounters.force_next QA hook).
##
## One video per Godot run:
##   HOME=<scratch> godot --path . --write-movie out.avi --fixed-fps 30 --resolution 720x1280 \
##        res://tools/video/video_NN_xxx.tscn

const MainScene := preload("res://scenes/main.tscn")
const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const Weather := preload("res://scripts/sim/weather.gd")
const LotSlots := preload("res://scripts/world/lot_slots.gd")
const FPS := 30.0
const STICK_RANGE := 86.0

var main: Node
var street: Node
var hood
var _overlay: CanvasLayer
var _dots: Control
var _pointer := Vector2(-100, -100)
var _pointer_down := false
var _ripples: Array = []
var _nav: AStarGrid2D
var _mouse_down_pos := Vector2.ZERO
var _stick_active := false
var _heading := Vector2.ZERO
var _wander := 0.0
var _rng := RandomNumberGenerator.new()
var _last_state := ""
var _last_obj := -2
var _stuck_pos := Vector2.ZERO
var _stuck_frames := 0


# ---------------------------------------------------------------- boot

## Starts the real game behind a title card. `setup` (optional) runs while the card hides the
## screen: deterministic state only (cases, positions, days). Nothing visible is faked.
func boot_hidden(seed_value: int, tutorial_done: bool, title_a: String, title_b: String, setup: Callable = Callable(), start_new_game := true) -> void:
	seed(seed_value)
	_rng.seed = seed_value
	Settings.tutorial_done = tutorial_done
	Settings.haptics = false
	_make_overlay()
	var card := _make_card(title_a, title_b)
	main = MainScene.instantiate()
	add_child(main)
	await wait(0.4)
	street = main._street
	hood = street.hood
	main.sim.rng.seed = seed_value
	if start_new_game:
		main._begin(false)
		await wait(0.3)
		if main.sim.assignments.is_empty():
			# A fresh player normally sees the intro first; setup starts day one directly.
			main._close_overlay()
			main._new_day()
			await wait(0.3)
		# Dismiss the brief/intro the way setup (not the viewer) would; the viewer sees the world.
		main._morning_queue.clear()
		main._close_overlay()
		await wait(0.3)
	if setup.is_valid():
		await setup.call()
	build_nav()                    # after setup: the route planner must see today's parked cars and yard objects
	await wait(1.1)
	card.queue_free()
	await wait(0.2)


func _make_card(line_a: String, line_b: String) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color("14202b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(box)
	for text in [line_a, line_b]:
		var l := Label.new()
		l.text = text
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 54 if text == line_a else 34)
		l.add_theme_color_override("font_color", Color("ffd36e") if text == line_a else Color.WHITE)
		box.add_child(l)
	return bg


## Black dip used between separate segments that need different setup (e.g. another day).
func fade_black(seconds: float) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg)
	var t := create_tween()
	t.tween_property(bg, "color:a", 1.0, seconds)
	await wait(seconds + 0.1)
	return bg


func unfade(bg: ColorRect, seconds: float) -> void:
	var t := create_tween()
	t.tween_property(bg, "color:a", 0.0, seconds)
	await wait(seconds + 0.1)
	bg.queue_free()


## Starts the real game. `tutorial_done` false = a genuinely fresh player (intro, scripted first case).
func boot(seed_value: int, tutorial_done: bool, title_a := "", title_b := "") -> void:
	seed(seed_value)
	_rng.seed = seed_value
	Settings.tutorial_done = tutorial_done
	Settings.haptics = false
	_make_overlay()
	if title_a != "":
		await show_title_card(title_a, title_b, 1.4)
	main = MainScene.instantiate()
	add_child(main)
	await wait(0.6)
	street = main._street
	hood = street.hood
	main.sim.rng.seed = seed_value


func _make_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	_dots = Control.new()
	_dots.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_draw_dots)
	_overlay.add_child(_dots)


func show_title_card(line_a: String, line_b: String, seconds: float) -> void:
	var bg := ColorRect.new()
	bg.color = Color("14202b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(box)
	for text in [line_a, line_b]:
		var l := Label.new()
		l.text = text
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 54 if text == line_a else 34)
		l.add_theme_color_override("font_color", Color("ffd36e") if text == line_a else Color.WHITE)
		box.add_child(l)
	await wait(seconds)
	bg.queue_free()


# ---------------------------------------------------------------- time

func wait(seconds: float) -> void:
	# Waits in DRAWN frames so every game step ends up in the movie (the window must be on screen).
	var n := maxi(1, int(round(seconds * FPS)))
	var start := Engine.get_frames_drawn()
	var guard := 0
	while Engine.get_frames_drawn() - start < n and guard < n * 8 + 60:
		await get_tree().process_frame
		_tick_overlay()
		guard += 1


## Timestamp log for the video index: "MARK|seconds|text" (movie time = drawn frames / 30).
func mark(text: String) -> void:
	printerr("MARK|%.1f|%s" % [float(Engine.get_frames_drawn()) / FPS, text])


func _tick_overlay() -> void:
	if main != null and is_instance_valid(main) and "ui_state" in main:
		if main.ui_state != _last_state:
			_last_state = main.ui_state
			mark("state " + _last_state)
		if street != null and int(street.objective) != _last_obj:
			_last_obj = int(street.objective)
			mark("objective -> " + (hood.lots[_last_obj].address if _last_obj >= 0 else "none"))
	for r in _ripples:
		r.age += 1.0 / FPS
	_ripples = _ripples.filter(func(r): return r.age < 0.5)
	_dots.queue_redraw()


func _draw_dots() -> void:
	# A small, clean touch indicator so a reviewer can follow what the "finger" is doing.
	for r in _ripples:
		var k: float = r.age / 0.5
		_dots.draw_arc(r.pos, 14.0 + 34.0 * k, 0.0, TAU, 28, Color(1, 1, 1, 0.55 * (1.0 - k)), 3.0)
	if _pointer_down:
		_dots.draw_circle(_pointer, 22.0, Color(1, 1, 1, 0.28))
		_dots.draw_circle(_pointer, 9.0, Color(1, 1, 1, 0.65))


# ---------------------------------------------------------------- real input

func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)
	_pointer = pos
	_pointer_down = pressed


func _mouse_motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if _pointer_down else 0
	Input.parse_input_event(e)
	_pointer = pos


## A quick tap at a screen position, exactly like a finger.
func tap(pos: Vector2) -> void:
	_mouse_motion(pos, Vector2.ZERO)
	await wait(0.12)
	_mouse_button(pos, true)
	_ripples.append({"pos": pos, "age": 0.0})
	await wait(0.1)
	_mouse_button(pos, false)
	await wait(0.2)


func find_button(text: String, node: Node = null) -> Button:
	node = node if node != null else main
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree() and not (node as Button).disabled:
		return node
	for child in node.get_children():
		var found := find_button(text, child)
		if found != null:
			return found
	return null


func has_button(text: String) -> bool:
	return find_button(text) != null


## Taps a real button by its label. Waits for it to exist first.
func press(text: String, patience := 5.0) -> bool:
	var waited := 0.0
	var b := find_button(text)
	while b == null and waited < patience:
		await wait(0.1)
		waited += 0.1
		b = find_button(text)
	if b == null:
		push_warning("VIDEO: button '%s' never appeared (state %s)" % [text, main.ui_state])
		return false
	mark("press " + text)
	await tap(b.get_global_rect().get_center())
	return true


## HUD-drawn controls (camera shutter, Cancel/Album, Next chip, minimap) are tapped by rect.
func tap_hud(rect: Rect2) -> void:
	await tap(street.hud_view.global_position + rect.get_center())


func tap_hud_point(p: Vector2) -> void:
	await tap(street.hud_view.global_position + p)


## Taps the big shutter until a photo preview appears (adjusting zoom like a player would).
func shoot_until_preview(max_tries := 6) -> bool:
	for attempt in max_tries:
		await wait(0.6)
		if street.camera_ev.zoom > 2.1:
			await tap_hud(street.hud_view._zoom_buttons().minus)
		await tap_hud_point(street.hud_view.camera_shutter())
		await wait(0.9)
		if main.ui_state == "PHOTO_PREVIEW":
			return true
		# Not usable / duplicate: nudge the zoom and try again.
		await tap_hud(street.hud_view._zoom_buttons().plus if attempt % 2 == 0 else street.hud_view._zoom_buttons().minus)
	return main.ui_state == "PHOTO_PREVIEW"


func wait_state(state: String, patience := 8.0) -> bool:
	var waited := 0.0
	while main.ui_state != state and waited < patience:
		await wait(0.1)
		waited += 0.1
	return main.ui_state == state


# ---------------------------------------------------------------- walking with a virtual thumb

func build_nav() -> void:
	## Route planner for the "thumb": prefers sidewalks and lawns over the road, never blocked cells.
	var step := 14.0
	_nav = AStarGrid2D.new()
	_nav.region = Rect2i(0, 0, int(Neighborhood.WORLD_W / step) + 1, int(Neighborhood.WORLD_H / step) + 1)
	_nav.cell_size = Vector2(step, step)
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.update()
	for x in _nav.region.size.x:
		for y in _nav.region.size.y:
			var p := Vector2(x, y) * step
			if not hood.is_walkable(p):
				_nav.set_point_solid(Vector2i(x, y), true)
			else:
				var ed: float = hood.edge_distance(p)
				_nav.set_point_weight_scale(Vector2i(x, y), 3.0 if ed <= 0.0 else (1.0 if ed <= Neighborhood.WALK_W else 2.2))   # sidewalks first, then lawns, roads last
	_mark_obstacles_solid()


## Parked cars, crew trucks and yard objects are fixed for the day: route around them like a person would.
func _mark_obstacles_solid() -> void:
	var step := 14.0
	var entries: Array = []
	for e in street._static_obstacles:
		entries.append(e)
	for e in street.ambient.obstacles():
		var src := str(e.get("src", ""))
		if src.begins_with("parked") or src.begins_with("crew"):
			entries.append(e)
	for e in entries:
		var pos: Vector2 = e.pos
		var reach: float = maxf((e.half as Vector2).x, (e.half as Vector2).y) + 28.0
		var x0 := int((pos.x - reach) / step)
		var x1 := int((pos.x + reach) / step) + 1
		var y0 := int((pos.y - reach) / step)
		var y1 := int((pos.y + reach) / step) + 1
		for cx in range(x0, x1 + 1):
			for cy in range(y0, y1 + 1):
				var cell := Vector2i(cx, cy)
				if _nav.is_in_boundsv(cell) and LotSlots.entry_contains(e, Vector2(cell) * step, 22.0):
					_nav.set_point_solid(cell, true)


func plan(from: Vector2, to: Vector2) -> PackedVector2Array:
	if _nav == null:
		build_nav()
	var step := 14.0
	var a := Vector2i((from / step).round())
	var b := Vector2i((to / step).round())
	for cell in [a, b]:
		if _nav.is_in_boundsv(cell) and _nav.is_point_solid(cell):
			_nav.set_point_solid(cell, false)
	var ids := _nav.get_id_path(a, b)
	var out := PackedVector2Array()
	for c in ids:
		out.append(Vector2(c) * step)
	return out


## Walks the player to `target` by dragging a virtual thumb, with natural small corrections.
## Returns true when it arrived within `radius` px. Never teleports.
func walk_to(target: Vector2, radius := 40.0, timeout := 40.0, calm := false, strength := 0.95) -> bool:
	mark("walk start (%d px to go)" % int(street.player.position.distance_to(target)))
	var path := plan(street.player.position, target)
	if path.size() < 2 and street.player.position.distance_to(target) > radius:
		# The planner found no clean route (a parked car hems in the start): head straight for it and
		# let the unstick logic steer around whatever is in the way, like a person would.
		mark("walk: no planned route, heading straight")
		path = PackedVector2Array([street.player.position, target])
	if path.size() < 2:
		return street.player.position.distance_to(target) <= radius
	var idx := 0
	var elapsed := 0.0
	_begin_stick()
	while elapsed < timeout:
		var pos: Vector2 = street.player.position
		if pos.distance_to(target) <= radius:
			break
		# Advance along the path and aim at a point ahead of us.
		while idx < path.size() - 1 and pos.distance_to(path[idx]) < 36.0:
			idx += 1
		var look := idx
		while look < path.size() - 1 and pos.distance_to(path[look]) < 90.0:
			look += 1
		var want: Vector2 = (path[look] - pos).normalized()
		# Human-ish: smooth the direction and let it wander a little.
		if not calm:
			_wander = clampf(_wander + _rng.randf_range(-0.25, 0.25) / FPS, -0.12, 0.12)
		want = want.rotated(_wander)
		_heading = _heading.lerp(want, 1.0 - exp(-7.0 / FPS)) if _heading != Vector2.ZERO else want
		_stick_to(_heading.normalized(), strength)
		await wait(1.0 / FPS)
		elapsed += 1.0 / FPS
		if _is_stuck():
			await _sidestep_out()
			path = plan(street.player.position, target)
			idx = 0
	await _end_stick()
	mark("walk end (%d px from target)" % int(street.player.position.distance_to(target)))
	return street.player.position.distance_to(target) <= radius


## True when the thumb has been pushing but the player has not moved for a moment. A real
## player would steer around: toward the sidewalk centre, or back off.
func _is_stuck() -> bool:
	_stuck_frames += 1
	if _stuck_frames >= 50:
		var moved: float = street.player.position.distance_to(_stuck_pos)
		_stuck_pos = street.player.position
		_stuck_frames = 0
		return moved < 30.0
	return false


func _blocked_at(p: Vector2) -> bool:
	if not hood.is_walkable(p):
		return true
	for e in street._nearby_obstacles():
		if LotSlots.entry_contains(e, p, 16.0):
			return true
	return false


func _sidestep_out() -> void:
	_stuck_frames = 0
	var pos: Vector2 = street.player.position
	var fwd: Vector2 = _heading.normalized() if _heading != Vector2.ZERO else Vector2.DOWN
	var left := fwd.rotated(-PI * 0.5)
	var right := fwd.rotated(PI * 0.5)
	var out := left
	var frame: Dictionary = hood.sidewalk_frame(pos)
	var best_score := -1.0
	for cand in [left, right, left.lerp(-fwd, 0.5).normalized(), right.lerp(-fwd, 0.5).normalized()]:
		var score := 0.0
		for dist in [30.0, 60.0, 90.0]:
			if not _blocked_at(pos + cand * dist):
				score += 1.0
		if not frame.is_empty() and cand.dot((frame.to_center as Vector2).normalized()) > 0.2:
			score += 0.5
		if score > best_score:
			best_score = score
			out = cand
	mark("unstick: stepping around an obstacle")
	for k in 28:
		_stick_to(out.rotated(_rng.randf_range(-0.15, 0.15)), 0.9)
		await wait(1.0 / FPS)
	# Then bear forward past it.
	for k in 24:
		_stick_to((fwd * 0.8 + out * 0.4).normalized(), 0.9)
		await wait(1.0 / FPS)
	_heading = Vector2.ZERO


## Continuous walk through waypoints without lifting the thumb (sidewalk tours).
func follow(points: Array, strength := 0.7, radius := 34.0, timeout := 90.0) -> void:
	_begin_stick()
	var idx := 0
	var elapsed := 0.0
	while idx < points.size() and elapsed < timeout:
		var pos: Vector2 = street.player.position
		while idx < points.size() and pos.distance_to(points[idx]) < radius:
			idx += 1
		if idx >= points.size():
			break
		var want: Vector2 = ((points[idx] as Vector2) - pos).normalized()
		_wander = clampf(_wander + _rng.randf_range(-0.25, 0.25) / FPS, -0.10, 0.10)
		want = want.rotated(_wander)
		_heading = _heading.lerp(want, 1.0 - exp(-7.0 / FPS)) if _heading != Vector2.ZERO else want
		_stick_to(_heading.normalized(), strength)
		await wait(1.0 / FPS)
		elapsed += 1.0 / FPS
		if _is_stuck():
			await _sidestep_out()
			idx = mini(idx + 1, points.size())     # carry on with the next waypoint once past the obstacle
	await _end_stick()


## Point on a street's sidewalk centreline at arc length s, on side +1 / -1.
func sidewalk_point(st, s: float, side: int) -> Vector2:
	var smp: Array = hood.sample(st, s)
	var t: Vector2 = smp[1]
	return (smp[0] as Vector2) + Vector2(-t.y, t.x) * float(side) * (st.half + Neighborhood.WALK_W * 0.5)


func nearest_s(st, p: Vector2) -> float:
	var best := INF
	var bs := 0.0
	var s := 0.0
	while s <= st.length:
		var d: float = (hood.sample(st, s)[0] as Vector2).distance_to(p)
		if d < best:
			best = d
			bs = s
		s += 20.0
	return bs


func best_side(st, s: float, p: Vector2) -> int:
	return 1 if sidewalk_point(st, s, 1).distance_to(p) <= sidewalk_point(st, s, -1).distance_to(p) else -1


func _begin_stick() -> void:
	_mouse_down_pos = Vector2(360.0, 980.0)
	_mouse_motion(_mouse_down_pos, Vector2.ZERO)
	_mouse_button(_mouse_down_pos, true)
	_stick_active = true
	_heading = Vector2.ZERO


func _stick_to(dir: Vector2, strength: float) -> void:
	var target := _mouse_down_pos + dir * STICK_RANGE * strength
	_mouse_motion(target, target - _pointer)


func _end_stick() -> void:
	if _stick_active:
		_mouse_button(_pointer, false)
		_stick_active = false
	await wait(0.25)


## Two-finger pinch (real ScreenTouch/ScreenDrag events). `to_dist` > `from_dist` zooms in.
func pinch(center: Vector2, from_dist: float, to_dist: float, seconds: float) -> void:
	var steps := maxi(2, int(seconds * FPS))
	for finger in 2:
		var e := InputEventScreenTouch.new()
		e.index = finger
		e.pressed = true
		e.position = center + Vector2((from_dist * 0.5) * (1.0 if finger == 1 else -1.0), 0.0)
		Input.parse_input_event(e)
	for k in steps:
		var d := lerpf(from_dist, to_dist, float(k + 1) / steps)
		for finger in 2:
			var drag := InputEventScreenDrag.new()
			drag.index = finger
			drag.position = center + Vector2((d * 0.5) * (1.0 if finger == 1 else -1.0), 0.0)
			Input.parse_input_event(drag)
		_pointer = center
		_pointer_down = true
		await wait(1.0 / FPS)
	for finger in 2:
		var up := InputEventScreenTouch.new()
		up.index = finger
		up.pressed = false
		up.position = center
		Input.parse_input_event(up)
	_pointer_down = false
	await wait(0.4)


## Holds the thumb in one direction for a time (used to show a wall/house blocking the player).
func push_direction(dir: Vector2, seconds: float) -> void:
	_begin_stick()
	var t := 0.0
	while t < seconds:
		_stick_to(dir.normalized(), 1.0)
		await wait(1.0 / FPS)
		t += 1.0 / FPS
	await _end_stick()


# ---------------------------------------------------------------- helpers for videos

## Rebuilds the street's pins/objects from the current assignments (like a new morning, minus the day roll).
## Setup-time only: used to stage a specific case before the viewer sees the world.
func refresh_world(select_house := -1) -> void:
	var pins := {}
	var visuals := {}
	for house in main.sim.assignments:
		var h := int(house)
		var a: Dictionary = main.sim.assignments[house]
		pins[h] = "done" if h in main.sim.completed else str(a.kind)
		visuals[h] = a.violations
	for house in main.sim.discoverable:
		visuals[int(house)] = main.sim.discoverable[house]
	street.set_day(pins, main._grass, main.sim.completed.size(), street.player.position, street.get_evidence(), visuals)
	if select_house >= 0:
		street.set_objective(select_house)
	street.set_discoverable(main.sim.discoverable.keys())
	street.set_case_states(main.sim.case_states())


func place_player(p: Vector2) -> void:
	## SETUP ONLY (hidden behind the title card): put the thumb's player somewhere before recording.
	street.player.position = p
	street.player.velocity = Vector2.ZERO
	street.cam = p - street.size * 0.5
	street._cam_ready = false


## Follows a moving target (a pedestrian, a vehicle) with the thumb, re-planning as it moves.
func chase(get_pos: Callable, stop_radius := 110.0, timeout := 25.0, strength := 0.8) -> bool:
	_begin_stick()
	var elapsed := 0.0
	var path := PackedVector2Array()
	var replan := 0.0
	while elapsed < timeout:
		var target: Vector2 = get_pos.call()
		var pos: Vector2 = street.player.position
		if target == Vector2.INF:
			break
		if pos.distance_to(target) <= stop_radius:
			await _end_stick()
			return true
		replan -= 1.0 / FPS
		if replan <= 0.0 or path.size() < 3:
			path = plan(pos, target)
			replan = 0.8
		var look := mini(path.size() - 1, 5)
		var aim: Vector2 = path[look] if path.size() > 1 else target
		var want := (aim - pos).normalized()
		_wander = clampf(_wander + _rng.randf_range(-0.25, 0.25) / FPS, -0.10, 0.10)
		_heading = _heading.lerp(want.rotated(_wander), 1.0 - exp(-7.0 / FPS)) if _heading != Vector2.ZERO else want
		_stick_to(_heading.normalized(), strength)
		await wait(1.0 / FPS)
		elapsed += 1.0 / FPS
		if _is_stuck():
			await _sidestep_out()
			path = PackedVector2Array()
	await _end_stick()
	return false


## Morning follow-ups (a director's call, an agenda card) after the brief: answer them like a player would.
func dismiss_modals() -> void:
	for i in 8:
		await wait(0.8)
		if main.ui_state == "WORLD":
			return
		if main._card != null and is_instance_valid(main._card):
			await wait(1.5)
			main._card.fling("left")           # the agenda card: choose the left option
			await wait(1.0)
			continue
		var btn: Button = _first_button(main._overlay)
		if btn == null:
			return
		await wait(2.2)                        # let the viewer read the call
		mark("answer: " + btn.text)
		await tap(btn.get_global_rect().get_center())


func _first_button(node: Node) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and not (node as Button).disabled:
		return node
	for child in node.get_children():
		var found := _first_button(child)
		if found != null:
			return found
	return null


func find_encounter_panel() -> Control:
	for child in main.get_children():
		if child.get_script() != null and str(child.get_script().resource_path).ends_with("encounter_panel.gd"):
			return child
	return null


## Plays an encounter panel the way a player would: read each line, tap to advance, pick a reply.
func play_panel(reply_label := "", read_extra := 1.6) -> void:
	var panel: Control = null
	for i in 80:
		panel = find_encounter_panel()
		if panel != null:
			break
		await wait(0.1)
	if panel == null:
		return
	await wait(2.2)                                   # push-in, door/garage/side entrance
	var lines: int = (panel.data.lines as Array).size()
	for i in lines:
		if not is_instance_valid(panel):
			return
		await wait_text_done(panel, read_extra)
		await tap(Vector2(360.0, 520.0))
		await wait(0.3)
	await wait(1.6)
	var choices: Array = panel.data.choices
	var label := reply_label if reply_label != "" else str(choices[0].label)
	label = panel._fill(label) if is_instance_valid(panel) else label
	await press(label)
	for i in 4:
		if is_instance_valid(panel) and panel._stage == "reply":
			await wait_text_done(panel, read_extra)
			await tap(Vector2(360.0, 520.0))
	await wait_state("WORLD", 8.0)
	await wait(2.0)

func prompt_center() -> Vector2:
	var r: Rect2 = street.hud_view.prompt_rect
	return street.hud_view.global_position + r.get_center()


func wait_text_done(panel, extra := 1.0) -> void:
	# Lets a typewriter line finish and then gives the viewer time to read it.
	var guard := 0
	while panel._text.visible_ratio < 1.0 and guard < 300:
		await wait(0.1)
		guard += 1
	await wait(extra)


func finish() -> void:
	await wait(1.2)
	get_tree().quit()
