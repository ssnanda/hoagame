extends Control
## Draws the neighborhood from the street controller's state. It reads geometry
## from Neighborhood and makes no gameplay decisions.

const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotScript := preload("res://scripts/world/lot.gd")
const DrawUtil := preload("res://scripts/world/draw_util.gd")
const ActorPainter := preload("res://scripts/world/actor_painter.gd")
const ObjectPainter := preload("res://scripts/world/object_painter.gd")
const HousePainter := preload("res://scripts/world/house_painter.gd")

const TILT := 0.84
const SEASON_LAWN := [Color("58c27d"), Color("66b858"), Color("b2a64f"), Color("d6e2e8")]
const SEASON_LEAF := [Color("48b86a"), Color("2f9e57"), Color("d9822b"), Color("e8eef2")]
const WALK_COL := Color("d9dde3")
const ROAD_COL := Color("3a4152")
const CURB_COL := Color("9aa0aa")
const WALKER_K := 1.4
const INCH_PX := 4.5
const MOUNTAIN_Y := 380.0

var ctx                                  ## street controller
var _styles: Array = []
var _tufts: Dictionary = {}
var _furniture: Array = []               ## {type, pos, rot}
var _base := Transform2D.IDENTITY
var _cam := Vector2.ZERO
var _view := Rect2()
var _lots: Array = []                    ## lots near the camera this frame


func setup(controller) -> void:
	ctx = controller
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var hood: Neighborhood = ctx.hood
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for lot: LotScript in hood.lots:
		_styles.append(HousePainter.make_style(lot))
		var tufts: Array = []
		var minp := Vector2(INF, INF)
		var maxp := Vector2(-INF, -INF)
		for p in lot.polygon:
			minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
			maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
		for _i in 70:
			var p := Vector2(rng.randf_range(minp.x, maxp.x), rng.randf_range(minp.y, maxp.y))
			if tufts.size() < 30 and Geometry2D.is_point_in_polygon(p, lot.polygon) and Geometry2D.get_closest_point_to_segment(p, lot.curb, lot.driveway_end).distance_to(p) > lot.driveway_width * 0.5 + 6.0 \
					and not Geometry2D.is_point_in_polygon(p, lot.footprint(4.0)):
				tufts.append({"p": p, "h": rng.randf_range(0.6, 1.0), "a": rng.randf_range(-0.3, 0.3)})
		_tufts[lot.id] = tufts
	_build_furniture(hood)


## Hydrants, drainage grates, streetlights and signs, placed once.
func _build_furniture(hood: Neighborhood) -> void:
	_furniture.clear()
	for street in hood.streets:
		for side in [-1, 1]:
			var s := 90.0
			var light_every := 250.0 if street.kind == "avenue" else 330.0
			var next_light := s
			var next_hydrant := 160.0 + float((street.id * 53) % 120)
			var next_grate := 120.0
			while s < street.length - 40.0:
				var smp: Array = hood.sample(street, s)
				var t: Vector2 = smp[1]
				var n := Vector2(-t.y, t.x) * float(side)
				var edge: float = street.half + Neighborhood.WALK_W
				if s >= next_light:
					_try_furniture(hood, "light", smp[0] + n * (edge - 6.0), t.angle())
					next_light += light_every
				if s >= next_hydrant:
					_try_furniture(hood, "hydrant", smp[0] + n * (edge + 4.0), t.angle())
					next_hydrant += 520.0
				if s >= next_grate:
					_try_furniture(hood, "grate", smp[0] + n * (street.half - 6.0), t.angle())
					next_grate += 340.0
				s += 20.0
	# Signs and crosswalks where each side street meets the avenue.
	for street in hood.streets:
		if street.id == 0:
			continue
		var start: Vector2 = street.path[0]
		var dir: Vector2 = (street.path[1] - street.path[0]).normalized()
		var n := Vector2(-dir.y, dir.x)
		var mouth: float = Neighborhood.AVENUE_HALF + Neighborhood.WALK_W + 12.0
		_furniture.append({"type": "crosswalk", "pos": start + dir * mouth, "rot": dir.angle(), "half": street.half})
		_furniture.append({"type": "stop", "pos": start + dir * (mouth + 26.0) + n * (street.half + Neighborhood.WALK_W - 4.0), "rot": dir.angle()})
		_furniture.append({"type": "name", "pos": start + dir * (mouth + 26.0) - n * (street.half + Neighborhood.WALK_W - 4.0), "rot": dir.angle()})


func _try_furniture(hood: Neighborhood, type: String, pos: Vector2, rot: float) -> void:
	if hood.driveway_at(pos) >= 0 or not hood.landmark_at(pos).is_empty():
		return
	for lot: LotScript in hood.lots:
		if absf(lot.curb.y - pos.y) < 70.0 and (lot.curb.distance_to(pos) < 52.0 or lot.mailbox.distance_to(pos) < 30.0):
			return
	for item in _furniture:
		if item.type == type and (item.pos as Vector2).distance_to(pos) < 90.0:
			return
	_furniture.append({"type": type, "pos": pos, "rot": rot})


func _draw() -> void:
	if ctx == null:
		return
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
	_lots.clear()
	for lot: LotScript in hood.lots:
		if _view.has_point(lot.center):
			_lots.append(lot)
	_ground(u0, u1)
	_landmarks(hood)
	_roads(hood)
	_furniture_pass()
	for lot: LotScript in _lots:
		_yard(lot)
	_road_vehicles()
	var shadow := Vector2(18.0, 22.0) * (1.0 + float(ctx.dusk) * 1.2)
	_tree_shadows(hood, shadow)
	for lot: LotScript in _lots:
		var near: bool = lot.id == int(ctx.near)
		HousePainter.draw(self, _base, lot, _styles[lot.id], lot.center - _cam, 1.12 if near else 1.0,
				float(ctx.dusk), float(ctx.time), ctx.layouts.get(lot.id, []))
	_trees(hood)
	if not ctx.capturing:
		for lot: LotScript in _lots:
			_markers(lot)
	_actors()
	if ctx.debug_view:
		_debug_layer(hood)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_weather()
	if float(ctx.dusk) > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.1, 0.32, 0.4 * float(ctx.dusk)))
	if float(ctx.gloom) > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.25, 0.27, 0.32, 0.4 * float(ctx.gloom)))


# ---------------------------------------------------------------- ground

func _lawn_color() -> Color:
	var lawn: Color = (SEASON_LAWN[int(ctx.season)] as Color).lerp(Color("2c7050"), float(ctx.dusk) * 0.7)
	return lawn


func _ground(u0: Vector2, u1: Vector2) -> void:
	draw_rect(Rect2(u0 - Vector2(60, 60), u1 - u0 + Vector2(120, 120)), _lawn_color())
	var k := int(floor(_cam.y / 160.0)) - 1
	while k * 160.0 - _cam.y < u1.y:
		if k % 2 == 0:
			draw_rect(Rect2(u0.x - 60.0, k * 160.0 - _cam.y, u1.x - u0.x + 120.0, 160.0), Color(1, 1, 1, 0.045))
		k += 1
	if _cam.y + u0.y < MOUNTAIN_Y + 260.0:
		var dusk := float(ctx.dusk)
		var back := Color("75869b").lerp(Color("343a57"), dusk * 0.65)
		var front := Color("536b64").lerp(Color("27394a"), dusk * 0.65)
		var base_y := MOUNTAIN_Y - _cam.y
		for i in 8:
			var bx := -80.0 + i * 330.0 - _cam.x
			var peak := Vector2(bx + 85.0, base_y - 145.0 - (i % 3) * 32.0)
			draw_colored_polygon(PackedVector2Array([Vector2(bx, base_y + 70.0), peak, Vector2(bx + 190.0, base_y + 70.0)]), back)
			draw_colored_polygon(PackedVector2Array([peak, peak + Vector2(-31, 52), peak + Vector2(4, 39), peak + Vector2(34, 58)]), Color("e8eef2", 0.9))
		for i in 7:
			var bx := -30.0 + i * 390.0 - _cam.x
			draw_colored_polygon(PackedVector2Array([Vector2(bx, base_y + 95.0), Vector2(bx + 95.0, base_y - 70.0), Vector2(bx + 210.0, base_y + 95.0)]), front)


func _landmarks(hood: Neighborhood) -> void:
	var dusk := float(ctx.dusk)
	for mark in hood.landmarks:
		var r: Rect2 = mark.rect
		if not _view.intersects(r):
			continue
		var rs := Rect2(r.position - _cam, r.size)
		match str(mark.type):
			"park":
				DrawUtil.rr(self, rs, Color("7fcf86").lerp(Color("2f6b4c"), dusk * 0.6), 18)
				DrawUtil.ellipse(self, rs.get_center(), rs.size.x * 0.32, rs.size.y * 0.3, Color("d8d1b8", 0.7))
				_playground(rs.get_center() + Vector2(-70, 0))
				for b in 3:
					DrawUtil.rr(self, Rect2(rs.get_center() + Vector2(60 + b * 52, -40 + b * 30), Vector2(28, 10)), Color("8a6747"), 2)
			"woods":
				DrawUtil.rr(self, rs, Color("2f7a4a").lerp(Color("1c4a35"), dusk * 0.6), 24)
			"pond", "lake":
				var c := rs.get_center()
				var half := rs.size * 0.5
				DrawUtil.ellipse(self, c, half.x + 14.0, half.y + 14.0, Color("b8d7b2").lerp(Color("314f55"), dusk * 0.6))
				DrawUtil.ellipse(self, c, half.x, half.y, Color("4aa9c7").lerp(Color("25465d"), dusk * 0.65))
				for i in 6:
					draw_arc(c + Vector2(sin(i * 1.7) * half.x * 0.3, -half.y * 0.6 + i * half.y * 0.22), 22.0 + i * 3.0,
							0.15, PI - 0.15, 16, Color(0.8, 0.95, 1.0, 0.35), 2.0)
				if str(mark.type) == "lake":
					draw_rect(Rect2(c + Vector2(-half.x - 6.0, -18.0), Vector2(120, 36)), Color("8a6747"))
					for x in range(int(c.x - half.x), int(c.x - half.x + 110), 18):
						draw_line(Vector2(x, c.y - 16.0), Vector2(x, c.y + 16.0), Color("b38a60"), 2.0)
			"clubhouse":
				_clubhouse(rs, dusk)


func _playground(p: Vector2) -> void:
	DrawUtil.rr(self, Rect2(p + Vector2(-40, -30), Vector2(80, 60)), Color("c9b98c"), 8)
	draw_line(p + Vector2(-30, -20), p + Vector2(-30, 20), Color("d94b45"), 4.0)
	draw_line(p + Vector2(-10, -20), p + Vector2(-10, 20), Color("d94b45"), 4.0)
	for k in 2:
		draw_line(p + Vector2(-30 + k * 20, -20), p + Vector2(-30 + k * 20, 0), Color("52616f"), 2.0)
	DrawUtil.rr(self, Rect2(p + Vector2(8, -22), Vector2(26, 44)), Color("f2b632"), 5)
	DrawUtil.rr(self, Rect2(p + Vector2(10, -6), Vector2(22, 14)), Color("e07a1f"), 4)


## Management office with the pool. The Wozig sign is part of the scenery, not an ad banner.
func _clubhouse(rs: Rect2, dusk: float) -> void:
	DrawUtil.rr(self, rs, Color("b9b4a6").lerp(Color("55546a"), dusk * 0.5), 14)
	var b := Rect2(rs.position + Vector2(24, 24), Vector2(270, 130))
	draw_rect(Rect2(b.position + Vector2(8, 10), b.size), Color(0, 0, 0, 0.2))
	DrawUtil.rr(self, b, Color("e6dcc6").lerp(Color("6f6470"), dusk * 0.5), 6)
	draw_rect(Rect2(b.position + Vector2(8, 8), b.size - Vector2(16, 16)), Color("5b6f8f").lerp(Color("231c3c"), dusk * 0.35))
	draw_line(b.position + Vector2(b.size.x * 0.5, 8), b.position + Vector2(b.size.x * 0.5, b.size.y - 8), Color("3f4f6a"), 3.0)
	DrawUtil.rr(self, Rect2(b.position + Vector2(b.size.x * 0.5 - 14, b.size.y - 4), Vector2(28, 12)), Color("56372b"), 2)
	var board := Rect2(rs.position + Vector2(300, 40), Vector2(190, 62))
	draw_line(board.position + Vector2(30, 62), board.position + Vector2(30, 86), Color("5b4634"), 4.0)
	draw_line(board.position + Vector2(160, 62), board.position + Vector2(160, 86), Color("5b4634"), 4.0)
	DrawUtil.rr(self, board, Color("f7f3e8"), 5)
	draw_rect(board, Color("2f4858"), false, 3.0)
	draw_string(ThemeDB.fallback_font, board.position + Vector2(0, 30), "WOZIG", HORIZONTAL_ALIGNMENT_CENTER, board.size.x, 28, Color("1f6b6b"))
	draw_string(ThemeDB.fallback_font, board.position + Vector2(0, 50), "COMMUNITY MANAGEMENT", HORIZONTAL_ALIGNMENT_CENTER, board.size.x, 11, Color("2f4858"))
	var pool := Rect2(rs.position + Vector2(24, 190), Vector2(210, 140))
	DrawUtil.rr(self, pool.grow(10.0), Color("d9d4c7"), 8)
	DrawUtil.rr(self, pool, Color("4aa9c7").lerp(Color("25465d"), dusk * 0.6), 8)
	for k in 4:
		draw_line(pool.position + Vector2(0, 20 + k * 30), pool.end - Vector2(0, 120 - k * 30), Color(1, 1, 1, 0.5), 1.0)
	for k in 5:
		DrawUtil.rr(self, Rect2(rs.position + Vector2(290 + k * 22, 200), Vector2(14, 28)), Color("cfd6dc"), 3)


# ---------------------------------------------------------------- roads

func _path_points(street) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var path: PackedVector2Array = street.path
	var first := -1
	var last := -1
	for i in path.size():
		if path[i].y >= _view.position.y and path[i].y <= _view.end.y:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return pts
	for i in range(maxi(first - 1, 0), mini(last + 2, path.size())):
		pts.append(path[i] - _cam)
	return pts


func _roads(hood: Neighborhood) -> void:
	var dusk := float(ctx.dusk)
	var walk := WALK_COL.lerp(Color("8f8aa8"), dusk * 0.6)
	var road := ROAD_COL.lerp(Color("22263a"), dusk * 0.6)
	var curb := CURB_COL.lerp(Color("5f5d78"), dusk * 0.6)
	var paths: Array = []
	for street in hood.streets:
		paths.append(_path_points(street))
	for i in hood.streets.size():
		var street = hood.streets[i]
		var pts: PackedVector2Array = paths[i]
		if pts.size() >= 2:
			draw_polyline(pts, walk, (street.half + Neighborhood.WALK_W) * 2.0, true)
		for bulb in street.bulbs:
			if _view.has_point(bulb.center):
				draw_circle(bulb.center - _cam, Neighborhood.BULB_R + Neighborhood.WALK_W, walk)
	for i in hood.streets.size():
		var street = hood.streets[i]
		var pts: PackedVector2Array = paths[i]
		if pts.size() >= 2:
			draw_polyline(pts, curb, street.half * 2.0 + 5.0, true)
		for bulb in street.bulbs:
			if _view.has_point(bulb.center):
				draw_circle(bulb.center - _cam, Neighborhood.BULB_R + 2.5, curb)
	for i in hood.streets.size():
		var street = hood.streets[i]
		var pts: PackedVector2Array = paths[i]
		if pts.size() >= 2:
			draw_polyline(pts, road, street.half * 2.0, true)
		for bulb in street.bulbs:
			if _view.has_point(bulb.center):
				var c: Vector2 = bulb.center - _cam
				draw_circle(c, Neighborhood.BULB_R, road)
				# Landscaped island at the center of every cul-de-sac.
				draw_circle(c, 30.0, curb)
				draw_circle(c, 26.0, Color("4f9b64").lerp(Color("274c42"), dusk * 0.6))
				draw_circle(c + Vector2(-6, -4), 9.0, Color("2f7a4a"))
	# Only the avenue carries a center line.
	var spts: PackedVector2Array = paths[0]
	var i2 := 0
	while i2 + 1 < spts.size():
		var mid := (spts[i2] + spts[i2 + 1]) * 0.5 + _cam
		var in_bulb := false
		for bulb in hood.streets[0].bulbs:
			in_bulb = in_bulb or mid.distance_to(bulb.center) < Neighborhood.BULB_R + 24.0
		if not in_bulb:
			draw_line(spts[i2], spts[i2 + 1], Color("ffe08a", 0.7), 3.5)
		i2 += 2


func _furniture_pass() -> void:
	var dusk := float(ctx.dusk)
	for item in _furniture:
		var pos: Vector2 = item.pos
		if not _view.has_point(pos):
			continue
		var p := pos - _cam
		match str(item.type):
			"light":
				draw_circle(p, 3.0, Color("52616f"))
				draw_circle(p + Vector2(0, -2), 5.0, Color("ffe9a6") if dusk > 0.2 else Color("d8dde3"))
				if dusk > 0.2:
					draw_circle(p, 34.0, Color(1.0, 0.92, 0.55, 0.16 * dusk))
			"hydrant":
				draw_circle(p, 6.0, Color("d94b45"))
				draw_circle(p, 2.5, Color("f4f4f4"))
			"grate":
				ActorPainter.place(self, _base, p, float(item.rot), 1.0)
				draw_rect(Rect2(-9, -3, 18, 6), Color("2c3039"))
				for k in 4:
					draw_line(Vector2(-6 + k * 4, -3), Vector2(-6 + k * 4, 3), Color("5b6270"), 1.0)
				draw_set_transform_matrix(_base)
			"crosswalk":
				ActorPainter.place(self, _base, p, float(item.rot), 1.0)
				var half := float(item.half)
				var y := -half + 8.0
				while y < half - 4.0:
					draw_rect(Rect2(-10, y, 20, 5), Color(1, 1, 1, 0.8))
					y += 11.0
				draw_set_transform_matrix(_base)
			"stop":
				draw_line(p, p + Vector2(0, -16), Color("52616f"), 2.0)
				draw_circle(p + Vector2(0, -22), 8.0, Color("c93a32"))
				draw_circle(p + Vector2(0, -22), 8.0, Color.WHITE, false, 1.5)
			"name":
				draw_line(p, p + Vector2(0, -16), Color("52616f"), 2.0)
				DrawUtil.rr(self, Rect2(p + Vector2(-18, -28), Vector2(36, 11)), Color("2f7a4a"), 2)
				draw_line(p + Vector2(-13, -22), p + Vector2(13, -22), Color.WHITE, 1.5)


# ---------------------------------------------------------------- lots

func _yard(lot: LotScript) -> void:
	var dusk := float(ctx.dusk)
	var inches: float = ctx.grass[lot.id] if lot.id < ctx.grass.size() else 3.0
	var tall := clampf((inches - 3.0) / 7.0, 0.0, 1.0)
	var yard_col: Color = Color("3f9e60").lerp((SEASON_LAWN[int(ctx.season)] as Color).darkened(0.12), 0.55)
	yard_col = yard_col.lerp(Color("b2b04a"), tall * 0.5).lerp(Color("1c5a3e"), dusk * 0.5)
	var poly := PackedVector2Array()
	for p in lot.polygon:
		poly.append(p - _cam)
	draw_colored_polygon(poly, yard_col)
	var base := Color("2f9e57").lerp(Color("1c5a3e"), dusk * 0.7)
	for tuft in _tufts.get(lot.id, []):
		var p: Vector2 = (tuft.p as Vector2) - _cam
		var length: float = inches * INCH_PX * float(tuft.h)
		for a in [-0.55, 0.0, 0.55]:
			var ang: float = a + float(tuft.a) + sin(float(ctx.time) * 1.6 + p.y * 0.05) * 0.06
			draw_line(p, p + Vector2(sin(ang), -cos(ang)) * length, base.lightened(float(tuft.h) * 0.2 - 0.1), 2.0, true)
	# Driveway with a flared apron, then walkway, mailbox and beds.
	var curb := lot.curb - _cam
	var door_end := lot.driveway_end - _cam
	var paving := Color("b8b3a8").lerp(Color("686477"), dusk * 0.5)
	draw_line(curb, door_end, paving, lot.driveway_width, true)
	draw_line(curb, door_end, Color(1, 1, 1, 0.14), 2.0, true)
	var along := (door_end - curb).normalized()
	var across := Vector2(-along.y, along.x)
	draw_colored_polygon(PackedVector2Array([curb + across * (lot.driveway_width * 0.5 + 9.0), curb - across * (lot.driveway_width * 0.5 + 9.0),
			curb - across * lot.driveway_width * 0.5 + along * 10.0, curb + across * lot.driveway_width * 0.5 + along * 10.0]), paving)
	var ds := signf((lot.driveway_end - lot.center).dot(lot.right()))
	var door := lot.local_point(lot.house_size.x * 0.5 + 10.0, -ds * lot.house_size.y * 0.35) - _cam
	draw_line(door, door + lot.front * 44.0, Color("cfc9bd").lerp(Color("686477"), dusk * 0.5), 14.0, true)
	var mailbox := lot.mailbox - _cam
	draw_line(mailbox, mailbox + Vector2(0, -16), Color("5b4634"), 3.0, true)
	DrawUtil.rr(self, Rect2(mailbox + Vector2(-8, -26), Vector2(16, 10)), Color("344b59"), 3)
	if ctx.camera_ev.evidence.has(lot.id):
		draw_circle(mailbox + Vector2(14, -22), 4.0, Color("71b9dc"))
	for k in 4:
		var lateral := -ds * lot.house_size.y * (0.12 + k * 0.17)
		var shrub := lot.local_point(lot.house_size.x * 0.5 + 8.0, lateral) - _cam
		DrawUtil.ellipse(self, shrub, 8.0 + (k % 2) * 2.0, 6.0, Color("257149").lightened((lot.id + k) % 3 * 0.05))
		if int(ctx.season) == 0 and (lot.id + k) % 2 == 0:
			draw_circle(shrub + Vector2(2, -2), 2.0, Color("ff9ac2"))
	for entry: Dictionary in ctx.layouts.get(lot.id, []):
		if not entry.on_house:
			ObjectPainter.yard_object(self, _base, entry, (entry.pos as Vector2) - _cam, dusk, float(ctx.time))
	for parked in ctx.ambient.parked:
		if int(parked.lot) == lot.id and str(parked.kind) == "driveway":
			var pose: Dictionary = ctx.ambient.parked_pose(parked)
			ActorPainter.place(self, _base, (pose.pos as Vector2) - _cam, (pose.heading as Vector2).angle() + PI * 0.5, 0.8)
			ActorPainter.car(self, parked.color, dusk)
			draw_set_transform_matrix(_base)


func _road_vehicles() -> void:
	var dusk := float(ctx.dusk)
	for parked in ctx.ambient.parked:
		if str(parked.kind) != "curb":
			continue
		var pose: Dictionary = ctx.ambient.parked_pose(parked)
		var pos: Vector2 = pose.pos
		if not _view.has_point(pos):
			continue
		ActorPainter.place(self, _base, pos - _cam, (pose.heading as Vector2).angle() + PI * 0.5, 0.8)
		ActorPainter.car(self, parked.color, dusk)
		draw_set_transform_matrix(_base)
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
	# Rentals, business traffic and street parking all show up as extra cars at the curb.
	var counts := {"short_rental": 2, "business_traffic": 2, "street_parking": 4}
	for lot: LotScript in _lots:
		for entry: Dictionary in ctx.layouts.get(lot.id, []):
			if not counts.has(entry.id):
				continue
			var tangent := Vector2(-lot.front.y, lot.front.x)
			var n: int = counts[entry.id]
			for k in n:
				var p := lot.curb + lot.front * (Neighborhood.WALK_W + 22.0) + tangent * (-80.0 + k * (160.0 / maxf(n - 1, 1)))
				ActorPainter.place(self, _base, p - _cam, tangent.angle() + PI * 0.5, 0.8)
				ActorPainter.car(self, [Color("c4cad1"), Color("3d3f46"), Color("8a6fc4"), Color("2f9e57")][k % 4], dusk)
				draw_set_transform_matrix(_base)


# ---------------------------------------------------------------- trees

func _tree_color(tone: float) -> Color:
	return (SEASON_LEAF[int(ctx.season)] as Color).lightened(tone).lerp(Color("1c5a3e"), float(ctx.dusk) * 0.7)


func _each_tree(hood: Neighborhood, visit: Callable) -> void:
	for lot: LotScript in _lots:
		for tree in lot.trees:
			visit.call(tree)
	for tree in hood.street_trees:
		if _view.has_point(Vector2(tree.x, tree.y)):
			visit.call(tree)
	for tree in hood.woods_trees:
		if _view.has_point(Vector2(tree.x, tree.y)):
			visit.call(tree)


func _tree_shadows(hood: Neighborhood, shadow: Vector2) -> void:
	_each_tree(hood, func(tree: Vector3):
		DrawUtil.ellipse(self, Vector2(tree.x, tree.y) - _cam + shadow * 0.9, tree.z, tree.z, Color(0, 0, 0, 0.18)))


func _trees(hood: Neighborhood) -> void:
	var time := float(ctx.time)
	_each_tree(hood, func(tree: Vector3):
		var phase := tree.x * 0.013 + tree.y * 0.007
		var tone := sin(tree.x * 0.37 + tree.y * 0.21) * 0.12
		var sway := sin(time * 1.3 + phase) * 3.0
		var tc := Vector2(tree.x, tree.y) - _cam + Vector2(sway, 0)
		var r: float = tree.z
		draw_line(tc + Vector2(0, r * 0.7), tc + Vector2(-sway * 0.4, -r * 0.2), Color("6b4931"), 8.0, true)
		var g := _tree_color(tone)
		DrawUtil.ellipse(self, tc, r, r * 0.9, g)
		DrawUtil.ellipse(self, tc + Vector2(-r * 0.28, -r * 0.2), r * 0.62, r * 0.58, g.lightened(0.12))
		DrawUtil.ellipse(self, tc + Vector2(r * 0.3, -r * 0.08), r * 0.48, r * 0.5, g.darkened(0.08)))


# ---------------------------------------------------------------- markers

func _markers(lot: LotScript) -> void:
	var pins: Dictionary = ctx.pins
	var kind: String = pins.get(lot.id, "")
	var c := lot.center - _cam
	var time := float(ctx.time)
	var near: bool = lot.id == int(ctx.near)
	var active := kind == "lawn" or kind == "card" or kind == "reinspect"
	var status: String = ctx.case_states.get(lot.id, "")
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
		var pts := _path_points(street)
		if pts.size() >= 2:
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
