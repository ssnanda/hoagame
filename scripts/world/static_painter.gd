extends RefCounted
## Everything in the neighborhood that does not move: ground, landmarks, roads, street
## furniture, lots with their houses and trees. It draws in world coordinates into
## cached canvas chunks (see world_chunk.gd), so none of this runs per frame; the camera
## is a transform on the chunk root. Time-of-day is a tint on that root.

const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotScript := preload("res://scripts/world/lot.gd")
const DrawUtil := preload("res://scripts/world/draw_util.gd")
const ActorPainter := preload("res://scripts/world/actor_painter.gd")
const ObjectPainter := preload("res://scripts/world/object_painter.gd")
const HousePainter := preload("res://scripts/world/house_painter.gd")

const SEASON_LAWN := [Color("58c27d"), Color("66b858"), Color("b2a64f"), Color("d6e2e8")]
const SEASON_LEAF := [Color("48b86a"), Color("2f9e57"), Color("d9822b"), Color("e8eef2")]
const WALK_COL := Color("d9dde3")
const ROAD_COL := Color("3a4152")
const CURB_COL := Color("9aa0aa")
const INCH_PX := 4.5
const MOUNTAIN_Y := 380.0
const FURNITURE_BUCKET := 800.0

var ctx                                   ## street controller (season, grass, layouts, ambient)
var hood: Neighborhood
var styles: Array = []
var tufts: Dictionary = {}
var furniture: Array = []                 ## {type, pos, rot}


func setup(controller) -> void:
	ctx = controller
	hood = ctx.hood
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for lot: LotScript in hood.lots:
		styles.append(HousePainter.make_style(lot))
		var list: Array = []
		var minp := Vector2(INF, INF)
		var maxp := Vector2(-INF, -INF)
		for p in lot.polygon:
			minp = Vector2(minf(minp.x, p.x), minf(minp.y, p.y))
			maxp = Vector2(maxf(maxp.x, p.x), maxf(maxp.y, p.y))
		for _i in 70:
			var p := Vector2(rng.randf_range(minp.x, maxp.x), rng.randf_range(minp.y, maxp.y))
			if list.size() < 26 and Geometry2D.is_point_in_polygon(p, lot.polygon) \
					and Geometry2D.get_closest_point_to_segment(p, lot.curb, lot.driveway_end).distance_to(p) > lot.driveway_width * 0.5 + 6.0 \
					and not Geometry2D.is_point_in_polygon(p, lot.footprint(4.0)):
				list.append({"p": p, "h": rng.randf_range(0.6, 1.0), "a": rng.randf_range(-0.3, 0.3)})
		tufts[lot.id] = list
	_build_furniture()


## Chunk dispatch used by world_chunk.gd.
func draw_chunk(c: CanvasItem, kind: String, arg) -> void:
	match kind:
		"ground":
			draw_ground(c)
		"landmark":
			draw_landmark(c, hood.landmarks[int(arg)])
		"roads":
			draw_roads(c, int(arg))
		"furniture":
			draw_furniture(c, int(arg))
		"lot":
			draw_lot(c, hood.lots[int(arg)])
		"trees":
			draw_trees(c, int(arg))


func lawn_color() -> Color:
	return SEASON_LAWN[int(ctx.season)]


# ---------------------------------------------------------------- ground

func draw_ground(c: CanvasItem) -> void:
	c.draw_rect(Rect2(-200, -200, Neighborhood.WORLD_W + 400.0, Neighborhood.WORLD_H + 400.0), lawn_color())
	var y := 0.0
	var k := 0
	while y < Neighborhood.WORLD_H:
		if k % 2 == 0:
			c.draw_rect(Rect2(-200, y, Neighborhood.WORLD_W + 400.0, 160.0), Color(1, 1, 1, 0.045))
		y += 160.0
		k += 1
	var back := Color("75869b")
	var front := Color("536b64")
	var base_y := MOUNTAIN_Y
	for i in 9:
		var bx := -80.0 + i * 330.0
		var peak := Vector2(bx + 85.0, base_y - 145.0 - (i % 3) * 32.0)
		c.draw_colored_polygon(PackedVector2Array([Vector2(bx, base_y + 70.0), peak, Vector2(bx + 190.0, base_y + 70.0)]), back)
		c.draw_colored_polygon(PackedVector2Array([peak, peak + Vector2(-31, 52), peak + Vector2(4, 39), peak + Vector2(34, 58)]), Color("e8eef2", 0.9))
	for i in 8:
		var bx := -30.0 + i * 390.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(bx, base_y + 95.0), Vector2(bx + 95.0, base_y - 70.0), Vector2(bx + 210.0, base_y + 95.0)]), front)


func draw_landmark(c: CanvasItem, mark: Dictionary) -> void:
	var rs: Rect2 = mark.rect
	match str(mark.type):
		"park":
			DrawUtil.rr(c, rs, Color("7fcf86"), 18)
			DrawUtil.ellipse(c, rs.get_center(), rs.size.x * 0.32, rs.size.y * 0.3, Color("d8d1b8", 0.7))
			_playground(c, rs.get_center() + Vector2(-70, 0))
			for b in 3:
				DrawUtil.rr(c, Rect2(rs.get_center() + Vector2(60 + b * 52, -40 + b * 30), Vector2(28, 10)), Color("8a6747"), 2)
		"woods":
			DrawUtil.rr(c, rs, Color("2f7a4a"), 24)
		"pond", "lake":
			var center := rs.get_center()
			var half := rs.size * 0.5
			DrawUtil.ellipse(c, center, half.x + 14.0, half.y + 14.0, Color("b8d7b2"))
			DrawUtil.ellipse(c, center, half.x, half.y, Color("4aa9c7"))
			for i in 6:
				c.draw_arc(center + Vector2(sin(i * 1.7) * half.x * 0.3, -half.y * 0.6 + i * half.y * 0.22), 22.0 + i * 3.0,
						0.15, PI - 0.15, 16, Color(0.8, 0.95, 1.0, 0.35), 2.0)
			if str(mark.type) == "lake":
				c.draw_rect(Rect2(center + Vector2(-half.x - 6.0, -18.0), Vector2(120, 36)), Color("8a6747"))
				for x in range(int(center.x - half.x), int(center.x - half.x + 110), 18):
					c.draw_line(Vector2(x, center.y - 16.0), Vector2(x, center.y + 16.0), Color("b38a60"), 2.0)
		"clubhouse":
			_clubhouse(c, rs)


func _playground(c: CanvasItem, p: Vector2) -> void:
	DrawUtil.rr(c, Rect2(p + Vector2(-40, -30), Vector2(80, 60)), Color("c9b98c"), 8)
	c.draw_line(p + Vector2(-30, -20), p + Vector2(-30, 20), Color("d94b45"), 4.0)
	c.draw_line(p + Vector2(-10, -20), p + Vector2(-10, 20), Color("d94b45"), 4.0)
	for k in 2:
		c.draw_line(p + Vector2(-30 + k * 20, -20), p + Vector2(-30 + k * 20, 0), Color("52616f"), 2.0)
	DrawUtil.rr(c, Rect2(p + Vector2(8, -22), Vector2(26, 44)), Color("f2b632"), 5)
	DrawUtil.rr(c, Rect2(p + Vector2(10, -6), Vector2(22, 14)), Color("e07a1f"), 4)


## Management office with the pool. The Wozig sign is part of the scenery, not an ad banner.
func _clubhouse(c: CanvasItem, rs: Rect2) -> void:
	DrawUtil.rr(c, rs, Color("b9b4a6"), 14)
	var b := Rect2(rs.position + Vector2(24, 24), Vector2(270, 130))
	c.draw_rect(Rect2(b.position + Vector2(8, 10), b.size), Color(0, 0, 0, 0.2))
	DrawUtil.rr(c, b, Color("e6dcc6"), 6)
	c.draw_rect(Rect2(b.position + Vector2(8, 8), b.size - Vector2(16, 16)), Color("5b6f8f"))
	c.draw_line(b.position + Vector2(b.size.x * 0.5, 8), b.position + Vector2(b.size.x * 0.5, b.size.y - 8), Color("3f4f6a"), 3.0)
	DrawUtil.rr(c, Rect2(b.position + Vector2(b.size.x * 0.5 - 14, b.size.y - 4), Vector2(28, 12)), Color("56372b"), 2)
	var board := Rect2(rs.position + Vector2(300, 40), Vector2(190, 62))
	c.draw_line(board.position + Vector2(30, 62), board.position + Vector2(30, 86), Color("5b4634"), 4.0)
	c.draw_line(board.position + Vector2(160, 62), board.position + Vector2(160, 86), Color("5b4634"), 4.0)
	DrawUtil.rr(c, board, Color("f7f3e8"), 5)
	c.draw_rect(board, Color("2f4858"), false, 3.0)
	c.draw_string(ThemeDB.fallback_font, board.position + Vector2(0, 30), "WOZIG", HORIZONTAL_ALIGNMENT_CENTER, board.size.x, 28, Color("1f6b6b"))
	c.draw_string(ThemeDB.fallback_font, board.position + Vector2(0, 50), "COMMUNITY MANAGEMENT", HORIZONTAL_ALIGNMENT_CENTER, board.size.x, 11, Color("2f4858"))
	var pool := Rect2(rs.position + Vector2(24, 190), Vector2(210, 140))
	DrawUtil.rr(c, pool.grow(10.0), Color("d9d4c7"), 8)
	DrawUtil.rr(c, pool, Color("4aa9c7"), 8)
	for k in 4:
		c.draw_line(pool.position + Vector2(0, 20 + k * 30), pool.end - Vector2(0, 120 - k * 30), Color(1, 1, 1, 0.5), 1.0)
	for k in 5:
		DrawUtil.rr(c, Rect2(rs.position + Vector2(290 + k * 22, 200), Vector2(14, 28)), Color("cfd6dc"), 3)


# ---------------------------------------------------------------- roads

## Roads are drawn in three world-wide passes (sidewalk, curb, asphalt) so intersections
## merge cleanly: a side street's sidewalk never paints over the avenue's asphalt.
func draw_roads(c: CanvasItem, pass_i: int) -> void:
	for street in hood.streets:
		var path: PackedVector2Array = street.path
		match pass_i:
			0:
				c.draw_polyline(path, WALK_COL, (street.half + Neighborhood.WALK_W) * 2.0, true)
				for bulb in street.bulbs:
					c.draw_circle(bulb.center, Neighborhood.BULB_R + Neighborhood.WALK_W, WALK_COL)
			1:
				c.draw_polyline(path, CURB_COL, street.half * 2.0 + 5.0, true)
				for bulb in street.bulbs:
					c.draw_circle(bulb.center, Neighborhood.BULB_R + 2.5, CURB_COL)
			2:
				c.draw_polyline(path, ROAD_COL, street.half * 2.0, true)
				for bulb in street.bulbs:
					c.draw_circle(bulb.center, Neighborhood.BULB_R, ROAD_COL)
					# Landscaped island at the center of every cul-de-sac.
					c.draw_circle(bulb.center, 30.0, CURB_COL)
					c.draw_circle(bulb.center, 26.0, Color("4f9b64"))
					c.draw_circle(bulb.center + Vector2(-6, -4), 9.0, Color("2f7a4a"))
	if pass_i == 2:
		var spine = hood.streets[0]
		var path: PackedVector2Array = spine.path
		var i := 0
		while i + 1 < path.size():
			var mid := (path[i] + path[i + 1]) * 0.5
			var in_bulb := false
			for bulb in spine.bulbs:
				in_bulb = in_bulb or mid.distance_to(bulb.center) < Neighborhood.BULB_R + 24.0
			if not in_bulb:
				c.draw_line(path[i], path[i + 1], Color("ffe08a", 0.7), 3.5)
			i += 2


## Hydrants, drainage grates, streetlights and signs, placed once.
func _build_furniture() -> void:
	furniture.clear()
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
					_try_furniture("light", smp[0] + n * (edge - 6.0), t.angle())
					next_light += light_every
				if s >= next_hydrant:
					_try_furniture("hydrant", smp[0] + n * (edge + 4.0), t.angle())
					next_hydrant += 520.0
				if s >= next_grate:
					_try_furniture("grate", smp[0] + n * (street.half - 6.0), t.angle())
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
		furniture.append({"type": "crosswalk", "pos": start + dir * mouth, "rot": dir.angle(), "half": street.half})
		furniture.append({"type": "stop", "pos": start + dir * (mouth + 26.0) + n * (street.half + Neighborhood.WALK_W - 4.0), "rot": dir.angle()})
		furniture.append({"type": "name", "pos": start + dir * (mouth + 26.0) - n * (street.half + Neighborhood.WALK_W - 4.0), "rot": dir.angle()})


func _try_furniture(type: String, pos: Vector2, rot: float) -> void:
	if hood.driveway_at(pos) >= 0 or not hood.landmark_at(pos).is_empty():
		return
	for lot: LotScript in hood.lots:
		if absf(lot.curb.y - pos.y) < 70.0 and (lot.curb.distance_to(pos) < 52.0 or lot.mailbox.distance_to(pos) < 30.0):
			return
	for item in furniture:
		if item.type == type and (item.pos as Vector2).distance_to(pos) < 90.0:
			return
	furniture.append({"type": type, "pos": pos, "rot": rot})


func furniture_bucket_count() -> int:
	return int(ceil(Neighborhood.WORLD_H / FURNITURE_BUCKET))


func draw_furniture(c: CanvasItem, bucket: int) -> void:
	for item in furniture:
		var pos: Vector2 = item.pos
		if int(pos.y / FURNITURE_BUCKET) != bucket:
			continue
		match str(item.type):
			"light":
				c.draw_circle(pos, 3.0, Color("52616f"))
				c.draw_circle(pos + Vector2(0, -2), 5.0, Color("d8dde3"))
			"hydrant":
				c.draw_circle(pos, 6.0, Color("d94b45"))
				c.draw_circle(pos, 2.5, Color("f4f4f4"))
			"grate":
				ActorPainter.place(c, Transform2D.IDENTITY, pos, float(item.rot), 1.0)
				c.draw_rect(Rect2(-9, -3, 18, 6), Color("2c3039"))
				for k in 4:
					c.draw_line(Vector2(-6 + k * 4, -3), Vector2(-6 + k * 4, 3), Color("5b6270"), 1.0)
				c.draw_set_transform_matrix(Transform2D.IDENTITY)
			"crosswalk":
				ActorPainter.place(c, Transform2D.IDENTITY, pos, float(item.rot), 1.0)
				var half := float(item.half)
				var y := -half + 8.0
				while y < half - 4.0:
					c.draw_rect(Rect2(-10, y, 20, 5), Color(1, 1, 1, 0.8))
					y += 11.0
				c.draw_set_transform_matrix(Transform2D.IDENTITY)
			"stop":
				c.draw_line(pos, pos + Vector2(0, -16), Color("52616f"), 2.0)
				c.draw_circle(pos + Vector2(0, -22), 8.0, Color("c93a32"))
				c.draw_circle(pos + Vector2(0, -22), 8.0, Color.WHITE, false, 1.5)
			"name":
				c.draw_line(pos, pos + Vector2(0, -16), Color("52616f"), 2.0)
				DrawUtil.rr(c, Rect2(pos + Vector2(-18, -28), Vector2(36, 11)), Color("2f7a4a"), 2)
				c.draw_line(pos + Vector2(-13, -22), pos + Vector2(13, -22), Color.WHITE, 1.5)


# ---------------------------------------------------------------- lots

## One property in a single chunk: yard, driveway, beds, objects, parked cars, the
## house and its own trees. Redrawn only when the day or season changes.
func draw_lot(c: CanvasItem, lot: LotScript) -> void:
	var season: int = ctx.season
	var inches: float = ctx.grass[lot.id] if lot.id < ctx.grass.size() else 3.0
	var tall := clampf((inches - 3.0) / 7.0, 0.0, 1.0)
	var yard_col: Color = Color("3f9e60").lerp((SEASON_LAWN[season] as Color).darkened(0.12), 0.55)
	yard_col = yard_col.lerp(Color("b2b04a"), tall * 0.5)
	c.draw_colored_polygon(lot.polygon, yard_col)
	# All blades in two batched commands instead of ~80 separate lines per lot.
	var light_blades := PackedVector2Array()
	var dark_blades := PackedVector2Array()
	for tuft in tufts.get(lot.id, []):
		var p: Vector2 = tuft.p
		var length: float = inches * INCH_PX * float(tuft.h)
		var target: PackedVector2Array = light_blades if float(tuft.h) > 0.8 else dark_blades
		for a in [-0.55, 0.0, 0.55]:
			var ang: float = a + float(tuft.a)
			target.append(p)
			target.append(p + Vector2(sin(ang), -cos(ang)) * length)
	c.draw_multiline(dark_blades, Color("2a9050"), 2.0, true)
	c.draw_multiline(light_blades, Color("3aa862"), 2.0, true)
	# Driveway with a flared apron, then walkway, mailbox and beds.
	var paving := Color("b8b3a8")
	c.draw_line(lot.curb, lot.driveway_end, paving, lot.driveway_width, true)
	c.draw_line(lot.curb, lot.driveway_end, Color(1, 1, 1, 0.14), 2.0, true)
	var along := (lot.driveway_end - lot.curb).normalized()
	var across := Vector2(-along.y, along.x)
	c.draw_colored_polygon(PackedVector2Array([lot.curb + across * (lot.driveway_width * 0.5 + 9.0), lot.curb - across * (lot.driveway_width * 0.5 + 9.0),
			lot.curb - across * lot.driveway_width * 0.5 + along * 10.0, lot.curb + across * lot.driveway_width * 0.5 + along * 10.0]), paving)
	var ds := signf((lot.driveway_end - lot.center).dot(lot.right()))
	var door := lot.local_point(lot.house_size.x * 0.5 + 10.0, -ds * lot.house_size.y * 0.35)
	c.draw_line(door, door + lot.front * 44.0, Color("cfc9bd"), 14.0, true)
	_mailbox(c, lot, styles[lot.id])
	# Expansion joints along the driveway.
	var dlen := lot.curb.distance_to(lot.driveway_end)
	for k in range(1, int(dlen / 34.0)):
		var jp := lot.curb + along * (k * 34.0)
		c.draw_line(jp - across * lot.driveway_width * 0.5, jp + across * lot.driveway_width * 0.5, Color(0, 0, 0, 0.1), 1.5)
	var style: Dictionary = styles[lot.id]
	if style.bed:
		# Mulch bed hugging the front of the house, behind the shrubs.
		for k in 4:
			var bp := lot.local_point(lot.house_size.x * 0.5 + 8.0, -ds * lot.house_size.y * (0.12 + k * 0.17))
			DrawUtil.ellipse(c, bp, 15.0, 11.0, Color("6b4a35", 0.75))
	if style.dead_patch and season in [1, 2]:
		var patch := lot.local_point(lot.house_size.x * 0.5 + 34.0, ds * lot.house_size.y * 0.1)
		DrawUtil.ellipse(c, patch, 20.0, 13.0, Color("a89a52", 0.7))
		DrawUtil.ellipse(c, patch + Vector2(8, 4), 11.0, 7.0, Color("93864a", 0.6))
	for k in 4:
		var lateral := -ds * lot.house_size.y * (0.12 + k * 0.17)
		var shrub := lot.local_point(lot.house_size.x * 0.5 + 8.0, lateral)
		DrawUtil.ellipse(c, shrub, 8.0 + (k % 2) * 2.0, 6.0, Color("257149").lightened((lot.id + k) % 3 * 0.05))
		if season == 0 and (lot.id + k) % 2 == 0:
			c.draw_circle(shrub + Vector2(2, -2), 2.0, Color("ff9ac2"))
	_season_yard(c, lot, season)
	_decor(c, lot, style, ds)
	if not lot.corner_edge.is_empty():
		_corner_hedge(c, lot)
	var entries: Array = ctx.layouts.get(lot.id, [])
	for entry: Dictionary in entries:
		if not entry.on_house:
			ObjectPainter.yard_object(c, Transform2D.IDENTITY, entry, entry.pos, 0.0, 0.0)
	for parked in ctx.ambient.parked:
		if int(parked.lot) != lot.id:
			continue
		var pose: Dictionary = ctx.ambient.parked_pose(parked)
		ActorPainter.place(c, Transform2D.IDENTITY, pose.pos, (pose.heading as Vector2).angle() + PI * 0.5, 0.8)
		ActorPainter.car(c, parked.color, 0.0)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	# Rentals, business traffic and street parking show up as extra cars at the curb.
	var counts := {"short_rental": 2, "business_traffic": 2, "street_parking": 4}
	for entry: Dictionary in entries:
		if not counts.has(entry.id):
			continue
		var tangent := Vector2(-lot.front.y, lot.front.x)
		var n: int = counts[entry.id]
		for k in n:
			var p := lot.curb + lot.front * (Neighborhood.WALK_W + 22.0) + tangent * (-80.0 + k * (160.0 / maxf(n - 1, 1)))
			ActorPainter.place(c, Transform2D.IDENTITY, p, tangent.angle() + PI * 0.5, 0.8)
			ActorPainter.car(c, [Color("c4cad1"), Color("3d3f46"), Color("8a6fc4"), Color("2f9e57")][k % 4], 0.0)
			c.draw_set_transform_matrix(Transform2D.IDENTITY)
	for tree in lot.trees:
		_tree_shadow(c, tree)
	HousePainter.draw(c, Transform2D.IDENTITY, lot, styles[lot.id], lot.center, 1.0, 0.0, 0.0, entries, season)
	for tree in lot.trees:
		_tree(c, tree)


func _mailbox(c: CanvasItem, lot: LotScript, style: Dictionary) -> void:
	var m := lot.mailbox
	DrawUtil.ellipse(c, m + Vector2(5, 3), 8.0, 4.0, Color(0, 0, 0, 0.18))
	match int(style.mailbox):
		1:
			DrawUtil.rr(c, Rect2(m + Vector2(-6, -22), Vector2(12, 22)), Color("a4553f"), 2)
			DrawUtil.rr(c, Rect2(m + Vector2(-8, -28), Vector2(16, 8)), Color("344b59"), 3)
		2:
			DrawUtil.rr(c, Rect2(m + Vector2(-9, -26), Vector2(18, 26)), Color("52616f"), 3)
			for k in 3:
				c.draw_line(m + Vector2(-6, -20 + k * 7), m + Vector2(6, -20 + k * 7), Color("c9cdd2"), 1.5)
		_:
			c.draw_line(m, m + Vector2(0, -16), Color("5b4634"), 3.0, true)
			DrawUtil.rr(c, Rect2(m + Vector2(-8, -26), Vector2(16, 10)), Color("344b59"), 3)
	# House number on the box.
	c.draw_rect(Rect2(m + Vector2(-3, -22), Vector2(6, 2)), Color("f4ecd8"))


## Small personal touches: flag, gnome, flamingo or wind spinner by the front walk.
func _decor(c: CanvasItem, lot: LotScript, style: Dictionary, ds: float) -> void:
	var p := lot.local_point(lot.house_size.x * 0.5 + 40.0, -ds * lot.house_size.y * 0.42)
	match int(style.decor):
		1:
			c.draw_line(p, p + Vector2(0, -26), Color("cfd2d6"), 2.0)
			c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -26), p + Vector2(15, -22), p + Vector2(0, -16)]), Color("d94b45"))
		2:
			DrawUtil.ellipse(c, p + Vector2(0, 2), 5.0, 3.0, Color(0, 0, 0, 0.2))
			c.draw_circle(p, 4.0, Color("d94b45"))
			c.draw_circle(p + Vector2(0, 5), 3.0, Color("5aa0d6"))
		3:
			c.draw_line(p, p + Vector2(0, -14), Color("e56b8f"), 2.0)
			DrawUtil.ellipse(c, p + Vector2(0, -16), 4.0, 3.0, Color("f08aa8"))
		4:
			c.draw_line(p, p + Vector2(0, -18), Color("52616f"), 2.0)
			for k in 4:
				c.draw_circle(p + Vector2(0, -22) + Vector2.from_angle(k * 1.57) * 5.0, 2.2, [Color("ff7aa8"), Color("ffd24d"), Color("5aa0d6"), Color("7ee081")][k])


## Hedge along the side of a corner lot that faces the other street.
func _corner_hedge(c: CanvasItem, lot: LotScript) -> void:
	var a: Vector2 = lot.corner_edge[0]
	var b: Vector2 = lot.corner_edge[1]
	var inward := (lot.center - (a + b) * 0.5).normalized() * 9.0
	if lot.id % 2 == 0:
		c.draw_line(a + inward, b + inward, Color("1f6b43"), 11.0, true)
		for k in 4:
			c.draw_circle(a.lerp(b, (k + 0.5) / 4.0) + inward, 7.0, Color("2f9e57"))
	else:
		# White picket fence instead of a hedge, so corner lots read differently lot to lot.
		c.draw_line(a + inward, b + inward, Color("efe0bd"), 3.0, true)
		var count := int(a.distance_to(b) / 9.0)
		for k in count:
			c.draw_circle(a.lerp(b, (k + 0.5) / maxf(count, 1.0)) + inward, 2.2, Color("f7f0d8"))
	# Street-name post on the corner.
	var post: Vector2 = a.lerp(b, 0.05) + inward * 0.2
	c.draw_line(post, post + Vector2(0, -18), Color("52616f"), 2.0)
	DrawUtil.rr(c, Rect2(post + Vector2(-16, -30), Vector2(32, 11)), Color("2f7a4a"), 2)
	c.draw_line(post + Vector2(-11, -24), post + Vector2(11, -24), Color.WHITE, 1.5)


## Per-season yard props that hold still: spring tulips, fall leaf piles, winter snow and lights.
## (Summer sprinklers animate, so the dynamic layer draws those.)
func _season_yard(c: CanvasItem, lot: LotScript, season: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = lot.id * 131 + 7
	var ds := signf((lot.driveway_end - lot.center).dot(lot.right()))
	match season:
		0:
			for k in 5:
				var p := lot.local_point(lot.house_size.x * 0.5 + 22.0, -ds * (lot.house_size.y * 0.15 + k * 11.0))
				c.draw_circle(p, 2.6, [Color("ff7aa8"), Color("ffd24d"), Color("b48cff")][(lot.id + k) % 3])
		1:
			if lot.id % 4 == 0:
				c.draw_circle(lot.local_point(lot.house_size.x * 0.5 + 34.0, -ds * lot.house_size.y * 0.3), 3.0, Color("52616f"))
		2:
			for k in 3:
				var p := lot.local_point(lot.house_size.x * 0.5 + 18.0 + rng.randf() * 26.0, rng.randf_range(-1.0, 1.0) * lot.house_size.y * 0.4)
				DrawUtil.ellipse(c, p, 9.0, 6.0, [Color("d9822b"), Color("b5482a"), Color("e0b03a")][k % 3])
		3:
			for k in 4:
				var p := lot.local_point(lot.house_size.x * 0.5 + 16.0 + rng.randf() * 30.0, rng.randf_range(-1.0, 1.0) * lot.house_size.y * 0.45)
				DrawUtil.ellipse(c, p, 12.0, 7.0, Color(0.96, 0.98, 1.0, 0.85))
			if lot.id % 3 == 0:
				var tree := lot.local_point(lot.house_size.x * 0.5 + 40.0, ds * lot.house_size.y * 0.3)
				c.draw_colored_polygon(PackedVector2Array([tree + Vector2(0, -16), tree + Vector2(-9, 8), tree + Vector2(9, 8)]), Color("1f6b43"))
				for k in 4:
					c.draw_circle(tree + Vector2(sin(k * 1.7) * 5.0, -8.0 + k * 5.0), 1.8, [Color("ff4d4d"), Color("ffd33d"), Color("4dd2ff"), Color("7ee081")][k])


# ---------------------------------------------------------------- trees

func _tree_color(tone: float) -> Color:
	return (SEASON_LEAF[int(ctx.season)] as Color).lightened(tone)


func _tree_shadow(c: CanvasItem, tree: Vector3) -> void:
	DrawUtil.ellipse(c, Vector2(tree.x, tree.y) + Vector2(16.0, 20.0), tree.z, tree.z, Color(0, 0, 0, 0.18))


func _tree(c: CanvasItem, tree: Vector3) -> void:
	var tone := sin(tree.x * 0.37 + tree.y * 0.21) * 0.12
	var tc := Vector2(tree.x, tree.y)
	var r: float = tree.z
	if fposmod(tree.x * 7.0 + tree.y * 3.0, 4.0) < 1.0:
		# Conifer: stacked triangles, stays green through winter.
		var green := Color("1f6b43").lerp(Color("d6e2e8"), 0.35 if int(ctx.season) == 3 else 0.0)
		for k in 3:
			var w := r * (1.0 - k * 0.24)
			var y0 := tc.y + r * 0.5 - k * r * 0.52
			c.draw_colored_polygon(PackedVector2Array([Vector2(tc.x - w, y0), Vector2(tc.x + w, y0), Vector2(tc.x, y0 - r * 0.9)]), green.lightened(k * 0.06))
		return
	c.draw_line(tc + Vector2(0, r * 0.7), tc + Vector2(0, -r * 0.2), Color("6b4931"), 8.0, true)
	var g := _tree_color(tone)
	DrawUtil.ellipse(c, tc, r, r * 0.9, g)
	DrawUtil.ellipse(c, tc + Vector2(-r * 0.28, -r * 0.2), r * 0.62, r * 0.58, g.lightened(0.12))
	DrawUtil.ellipse(c, tc + Vector2(r * 0.3, -r * 0.08), r * 0.48, r * 0.5, g.darkened(0.08))


## Street trees and woods, bucketed by y so each chunk stays small.
func draw_trees(c: CanvasItem, bucket: int) -> void:
	var lists: Array = [hood.street_trees, hood.woods_trees]
	for list in lists:
		for tree: Vector3 in list:
			if int(tree.y / FURNITURE_BUCKET) == bucket:
				_tree_shadow(c, tree)
	for list in lists:
		for tree: Vector3 in list:
			if int(tree.y / FURNITURE_BUCKET) == bucket:
				_tree(c, tree)
