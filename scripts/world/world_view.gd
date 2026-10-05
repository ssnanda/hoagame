extends Control
## Dynamic layer: markers, people, moving vehicles, weather and overlays. The static world
## (ground, roads, lots, houses, trees) lives in cached chunks under `static_root`; see
## static_painter.gd and world_chunk.gd. That is what keeps the frame cost low.

const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotScript := preload("res://scripts/world/lot.gd")
const DrawUtil := preload("res://scripts/world/draw_util.gd")
const ActorPainter := preload("res://scripts/world/actor_painter.gd")
const StaticPainter := preload("res://scripts/world/static_painter.gd")
const WorldChunk := preload("res://scripts/world/world_chunk.gd")

const TILT := 0.84
const WALKER_K := 1.4
const CHUNK_MARGIN := 700.0
const MAX_REDRAWS_PER_FRAME := 4

var ctx                                  ## street controller
var painter: StaticPainter
var static_root: Node2D
var _chunks: Array = []                  ## {node, rect, stale}
var _base := Transform2D.IDENTITY
var _cam := Vector2.ZERO
var _view := Rect2()
var _lots: Array = []                    ## lots near the camera this frame


func setup(controller, root: Node2D) -> void:
	ctx = controller
	static_root = root
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	painter = StaticPainter.new()
	painter.setup(ctx)
	_build_chunks()


func styles() -> Array:
	return painter.styles


## Marks every chunk for redraw (new day, new season, changed lawns or violations).
func invalidate() -> void:
	for chunk in _chunks:
		chunk.stale = true


func _add_chunk(kind: String, arg, rect: Rect2) -> void:
	var node := WorldChunk.new()
	node.painter = painter
	node.kind = kind
	node.arg = arg
	static_root.add_child(node)
	_chunks.append({"node": node, "rect": rect, "stale": true})


func _build_chunks() -> void:
	var hood: Neighborhood = ctx.hood
	_add_chunk("ground", 0, Rect2(-200, -200, Neighborhood.WORLD_W + 400.0, Neighborhood.WORLD_H + 400.0))
	for i in hood.landmarks.size():
		_add_chunk("landmark", i, (hood.landmarks[i].rect as Rect2).grow(40.0))
	for pass_i in 3:
		_add_chunk("roads", pass_i, Rect2(-200, -200, Neighborhood.WORLD_W + 400.0, Neighborhood.WORLD_H + 400.0))
	for b in painter.furniture_bucket_count():
		_add_chunk("furniture", b, Rect2(0, b * StaticPainter.FURNITURE_BUCKET, Neighborhood.WORLD_W, StaticPainter.FURNITURE_BUCKET).grow(80.0))
	for lot: LotScript in hood.lots:
		var minp := Vector2(INF, INF)
		var maxp := Vector2(-INF, -INF)
		for p in lot.polygon:
			minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
			maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
		_add_chunk("lot", lot.id, Rect2(minp, maxp - minp).grow(130.0))
	for b in painter.furniture_bucket_count():
		_add_chunk("trees", b, Rect2(0, b * StaticPainter.FURNITURE_BUCKET, Neighborhood.WORLD_W, StaticPainter.FURNITURE_BUCKET).grow(80.0))


## Redraws stale chunks near the camera, nearest first and only a few per frame, so a
## new day never causes a hitch. Backdrop chunks (ground, roads) go first.
func _refresh_chunks(view: Rect2) -> void:
	var near := view.grow(CHUNK_MARGIN)
	var center := view.get_center()
	var due: Array = []
	for chunk in _chunks:
		if chunk.stale and near.intersects(chunk.rect):
			var kind: String = chunk.node.kind
			var priority := 0.0 if kind in ["ground", "roads", "landmark"] else center.distance_to((chunk.rect as Rect2).get_center())
			due.append([priority, chunk])
	if due.is_empty():
		return
	due.sort_custom(func(a, b): return a[0] < b[0])
	# One chunk a frame while playing keeps frames short; more while a panel hides the street.
	var budget := MAX_REDRAWS_PER_FRAME if ctx.warm_up else (2 if get_process_delta_time() < 0.011 else 1)
	for i in mini(due.size(), budget):
		var chunk: Dictionary = due[i][1]
		chunk.stale = false
		(chunk.node as Node2D).queue_redraw()


func _draw() -> void:
	if ctx == null:
		return
	var started := Time.get_ticks_usec()
	_draw_world()
	ctx.perf.world = lerpf(float(ctx.perf.world), float(Time.get_ticks_usec() - started), 0.1)


func _draw_world() -> void:
	var hood: Neighborhood = ctx.hood
	_cam = ctx.cam
	var ws: float = ctx.world_scale
	var sc := Vector2(ws, ws * TILT)
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	_base = Transform2D(0.0, sc, 0.0, center * (Vector2.ONE - sc))
	draw_set_transform_matrix(_base)
	var u0 := center - center / sc
	var u1 := (size - center) / sc + center
	_view = Rect2(_cam + u0, u1 - u0).grow(380.0)
	_refresh_chunks(Rect2(_cam + u0, u1 - u0))
	_lots.clear()
	for lot: LotScript in hood.lots:
		if _view.has_point(lot.center):
			_lots.append(lot)
	_road_vehicles()
	_animated_props()
	if not ctx.capturing:
		for lot: LotScript in _lots:
			_markers(lot)
	_actors()
	if ctx.debug_view:
		_debug_layer(hood)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_weather()
	if float(ctx.dusk) > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.1, 0.32, 0.3 * float(ctx.dusk)))
	if float(ctx.gloom) > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.27, 0.32, 0.4 * float(ctx.gloom)))


## Moving traffic and work trucks. Parked cars are part of each lot's cached chunk.
func _road_vehicles() -> void:
	var dusk := float(ctx.dusk)
	for v in ctx.ambient.traffic:
		var pose: Dictionary = ctx.ambient.traffic_pose(v)
		var pos: Vector2 = pose.pos
		if not _view.has_point(pos):
			continue
		ActorPainter.place(self, _base, pos - _cam, (pose.heading as Vector2).angle() + PI * 0.5, 0.78 if v.kind == "car" else 0.85)
		if v.kind == "car":
			ActorPainter.car(self, v.color, dusk)
		else:
			ActorPainter.truck(self, str(v.kind))
		draw_set_transform_matrix(_base)
	for crew in ctx.ambient.crews:
		var pose: Dictionary = ctx.ambient.crew_truck_pose(crew)
		var pos: Vector2 = pose.pos
		if not _view.has_point(pos):
			continue
		ActorPainter.place(self, _base, pos - _cam, (pose.heading as Vector2).angle() + PI * 0.5, 0.82)
		ActorPainter.truck(self, "delivery")
		DrawUtil.rr(self, Rect2(-16, 62, 32, 40), Color("52616f"), 3)
		draw_set_transform_matrix(_base)


## The few things on lots that animate: summer sprinkler spray.
func _animated_props() -> void:
	if int(ctx.season) != 1:
		return
	var time := float(ctx.time)
	for lot: LotScript in _lots:
		if lot.id % 4 != 0:
			continue
		var ds := signf((lot.driveway_end - lot.center).dot(lot.right()))
		var base := lot.local_point(lot.house_size.x * 0.5 + 34.0, -ds * lot.house_size.y * 0.3) - _cam
		for k in 6:
			var a := time * 3.0 + k * TAU / 6.0
			var r := 14.0 + 12.0 * fposmod(time * 1.4 + k * 0.17, 1.0)
			draw_circle(base + Vector2.from_angle(a) * r, 1.8, Color(0.75, 0.9, 1.0, 0.8))
		draw_arc(base, 24.0, 0.0, TAU, 20, Color(0.7, 0.9, 1.0, 0.18), 6.0)


# ---------------------------------------------------------------- markers

func _markers(lot: LotScript) -> void:
	var pins: Dictionary = ctx.pins
	var kind: String = pins.get(lot.id, "")
	var c := lot.center - _cam
	var time := float(ctx.time)
	var near: bool = lot.id == int(ctx.near)
	var active := kind == "lawn" or kind == "card" or kind == "reinspect"
	var status: String = ctx.case_states.get(lot.id, "")
	if ctx.camera_ev.evidence.has(lot.id):
		draw_circle(lot.mailbox - _cam + Vector2(14, -22), 4.0, Color("71b9dc"))
	if near:
		var pulse := 0.5 + 0.5 * sin(time * 6.0)
		var outline := PackedVector2Array()
		for p in lot.footprint(10.0 + pulse * 4.0):
			outline.append(p - _cam)
		var col := Color("ffd36e") if active else Color(1, 1, 1, 0.8)
		draw_colored_polygon(outline, Color(col, 0.12 + 0.08 * pulse))
		draw_polyline(outline + PackedVector2Array([outline[0]]), Color(col, 0.95), 4.0)
	if active:
		var pin := c + Vector2(0, -26.0 + sin(time * 3.0 + lot.id) * 4.0)
		var col2 := Color("3fae6a") if kind == "lawn" else (Color("f2994a") if kind == "reinspect" else Color("e0533d"))
		DrawUtil.ellipse(self, pin, 30.0 + sin(time * 4.0) * 3.0, 30.0 + sin(time * 4.0) * 3.0, Color(col2, 0.22))
		DrawUtil.ellipse(self, pin + Vector2(4, 6), 18.0, 18.0, Color(0, 0, 0, 0.2))
		DrawUtil.ellipse(self, pin, 18.0, 18.0, col2)
		draw_string(ThemeDB.fallback_font, pin + Vector2(-18, 8), "!", HORIZONTAL_ALIGNMENT_CENTER, 36.0, 26, Color.WHITE)
		if near:
			var tag := Rect2(pin + Vector2(-60, -52), Vector2(120, 28))
			DrawUtil.rr(self, tag, Color("e0533d"), 8)
			draw_string(ThemeDB.fallback_font, tag.position + Vector2(0, 20), "REINSPECT" if kind == "reinspect" else "COMPLAINT", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 16, Color.WHITE)
	elif kind == "done" or status != "":
		var tint: Color = {"warning": Color("f2c94c"), "hearing": Color("f2994a"), "fined": Color("eb5757"),
				"compliant": Color("6fcf97"), "disputed": Color("9b8cf0"), "reinspect": Color("f2c94c")}.get(status, Color("9aa4b2"))
		var pin := c + Vector2(0, -22.0)
		DrawUtil.ellipse(self, pin, 12.0, 12.0, tint)
		draw_polyline(PackedVector2Array([pin + Vector2(-5, 0), pin + Vector2(-1, 4), pin + Vector2(6, -4)]), Color.WHITE, 2.5, true)


# ---------------------------------------------------------------- actors

func _actors() -> void:
	var amb = ctx.ambient
	var time := float(ctx.time)
	for w in amb.walkers:
		var p: Vector2 = amb.walker_position(w)
		if not _view.has_point(p):
			continue
		var sp := p - _cam
		ActorPainter.place(self, _base, sp, 0.0, 1.0)
		ActorPainter.person(self, int(w.tone), time, float(w.speed))
		draw_set_transform_matrix(_base)
		if bool(w.dog):
			var dog_p := sp + Vector2(25.0 * float(w.side), 24.0)
			draw_line(sp + Vector2(7.0 * float(w.side), 3.0), dog_p + Vector2(0.0, -5.0), Color("7b5a3b"), 2.0)
			ActorPainter.place(self, _base, dog_p, 0.0, 1.0)
			ActorPainter.dog(self, int(w.tone))
			draw_set_transform_matrix(_base)
	for k in amb.kids:
		var p: Vector2 = amb.kid_position(k)
		if not _view.has_point(p):
			continue
		ActorPainter.place(self, _base, p - _cam, 0.0, 0.65)
		ActorPainter.person(self, int(k.tone), time, 30.0)
		draw_set_transform_matrix(_base)
		var ball_a := float(k.phase) + time * float(k.speed) * 1.4 + 2.0
		var bp: Vector2 = (k.c as Vector2) + Vector2.from_angle(ball_a) * (float(k.r) + 16.0) - _cam
		bp.y -= absf(sin(time * 5.0 + float(k.phase))) * 9.0
		draw_circle(bp, 5.0, [Color("ff6b5a"), Color("ffd36e"), Color("71b9dc"), Color.WHITE][int(k.tone) % 4])
	for crew in amb.crews:
		var p: Vector2 = amb.crew_worker_position(crew)
		if not _view.has_point(p):
			continue
		var sp := p - _cam
		match str(crew.get("kind", "mower")):
			"blower":
				draw_line(sp + Vector2(8, -6), sp + Vector2(30, -20), Color("2b2e36"), 4.0, true)
				for j in 5:
					var t := fposmod(time * 1.6 + j * 0.2, 1.0)
					draw_circle(sp + Vector2(30, -20) + Vector2(14 + t * 34.0, -6 + sin(j * 2.0 + time * 4.0) * 8.0), 2.4,
							[Color("d9822b"), Color("b5482a"), Color("e0b03a")][j % 3])
			"shovel":
				draw_line(sp + Vector2(6, -6), sp + Vector2(22, -22), Color("8a6747"), 3.0, true)
				DrawUtil.rr(self, Rect2(sp + Vector2(18, -28), Vector2(14, 9)), Color("52616f"), 2)
			_:
				DrawUtil.rr(self, Rect2(sp + Vector2(-9, -34), Vector2(18, 14)), Color("e07a1f"), 3)
		ActorPainter.place(self, _base, sp, 0.0, 1.0)
		ActorPainter.person(self, int(crew.lot) % 4, time, 30.0)
		draw_set_transform_matrix(_base)
	_player()


func _player() -> void:
	if not ctx.player.cart:
		var parked: Vector2 = ctx.cart_pos
		if _view.has_point(parked):
			ActorPainter.place(self, _base, parked - _cam, float(ctx.cart_heading), 1.0)
			ActorPainter.golf_cart(self)
			draw_set_transform_matrix(_base)
	if ctx.capturing:
		return
	var player = ctx.player
	var pos: Vector2 = player.position - _cam
	var moving: bool = player.moving
	var phase: float = player.phase
	var time := float(ctx.time)
	var angle: float = player.angle
	if player.cart:
		ActorPainter.place(self, _base, pos, angle, 1.0)
		ActorPainter.golf_cart(self)
		draw_set_transform_matrix(_base)
	var swing := sin(phase) if moving else 0.0
	var bob := absf(cos(phase)) * -3.5 if moving else sin(time * 2.0) * 0.8
	var k := WALKER_K * (1.0 + 0.03 * absf(sin(phase))) if moving else WALKER_K * (1.0 + 0.012 * sin(time * 2.0))
	if float(ctx.cart_fx) > 0.0:
		var fx: float = ctx.cart_fx
		draw_arc(pos, 30.0 + (1.0 - fx) * 46.0, 0.0, TAU, 28, Color(1, 1, 1, 0.55 * fx), 3.0)
		k *= 1.0 + 0.12 * sin(fx * PI)
	ActorPainter.place(self, _base, pos + Vector2(8, 10), angle, k * 1.2)
	DrawUtil.ellipse(self, Vector2.ZERO, 20.0, 15.0, Color(0, 0, 0, 0.25))
	ActorPainter.place(self, _base, pos + Vector2(0, bob), angle, k)
	ActorPainter.inspector(self, int(ctx.walker_variant), swing)
	draw_set_transform_matrix(_base)
	if float(ctx.bubble_t) > 0.0:
		var font := ThemeDB.fallback_font
		var text: String = ctx.bubble
		var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var box := Rect2(pos.x - tsize.x * 0.5 - 16.0, pos.y - 100.0, tsize.x + 32.0, 52.0)
		box.position.x = clampf(box.position.x, 8.0, size.x - box.size.x - 8.0)
		DrawUtil.rr(self, box, Color.WHITE, 14)
		draw_string(font, box.position + Vector2(16.0, 36.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("1c1b1f"))


# ---------------------------------------------------------------- weather

func _weather() -> void:
	var w := size.x
	var h := size.y
	var time := float(ctx.time)
	var weather: int = ctx.weather
	var season: int = ctx.season
	if season == 0 and weather == 1:
		for i in 60:
			var x := fposmod(i * 71.0 + time * 40.0, w + 40.0) - 20.0
			var y := fposmod(i * 137.0 + time * 520.0, h + 60.0) - 30.0
			draw_line(Vector2(x, y), Vector2(x - 6.0, y + 16.0), Color(0.75, 0.85, 1.0, 0.5), 1.5)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.42, 0.55, 0.12))
	elif weather == 0:
		for i in 7:
			var cx := fposmod(i * 211.0 + time * (6.0 + i), w + 260.0) - 130.0
			var cy := 60.0 + (i * 97) % 260 - fposmod(_cam.y * 0.08, h + 200.0)
			DrawUtil.ellipse(self, Vector2(cx, cy), 38.0, 15.0, Color(1, 1, 1, 0.12))
			DrawUtil.ellipse(self, Vector2(cx + 28.0, cy + 3.0), 28.0, 12.0, Color(1, 1, 1, 0.1))
	elif weather == 1:
		for i in 9:
			var x := fposmod(i * 97.0 + time * (18.0 + i), w + 40.0) - 20.0
			var y := fposmod(i * 143.0 + time * 28.0, h + 60.0) - 30.0
			draw_circle(Vector2(x, y), 3.0 + float(i % 3), Color("ffd36e", 0.35))
	if season == 3:
		for i in 28:
			var x := fposmod(i * 61.0 + sin(time + i) * 14.0, w)
			var y := fposmod(i * 97.0 + time * (30.0 + i % 5 * 6.0), h + 20.0) - 10.0
			draw_circle(Vector2(x, y), 2.0 + i % 3, Color(1, 1, 1, 0.8))
	elif season == 2:
		for i in 12:
			var x := fposmod(i * 83.0 + time * 24.0, w + 40.0) - 20.0
			var y := fposmod(i * 131.0 + time * 36.0, h + 40.0) - 20.0
			draw_circle(Vector2(x, y), 4.0, [Color("d9822b"), Color("b5482a"), Color("e0b03a")][i % 3])


## Developer layer (menu > DEBUG VIEW in debug builds): lot polygons, footprints,
## driveways, inspection radius, violation slots and property ids.
func _debug_layer(hood: Neighborhood) -> void:
	var font := ThemeDB.fallback_font
	for street in hood.streets:
		var pts := PackedVector2Array()
		for p in street.path:
			pts.append(p - _cam)
		draw_polyline(pts, Color(1, 1, 1, 0.5), 1.5)
	for lot: LotScript in _lots:
		var poly := PackedVector2Array()
		for p in lot.polygon:
			poly.append(p - _cam)
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color("00e5ff"), 1.5)
		var fp := PackedVector2Array()
		for p in lot.footprint():
			fp.append(p - _cam)
		draw_polyline(fp + PackedVector2Array([fp[0]]), Color("ff3df2"), 2.0)
		draw_line(lot.curb - _cam, lot.driveway_end - _cam, Color("ffee00"), 2.0)
		draw_circle(lot.curb - _cam, 4.0, Color("ffee00"))
		draw_circle(lot.mailbox - _cam, 4.0, Color("ff9100"))
		draw_arc(lot.driveway_mid() - _cam, 135.0, 0.0, TAU, 48, Color(0, 1, 0.4, 0.25), 1.0)
		draw_string(font, lot.center - _cam + Vector2(-20, 5), "#%d" % lot.id, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 16, Color.WHITE)
		for entry: Dictionary in ctx.layouts.get(lot.id, []):
			draw_circle((entry.pos as Vector2) - _cam, 6.0, Color("ff9100"), false, 2.0)
	for entry: Dictionary in ctx.ambient.obstacles():
		if _view.has_point(entry.pos):
			var half: Vector2 = entry.half
			var ax := Vector2.from_angle(float(entry.rot)) * half.x
			var ay := Vector2.from_angle(float(entry.rot) + PI * 0.5) * half.y
			var c: Vector2 = (entry.pos as Vector2) - _cam
			draw_polyline(PackedVector2Array([c + ax + ay, c + ax - ay, c - ax - ay, c - ax + ay, c + ax + ay]), Color("ff1744"), 1.5)
