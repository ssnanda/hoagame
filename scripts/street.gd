extends Control
## Street controller. Owns input, the inspector, the camera and per-day state, and
## coordinates the focused modules: Neighborhood (geometry), PlayerController,
## Ambient, EvidenceCamera, WorldView and HudView. Game rules live in main.gd.

signal visit(house: int)
signal photo_taken(house: int, quality: int, usable: bool, documented: Array)
signal evidence_changed
signal discover(house: int)

const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotScript := preload("res://scripts/world/lot.gd")
const LotSlots := preload("res://scripts/world/lot_slots.gd")
const PlayerController := preload("res://scripts/world/player_controller.gd")
const Ambient := preload("res://scripts/world/ambient.gd")
const EvidenceCamera := preload("res://scripts/world/evidence_camera.gd")
const WorldView := preload("res://scripts/world/world_view.gd")
const HudView := preload("res://scripts/world/hud_view.gd")

const ACTIVE_KINDS := ["lawn", "card", "reinspect"]
const STICK_RANGE := 86.0
const TAP_MAX_MS := 350
const TAP_SLOP := 14.0
const NEAR_DIST := 135.0
const DRIVEWAY_BIAS := 40.0
const WORLD_TILT := 0.84
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
	"Nothing to report. A rare and unsettling feeling.",
	"The hedge is within code. The hedge knows.",
	"A flag, a wreath, and a lot of confidence.",
	"No violations. The neighbors are disappointed.",
	"Compliant. Smug, but compliant.",
	"A garden gnome files a silent complaint.",
	"Perfectly legal. Mildly upsetting.",
	"Mulch recently applied. Mood: unavoidable.",
]

var hood: Neighborhood
var player: PlayerController
var ambient: Ambient
var camera_ev: EvidenceCamera
var world_view: Control
var static_root: Node2D
var hud_view: Control

# State the views read.
var cam := Vector2.ZERO
var world_scale := 1.0
var time := 0.0
var dusk := 0.0
var gloom := 0.0
var season := 0
var weather := 0
var walker_variant := 0
var pins: Dictionary = {}
var grass: Array = []
var violations: Dictionary = {}
var layouts: Dictionary = {}
var case_states: Dictionary = {}
var discoverable: Dictionary = {}
var near := -1
var objective := -1
var bubble := ""
var bubble_t := 0.0
var hint := ""
var camera_flash := 0.0
var photo_message := ""
var photo_message_t := 0.0
var frame_info: Dictionary = {}
var capturing := false
var cart_pos := Vector2.ZERO
var cart_heading := 0.0
var cart_fx := 0.0           ## 1 -> 0 after getting in or out of the cart
var _cart_slide := 0.0
var debug_view := false
var warm_up := false         ## true while a panel covers the street: redraw cached chunks faster
var perf := {"process": 0.0, "world": 0.0, "hud": 0.0}   ## smoothed microseconds per frame (dev telemetry)
var debug_scale := 0.0       ## dev tools: force the world zoom
var debug_focus := Vector2.INF   ## dev tools: look at a fixed world point
# Input state.
var dragging := false
var used := false
var anchor := Vector2.ZERO
var finger := Vector2.ZERO
var stick := Vector2.ZERO
var stick_hold := 0.0

var _pressing := false
var _press_pos := Vector2.ZERO
var _press_ms := 0
var _static_obstacles: Array = []
var _day_total := 1
var _day_done := 0
var _dusk_tween: Tween
var _objective_check := 0.0
var _cam_ready := false
var _step_clock := 0.0
var _audio_clock := 0.0
var _bird_clock := 4.0
var _bark_clock := 3.0


func _ready() -> void:
	clip_contents = true
	hood = Neighborhood.new()
	hood.build()
	player = PlayerController.new()
	player.position = _default_spawn()
	cart_pos = player.position + Vector2(-40.0, 30.0)
	ambient = Ambient.new()
	ambient.setup(hood, 1, 0, {})
	camera_ev = EvidenceCamera.new()
	for i in hood.lots.size():
		grass.append(3.0)
	static_root = Node2D.new()
	add_child(static_root)
	world_view = WorldView.new()
	add_child(world_view)
	world_view.setup(self, static_root)
	hud_view = HudView.new()
	add_child(hud_view)
	hud_view.setup(self)
	if OS.is_debug_build():
		var problems := hood.validate()
		if problems.is_empty():
			print("WORLD VALIDATION: %d lots, no layout problems." % hood.lots.size())
		else:
			print("WORLD VALIDATION: %d problem(s)" % problems.size())
			for line in problems:
				print("  ", line)
	GameState.stats_changed.connect(_sync_mood)
	_sync_mood()


func house_count() -> int:
	return hood.lots.size()


func lot_address(i: int) -> String:
	return hood.lots[i].address


func lot_kind(i: int) -> String:
	return hood.lots[i].kind


func house_color(i: int) -> Color:
	return world_view.styles()[i].roof


func _default_spawn() -> Vector2:
	var y := 6900.0
	return Vector2(hood.spine_x(y) - (Neighborhood.AVENUE_HALF + Neighborhood.WALK_W * 0.5), y)


## pins: lot id -> "lawn" | "card" | "done". `property_violations`: lot id -> allegation list.
func set_day(new_pins: Dictionary, new_grass: Array, completed := 0, saved_position = null,
		evidence: Dictionary = {}, property_violations: Dictionary = {}) -> void:
	pins = new_pins.duplicate()
	grass = new_grass.duplicate()
	while grass.size() < hood.lots.size():
		grass.append(3.0)
	violations = property_violations.duplicate(true)
	camera_ev.load_saved(evidence)
	_day_total = maxi(pins.size(), 1)
	_day_done = int(completed)
	walker_variant = (GameState.day - 1) % 4
	weather = (GameState.day - 1) % 3
	season = GameState.season()
	layouts.clear()
	_static_obstacles.clear()
	var blocked_driveways := {}
	for house in violations:
		var id := int(house)
		if id >= hood.lots.size():
			continue
		var entries := LotSlots.layout(hood.lots[id], violations[house])
		layouts[id] = entries
		for entry: Dictionary in entries:
			if (entry.half as Vector2) != Vector2.ZERO:
				_static_obstacles.append(entry)
			if entry.id in ["rv", "commercial_vehicle", "broken_vehicle", "hoop"]:
				blocked_driveways[id] = true
	ambient.setup(hood, GameState.day, GameState.weekday(), blocked_driveways, season)
	world_view.invalidate()
	if saved_position is Vector2 and hood.is_walkable(saved_position):
		player.position = saved_position
	else:
		player.position = _default_spawn()
		player.cart = false
		cart_pos = player.position + Vector2(-40.0, 30.0)
	player.velocity = Vector2.ZERO
	objective = -1
	_cam_ready = false
	_update_dusk()
	_pick_objective()


func get_player_position() -> Vector2:
	return player.position


func get_evidence() -> Dictionary:
	return camera_ev.evidence.duplicate(true)


func set_case_states(states: Dictionary) -> void:
	case_states = states.duplicate()


func set_hint(text: String) -> void:
	hint = text


## Lots with an obvious violation but no complaint filed: the inspector may spot them.
func set_discoverable(ids: Array) -> void:
	discoverable.clear()
	for id in ids:
		discoverable[int(id)] = true


func add_assignment(house: int, kind: String) -> void:
	pins[house] = kind
	_day_total += 1
	_pick_objective()


func mark_done(house: int) -> void:
	pins[house] = "done"
	say("INSPECTION COMPLETE · %s" % lot_address(house), 2.8)
	_day_done += 1
	_update_dusk()
	if objective == house:
		objective = -1
	_pick_objective()


func say(text: String, seconds := 2.2) -> void:
	bubble = text
	bubble_t = seconds


func set_objective(house: int) -> void:
	objective = house


func _pick_objective() -> void:
	if objective >= 0 and pins.get(objective, "") in ACTIVE_KINDS:
		return
	var best := INF
	objective = -1
	for house in pins:
		if pins[house] in ACTIVE_KINDS:
			var d := player.position.distance_to(hood.lots[int(house)].driveway_mid())
			if d < best:
				best = d
				objective = int(house)


func _update_dusk() -> void:
	if _dusk_tween:
		_dusk_tween.kill()
	_dusk_tween = create_tween()
	_dusk_tween.tween_property(self, "dusk", 0.85 * float(_day_done) / _day_total, 1.0)


func _sync_mood() -> void:
	var happy: float = float(GameState.stats.get("happiness", 50))
	var tw := create_tween()
	tw.tween_property(self, "gloom", clampf((35.0 - happy) / 35.0, 0.0, 1.0), 0.8)


# ---------------------------------------------------------------- input
# Movement, taps and holds are separate gestures. Only a quick, small tap can press
# a control or inspect; a drag only ever walks.

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_press_pos = event.position
			_press_ms = Time.get_ticks_msec()
			used = true
		else:
			var quick := Time.get_ticks_msec() - _press_ms <= TAP_MAX_MS
			var was_drag := dragging
			_pressing = false
			dragging = false
			stick = Vector2.ZERO
			if not was_drag and quick and event.position.distance_to(_press_pos) < TAP_SLOP:
				_tap(event.position)
	elif event is InputEventMouseMotion and _pressing:
		if hud_view.map_open:
			hud_view.handle_drag(event.relative)
			return
		if not dragging and event.position.distance_to(_press_pos) >= TAP_SLOP and not _overlay_open():
			dragging = true
			anchor = _press_pos
			finger = event.position
		if dragging:
			finger = event.position
			stick = (finger - anchor).limit_length(STICK_RANGE / Settings.sensitivity) / (STICK_RANGE / Settings.sensitivity)


func _overlay_open() -> bool:
	return hud_view.map_open or hud_view.gallery_open or camera_ev.active


func _tap(pos: Vector2) -> void:
	if hud_view.handle_tap(pos):
		return
	# Tapping the highlighted home itself also opens the case.
	if near >= 0 and pins.get(near, "") in ACTIVE_KINDS:
		var lot: LotScript = hood.lots[near]
		var scale := Vector2(world_scale, world_scale * WORLD_TILT)
		var center := Vector2(size.x * 0.5, size.y * 0.54)
		var screen: Vector2 = center + (lot.center - cam - center) * scale
		if screen.distance_to(pos) <= maxf(lot.house_size.y, lot.house_size.x) * 0.7 * world_scale:
			inspect_near()


func inspect_near() -> void:
	if near < 0:
		return
	if discoverable.has(near) and not pins.has(near):
		discover.emit(near)
		return
	var kind: String = pins.get(near, "")
	if kind == "lawn" or kind == "card":
		visit.emit(near)
	else:
		say("Inspection complete. Case on file." if kind == "done" else QUIPS[randi() % QUIPS.size()])


## The golf cart stays where you leave it. Walk back to it to drive again.
func toggle_cart() -> void:
	if player.cart:
		# Step out beside the cart and leave it parked.
		var side := Vector2.from_angle(player.angle + PI * 0.5) * 40.0
		var exit_pos := player.position + side
		if not hood.is_walkable(exit_pos):
			exit_pos = player.position - side
		player.cart = false
		cart_pos = player.position
		cart_heading = player.angle
		if hood.is_walkable(exit_pos):
			player.position = exit_pos
		cart_fx = 1.0
		photo_message = "CART PARKED HERE · on foot"
		Sfx.play("tap")
	else:
		var gap := player.position.distance_to(cart_pos)
		if gap <= 110.0:
			player.cart = true
			_cart_slide = 0.3
			cart_fx = 1.0
			photo_message = "GOLF CART · stays on the road"
			Sfx.play("good")
		else:
			photo_message = "Your cart is %d ft away" % roundi(gap * 0.75)
	photo_message_t = 2.0


func get_cart_state() -> Dictionary:
	return {"pos": cart_pos if not player.cart else player.position, "active": player.cart}


func set_cart_state(state: Dictionary) -> void:
	var pos = state.get("pos", null)
	if pos is Vector2 and hood.edge_distance(pos) <= Neighborhood.WALK_W * 0.8:
		cart_pos = pos
	if bool(state.get("active", false)) and player.position.distance_to(cart_pos) < 120.0:
		player.cart = true


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	time += delta
	# Child views always cover the street exactly, whatever layout pass ran last.
	for view: Control in [world_view, hud_view]:
		view.position = Vector2.ZERO
		view.size = size
	bubble_t = maxf(0.0, bubble_t - delta)
	photo_message_t = maxf(0.0, photo_message_t - delta)
	camera_flash = maxf(0.0, camera_flash - delta * 3.5)
	var move := stick
	if _overlay_open():
		move = Vector2.ZERO
	elif not dragging:
		move = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_action_just_pressed("ui_accept"):
			inspect_near()
	stick_hold = move_toward(stick_hold, 1.0 if dragging else 0.0, delta * 3.0)
	cart_fx = maxf(0.0, cart_fx - delta * 2.5)
	if _cart_slide > 0.0:
		_cart_slide -= delta
		player.position = player.position.lerp(cart_pos, 1.0 - exp(-16.0 * delta))
	ambient.update(delta, player.position)
	player.update(delta, move, hood, _nearby_obstacles(), ambient.circles())
	player.smooth_heading(delta)
	if player.moving and not player.cart:
		_step_clock += delta * player.speed_fraction()
		if _step_clock >= 0.3:
			_step_clock = 0.0
			Sfx.play("step")
	_follow_camera(delta)
	_update_audio(delta)
	near = _nearest_lot()
	_objective_check -= delta
	if _objective_check <= 0.0:
		_objective_check = 1.0
		_pick_objective()
	if camera_ev.active:
		frame_info = _evaluate_frame()
	_place_static_root()
	world_view.queue_redraw()
	hud_view.queue_redraw()
	perf.process = lerpf(float(perf.process), float(Time.get_ticks_usec() - started), 0.1)


## Ambience follows what is near the inspector: traffic, the cart, crews, sprinklers, birds and dogs.
func _update_audio(delta: float) -> void:
	_audio_clock -= delta
	_bird_clock -= delta
	_bark_clock -= delta
	if _audio_clock > 0.0 and _bird_clock > 0.0 and _bark_clock > 0.0:
		return
	var p := player.position
	if _audio_clock <= 0.0:
		_audio_clock = 0.25
		Sfx.set_loop("hum", player.speed_fraction() if player.cart else 0.0)
		var road := hood.edge_distance(p, -1, 0)
		Sfx.set_loop("traffic", clampf(1.0 - maxf(road, 0.0) / 260.0, 0.0, 1.0))
		var blower := 0.0
		if season == 2:
			for crew in ambient.crews:
				blower = maxf(blower, 1.0 - p.distance_to(ambient.crew_worker_position(crew)) / 450.0)
		Sfx.set_loop("blower", blower)
		var spray := 0.0
		if season == 1:
			for lot: LotScript in hood.lots:
				if lot.id % 4 == 0 and absf(lot.center.y - p.y) < 340.0:
					spray = maxf(spray, 1.0 - p.distance_to(lot.center) / 320.0)
		Sfx.set_loop("sprinkler", spray)
	if _bird_clock <= 0.0:
		_bird_clock = randf_range(3.0, 9.0)
		if season <= 1 and dusk < 0.5:
			Sfx.play("chirp")
	if _bark_clock <= 0.0:
		_bark_clock = randf_range(4.0, 8.0)
		for w in ambient.walkers:
			if bool(w.dog) and p.distance_to(ambient.walker_position(w)) < 220.0:
				Sfx.play("bark")
				break


## The camera is just a transform on the cached world; dusk is a tint on it.
func _place_static_root() -> void:
	var sc := Vector2(world_scale, world_scale * WORLD_TILT)
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	static_root.transform = Transform2D(0.0, sc, 0.0, center * (Vector2.ONE - sc) - cam * sc)
	static_root.modulate = Color.WHITE.lerp(Color(0.5, 0.48, 0.8), clampf(dusk * 0.75, 0.0, 0.7))


func _nearby_obstacles() -> Array:
	var result: Array = []
	for entry: Dictionary in _static_obstacles:
		if absf((entry.pos as Vector2).y - player.position.y) < 300.0:
			result.append(entry)
	for entry: Dictionary in ambient.obstacles():
		if absf((entry.pos as Vector2).y - player.position.y) < 300.0:
			result.append(entry)
	return result


func _follow_camera(delta: float) -> void:
	var target_scale := 0.9 if player.moving else 1.0
	if player.cart and player.moving:
		target_scale = 0.84
	target_scale -= 0.05 * cart_fx
	if debug_scale > 0.0:
		target_scale = debug_scale
	if Settings.reduce_motion:
		target_scale = 1.0
	if camera_ev.active:
		target_scale = camera_ev.zoom
	world_scale = lerpf(world_scale, target_scale, 1.0 - exp(-5.0 * delta))
	var look := Vector2.ZERO if Settings.reduce_motion else (player.velocity * 0.22).limit_length(70.0)
	var focus := player.position + look
	var target := Vector2(focus.x - size.x * 0.5, focus.y - size.y * 0.58)
	if debug_focus != Vector2.INF:
		target = debug_focus - size * 0.5
	if camera_ev.active and near >= 0:
		# Photographing: center the property in the viewfinder.
		var frame := camera_ev.frame_rect(size)
		target = hood.lots[near].center - Vector2(size.x * 0.5, frame.get_center().y)
	if debug_focus == Vector2.INF:
		target.x = clampf(target.x, 0.0, maxf(0.0, Neighborhood.WORLD_W - size.x))
		target.y = clampf(target.y, 0.0, maxf(0.0, Neighborhood.WORLD_H - size.y))
	if _cam_ready:
		cam = cam.lerp(target, 1.0 - exp(-7.0 * delta))
	else:
		cam = target
		_cam_ready = true


## The property closest to where the inspector actually stands (the driveway), with
## open complaints preferred so a neighbor never steals the prompt.
func _nearest_lot() -> int:
	var best_score := NEAR_DIST
	var found := -1
	for lot: LotScript in hood.lots:
		if absf(lot.center.y - player.position.y) > NEAR_DIST + 120.0:
			continue
		var d := player.position.distance_to(lot.driveway_mid())
		var active: bool = pins.get(lot.id, "") in ACTIVE_KINDS
		var score := d - (DRIVEWAY_BIAS if active else 0.0)
		if d < NEAR_DIST and score < best_score:
			best_score = score
			found = lot.id
	return found


# ---------------------------------------------------------------- camera

func to_screen(world: Vector2) -> Vector2:
	var scale := Vector2(world_scale, world_scale * WORLD_TILT)
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	return center + (world - cam - center) * scale


func open_camera() -> void:
	if near >= 0 and pins.get(near, "") in ACTIVE_KINDS:
		camera_ev.active = true
		camera_ev.zoom = 1.4
		photo_message = "FRAME THE PROPERTY"
	else:
		photo_message = "MOVE CLOSER TO INSPECT"
	photo_message_t = 2.0


func _evaluate_frame() -> Dictionary:
	if near < 0:
		return {"quality": 0, "documented": [], "potential": false}
	var lot: LotScript = hood.lots[near]
	return camera_ev.evaluate(lot, player.position, to_screen, size, dusk, layouts.get(near, []), _obstructors(lot))


func _obstructors(lot: LotScript) -> Array:
	var result: Array = []
	for tree in lot.trees:
		result.append(tree)
	for tree in hood.street_trees:
		if lot.center.distance_to(Vector2(tree.x, tree.y)) < 140.0:
			result.append(tree)
	return result


func take_photo() -> void:
	var info := _evaluate_frame()
	if near < 0:
		photo_message = "NO PROPERTY IN RANGE"
		photo_message_t = 2.0
		return
	var house := near
	var quality: int = info.quality
	var key := camera_ev.shot_key(player.position)
	if camera_ev.is_duplicate(house, key):
		photo_message = "DUPLICATE · MOVE OR ZOOM"
		photo_message_t = 2.2
		return
	if quality < EvidenceCamera.USABLE_QUALITY:
		photo_message = "UNUSABLE %d%% · CLOSER / RECENTER" % quality
		photo_message_t = 2.4
		photo_taken.emit(house, quality, false, [])
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://evidence-lot-%03d-%s.png" % [house, stamp]
	# Hide the HUD for a frame so the saved photo is just the framed scene.
	var image: Image
	if DisplayServer.get_name() == "headless":
		# No renderer under the headless test runner: store a placeholder frame.
		image = Image.create(64, 48, false, Image.FORMAT_RGB8)
	else:
		capturing = true
		hud_view.visible = false
		await RenderingServer.frame_post_draw
		image = get_viewport().get_texture().get_image()
		capturing = false
		hud_view.visible = true
	var vp := get_viewport_rect().size
	var ratio := float(image.get_width()) / maxf(vp.x, 1.0)
	var frame := camera_ev.frame_rect(size)
	var origin := frame.position + global_position
	var region := Rect2i(int(origin.x * ratio), int(origin.y * ratio), int(frame.size.x * ratio), int(frame.size.y * ratio))
	region = region.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if region.has_area():
		image = image.get_region(region)
	var error := image.save_png(path)
	camera_ev.active = false
	if error != OK:
		photo_message = "CAMERA ERROR"
		photo_message_t = 2.2
		return
	var result := camera_ev.add_photo(house, lot_address(house), str(pins.get(house, "inspection")),
			{"path": path, "time": stamp, "day": GameState.day, "quality": quality, "documented": info.documented, "key": key})
	var recorded: Array = []
	for id in result.newly:
		recorded.append(_label_for(house, str(id)))
	if not recorded.is_empty():
		photo_message = "EVIDENCE RECORDED · %s" % ", ".join(recorded)
	else:
		photo_message = "PHOTO SAVED · %d%%" % quality
	photo_message_t = 2.6
	camera_flash = 1.0
	photo_taken.emit(house, quality, true, result.newly)
	evidence_changed.emit()


func _label_for(house: int, id: String) -> String:
	for v in violations.get(house, []):
		if str(v.get("id", "")) == id:
			return str(v.get("label", id))
	return id
