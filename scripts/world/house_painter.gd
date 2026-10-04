extends RefCounted
## One home from above, in the lot's own frame: origin at the house center,
## +x toward the street, +y across the frontage. Six archetypes share one
## palette so the subdivision looks planned, not random.

const DrawUtil := preload("res://scripts/world/draw_util.gd")
const ActorPainter := preload("res://scripts/world/actor_painter.gd")
const LotScript := preload("res://scripts/world/lot.gd")
const ObjectPainter := preload("res://scripts/world/object_painter.gd")

const ROOFS := [Color("c4543e"), Color("5b6f8f"), Color("8a6f56"), Color("4f7f6a"), Color("805b73"), Color("b77945"), Color("6d7480")]
const WALLS := [Color("ddd1bb"), Color("cfd8dc"), Color("e6d8c0"), Color("c9b79c"), Color("d9d9d4"), Color("bfc8b2")]
const BRICK := Color("a4553f")


## Deterministic per-lot look, varied inside a restrained palette.
static func make_style(lot: LotScript) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = lot.id * 977 + 31
	var arch := lot.archetype
	var brick := arch == 3 or (arch in [0, 1] and rng.randf() < 0.25)
	return {
		"roof": ROOFS[rng.randi() % ROOFS.size()],
		"wall": BRICK if brick else WALLS[rng.randi() % WALLS.size()],
		"brick": brick,
		"solar": rng.randf() < 0.18,
		"fence": rng.randf() < 0.3,
		"pool": rng.randf() < 0.1,
		"patio": rng.randf() < 0.45,
		"chimney": rng.randf() < 0.55 or arch == 3,
		"ac": rng.randf() < 0.7,
		"chimney_y": rng.randf_range(-0.3, 0.3),
		"garage_color": Color("c9cdd2").lerp(Color("8a8f98"), rng.randf() * 0.5),
	}


static func draw(c: CanvasItem, base: Transform2D, lot: LotScript, style: Dictionary,
		center: Vector2, focus_scale: float, dusk: float, time: float, entries: Array) -> void:
	ActorPainter.place(c, base, center, lot.rotation(), focus_scale)
	var dx := lot.house_size.x
	var dy := lot.house_size.y
	var hx := dx * 0.5
	var hy := dy * 0.5
	var drive_lat := (lot.driveway_end - lot.center).dot(lot.right())
	var ds := signf(drive_lat) if drive_lat != 0.0 else 1.0
	var roof: Color = (style.roof as Color).lerp(Color("231c3c"), dusk * 0.35)
	var wall: Color = (style.wall as Color).lerp(Color("6f6470"), dusk * 0.5)
	# Cast shadow always falls the same way in the world, whatever the lot's heading.
	var shadow := Vector2(18.0, 22.0).rotated(-lot.rotation()) * (1.0 + dusk * 1.2) / focus_scale
	c.draw_rect(Rect2(Vector2(-hx, -hy) + shadow, Vector2(dx, dy)), Color(0, 0, 0, 0.2))
	# Backyard extras sit behind the house.
	if style.patio:
		DrawUtil.rr(c, Rect2(-hx - 32.0, -hy * 0.45, 30.0, hy * 0.9), Color("b9a98a").lerp(Color("5f5870"), dusk * 0.5), 3)
	if style.pool:
		DrawUtil.rr(c, Rect2(-hx - 56.0, -hy * 0.35, 40.0, hy * 0.7), Color("e8f1f2"), 6)
		DrawUtil.rr(c, Rect2(-hx - 52.0, -hy * 0.3, 32.0, hy * 0.6), Color("4aa9c7").lerp(Color("25465d"), dusk * 0.6), 5)
	if style.fence:
		for k in range(-int(hy) - 6, int(hy) + 6, 12):
			c.draw_rect(Rect2(-hx - 58.0, float(k) - 2.0, 4.0, 4.0), Color("efe0bd"))
		c.draw_line(Vector2(-hx - 56.0, -hy - 6.0), Vector2(-hx - 56.0, hy + 6.0), Color("cbb995"), 2.0)
	# Walls, then the roof inset so the eave reads as a border.
	DrawUtil.rr(c, Rect2(-hx, -hy, dx, dy), wall, 5)
	if style.brick:
		var by := -hy + 6.0
		while by < hy:
			c.draw_line(Vector2(-hx + 2.0, by), Vector2(hx - 2.0, by), Color(0.2, 0.1, 0.07, 0.25), 1.5)
			by += 8.0
	_roof(c, lot.archetype, hx - 5.0, hy - 5.0, roof)
	if style.solar:
		for row in 2:
			for col in 3:
				var panel := Rect2(Vector2(-hx * 0.75 + row * 26.0, -hy * 0.75 + col * 30.0), Vector2(22, 27))
				DrawUtil.rr(c, panel, Color("16364f"), 2)
				c.draw_rect(panel, Color("65a8c9", 0.7), false, 1.5)
	if style.chimney:
		DrawUtil.rr(c, Rect2(-hx * 0.3, float(style.chimney_y) * dy - 9.0, 18.0, 18.0), Color("765044"), 3)
	if style.ac:
		DrawUtil.rr(c, Rect2(-hx - 20.0, -ds * hy * 0.55 - 11.0, 18.0, 22.0), Color("aeb6bc"), 3)
		c.draw_circle(Vector2(-hx - 11.0, -ds * hy * 0.55), 6.0, Color("6e7880"), false, 2.0)
	# Garage door where the driveway arrives, porch and door on the other side.
	var gw := lot.driveway_width + 12.0
	DrawUtil.rr(c, Rect2(hx - 4.0, drive_lat - gw * 0.5, 8.0, gw), style.garage_color, 2)
	for k in 3:
		c.draw_line(Vector2(hx - 3.0, drive_lat - gw * 0.5 + (k + 1) * gw / 4.0), Vector2(hx + 3.0, drive_lat - gw * 0.5 + (k + 1) * gw / 4.0), Color(0, 0, 0, 0.25), 1.0)
	var door_y := -ds * hy * 0.35
	DrawUtil.rr(c, Rect2(hx - 2.0, door_y - 16.0, 16.0, 32.0), Color("d8c6a3").lerp(Color("6c6280"), dusk * 0.5), 3)
	DrawUtil.rr(c, Rect2(hx + 2.0, door_y - 7.0, 6.0, 14.0), Color("56372b"), 2)
	for lamp in [-1.0, 1.0]:
		c.draw_circle(Vector2(hx + 5.0, door_y + lamp * 15.0), 3.0, Color("ffd36e"))
		c.draw_circle(Vector2(hx + 5.0, drive_lat + lamp * (gw * 0.5 + 4.0)), 2.5, Color("ffd36e"))
	if dusk > 0.05:
		DrawUtil.ellipse(c, Vector2(hx + 8.0, door_y), 20.0, 16.0, Color("ffd36e", 0.5 * dusk))
		for wy in [-hy * 0.6, hy * 0.6]:
			DrawUtil.rr(c, Rect2(hx - 8.0, wy - 9.0, 8.0, 18.0), Color("ffd36e", 0.8 * dusk), 2)
	for entry: Dictionary in entries:
		if entry.on_house:
			ObjectPainter.house_object(c, entry, lot, time)
	c.draw_set_transform_matrix(base)


static func _roof(c: CanvasItem, arch: int, hx: float, hy: float, roof: Color) -> void:
	var light := roof.lightened(0.14)
	var dark := roof.darkened(0.14)
	match arch:
		1, 3:
			# Hip roof: four facets meeting at a short ridge along the frontage.
			var rx := hx * 0.35
			var ry := hy * 0.45
			c.draw_colored_polygon(PackedVector2Array([Vector2(hx, -hy), Vector2(hx, hy), Vector2(rx, ry), Vector2(rx, -ry)]), light)
			c.draw_colored_polygon(PackedVector2Array([Vector2(-hx, -hy), Vector2(-hx, hy), Vector2(-rx, ry), Vector2(-rx, -ry)]), dark)
			c.draw_colored_polygon(PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(rx, -ry), Vector2(-rx, -ry)]), roof)
			c.draw_colored_polygon(PackedVector2Array([Vector2(-hx, hy), Vector2(hx, hy), Vector2(rx, ry), Vector2(-rx, ry)]), roof.darkened(0.07))
			c.draw_line(Vector2(-rx, -ry), Vector2(rx, -ry), roof.darkened(0.35), 2.0)
			c.draw_line(Vector2(-rx, ry), Vector2(rx, ry), roof.darkened(0.35), 2.0)
			c.draw_line(Vector2(-rx, -ry), Vector2(-rx, ry), roof.darkened(0.35), 2.0)
		2:
			# Craftsman: ridge along the depth, with a street-facing porch gable.
			c.draw_rect(Rect2(-hx, -hy, hx * 2.0, hy), light)
			c.draw_rect(Rect2(-hx, 0.0, hx * 2.0, hy), dark)
			c.draw_line(Vector2(-hx, 0), Vector2(hx, 0), roof.darkened(0.35), 3.0)
			c.draw_colored_polygon(PackedVector2Array([Vector2(hx + 12.0, -26.0), Vector2(hx + 12.0, 26.0), Vector2(hx - 18.0, 26.0), Vector2(hx - 18.0, -26.0)]), roof.lightened(0.05))
			c.draw_line(Vector2(hx - 18.0, 0), Vector2(hx + 12.0, 0), roof.darkened(0.35), 2.0)
		4:
			# Modern: flat roof, parapet and a raised volume.
			c.draw_rect(Rect2(-hx, -hy, hx * 2.0, hy * 2.0), Color("c7ccd1"))
			c.draw_rect(Rect2(-hx, -hy, hx * 2.0, hy * 2.0), Color("5c636b"), false, 3.0)
			c.draw_rect(Rect2(-hx * 0.9, -hy * 0.9, hx * 1.1, hy * 1.1), Color("aab1b8"))
			c.draw_rect(Rect2(-hx * 0.55, -hy * 0.55, hx * 0.6, hy * 0.4), Color("6ea3bd", 0.8))
		_:
			c.draw_rect(Rect2(0, -hy, hx, hy * 2.0), light)
			c.draw_rect(Rect2(-hx, -hy, hx, hy * 2.0), dark)
			var ry2 := -hx + 8.0
			while ry2 < hx:
				c.draw_line(Vector2(ry2, -hy), Vector2(ry2, hy), Color(0, 0, 0, 0.08), 2.0)
				ry2 += 14.0
			c.draw_line(Vector2(0, -hy), Vector2(0, hy), roof.darkened(0.35), 3.0)
