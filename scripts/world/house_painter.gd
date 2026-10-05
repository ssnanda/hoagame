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
		"garage_open": rng.randf() < 0.14,
		"lights": rng.randf() < 0.7,
		"garage_color": Color("c9cdd2").lerp(Color("8a8f98"), rng.randf() * 0.5),
		"shutter": [Color("2f4858"), Color("7a2f2a"), Color("2f5a43"), Color("f4ecd8"), Color("3b3b44")][rng.randi() % 5],
		"shutters": arch in [0, 2, 3] and rng.randf() < 0.7,
		"porch": arch in [0, 2, 5] and rng.randf() < 0.6,
		"decor": rng.randi() % 5,          ## 0 none, 1 flag, 2 gnome, 3 flamingo, 4 wind spinner
		"bed": rng.randf() < 0.75,
		"mailbox": rng.randi() % 3,        ## 0 post, 1 brick pillar, 2 cluster box
		"conifer": rng.randf() < 0.25,
		"dead_patch": rng.randf() < 0.3,
		"deck": rng.randf() < 0.25 and arch != 4,
		"swing": rng.randf() < 0.12,
	}


static func draw(c: CanvasItem, base: Transform2D, lot: LotScript, style: Dictionary,
		center: Vector2, focus_scale: float, dusk: float, time: float, entries: Array, season := 0) -> void:
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
		if season == 1:
			# Summer: people in the pool.
			for k in 2:
				c.draw_circle(Vector2(-hx - 40.0 + sin(time * 0.8 + k * 2.0) * 6.0, float(k - 0.5) * 18.0 + cos(time + k) * 4.0), 3.5, Color("f2c29b"))
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
	if season == 3:
		# Snow cap on the back half of the roof.
		c.draw_rect(Rect2(-hx + 6.0, -hy + 6.0, hx - 4.0, dy - 12.0), Color(0.95, 0.97, 1.0, 0.72))
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
	if style.garage_open:
		DrawUtil.rr(c, Rect2(hx - 14.0, drive_lat - gw * 0.5 + 2.0, 16.0, gw - 4.0), Color("1b1d22"), 2)
		DrawUtil.rr(c, Rect2(hx - 12.0, drive_lat - gw * 0.5 + 8.0, 9.0, gw - 16.0), Color("6d7480"), 2)
	var door_y := -ds * hy * 0.35
	DrawUtil.rr(c, Rect2(hx - 2.0, door_y - 16.0, 16.0, 32.0), Color("d8c6a3").lerp(Color("6c6280"), dusk * 0.5), 3)
	DrawUtil.rr(c, Rect2(hx + 2.0, door_y - 7.0, 6.0, 14.0), Color("56372b"), 2)
	for lamp in [-1.0, 1.0]:
		c.draw_circle(Vector2(hx + 5.0, door_y + lamp * 15.0), 3.0, Color("ffd36e"))
		c.draw_circle(Vector2(hx + 5.0, drive_lat + lamp * (gw * 0.5 + 4.0)), 2.5, Color("ffd36e"))
	if season == 3:
		# Holiday lights along the front eave and a wreath on the door.
		if style.lights:
			var tick := int(time * 2.0)
			for k in range(int(-hy) + 6, int(hy) - 4, 11):
				var lit := (k / 11 + tick) % 3
				c.draw_circle(Vector2(hx - 1.0, float(k)), 2.6, [Color("ff4d4d"), Color("ffd33d"), Color("4dd2ff")][lit])
				if dusk > 0.2:
					c.draw_circle(Vector2(hx - 1.0, float(k)), 6.0, Color(1, 0.95, 0.6, 0.25 * dusk))
		c.draw_circle(Vector2(hx + 9.0, door_y), 5.0, Color("2f7a4a"), false, 2.5)
		c.draw_circle(Vector2(hx + 9.0, door_y - 4.0), 1.8, Color("d94b45"))
	if dusk > 0.05:
		DrawUtil.ellipse(c, Vector2(hx + 8.0, door_y), 20.0, 16.0, Color("ffd36e", 0.5 * dusk))
		for wy in [-hy * 0.6, hy * 0.6]:
			DrawUtil.rr(c, Rect2(hx - 8.0, wy - 9.0, 8.0, 18.0), Color("ffd36e", 0.8 * dusk), 2)
	_details(c, lot, style, hx, hy, drive_lat, ds, door_y, dusk)
	for entry: Dictionary in entries:
		if entry.on_house:
			ObjectPainter.house_object(c, entry, lot, time)
	c.draw_set_transform_matrix(base)


## Trim that makes each house its own: shutters, porch roof and columns, window glints,
## a back deck and a swing set, plus roof shingle texture.
static func _details(c: CanvasItem, lot: LotScript, style: Dictionary, hx: float, hy: float, drive_lat: float,
		ds: float, door_y: float, dusk: float) -> void:
	var trim := Color("f4ecd8").lerp(Color("6c6280"), dusk * 0.4)
	if style.shutters:
		for wy in [-hy * 0.6, hy * 0.6]:
			if absf(wy - drive_lat) < 30.0:
				continue
			for side in [-1.0, 1.0]:
				c.draw_rect(Rect2(hx - 9.0, wy + side * 13.0 - 2.5, 7.0, 5.0), style.shutter)
			c.draw_rect(Rect2(hx - 8.0, wy - 8.0, 6.0, 16.0), Color("a8c9d6", 0.55).lerp(Color("2a3550"), dusk * 0.6))
			c.draw_rect(Rect2(hx - 8.0, wy - 8.0, 6.0, 16.0), trim, false, 1.0)
	if style.porch:
		# Porch roof over the front door with two columns.
		DrawUtil.rr(c, Rect2(hx + 6.0, door_y - 22.0, 22.0, 44.0), (style.roof as Color).darkened(0.05).lerp(Color("231c3c"), dusk * 0.35), 3)
		c.draw_rect(Rect2(hx + 6.0, door_y - 22.0, 22.0, 44.0), Color(0, 0, 0, 0.22), false, 1.5)
		for side in [-1.0, 1.0]:
			c.draw_circle(Vector2(hx + 26.0, door_y + side * 19.0), 2.8, trim)
	if style.deck:
		DrawUtil.rr(c, Rect2(-hx - 30.0, -hy * 0.3, 28.0, hy * 0.6), Color("a8825a").lerp(Color("5f5870"), dusk * 0.5), 2)
		for k in range(int(-hy * 0.3) + 4, int(hy * 0.3), 6):
			c.draw_line(Vector2(-hx - 30.0, float(k)), Vector2(-hx - 2.0, float(k)), Color(0, 0, 0, 0.14), 1.0)
		DrawUtil.rr(c, Rect2(-hx - 24.0, -5.0, 10.0, 10.0), Color("c9cdd2"), 5)   # table
	if style.swing:
		var sx := -hx - 44.0
		c.draw_line(Vector2(sx, -hy * 0.6), Vector2(sx, -hy * 0.6 + 26.0), Color("52616f"), 3.0)
		c.draw_line(Vector2(sx + 22.0, -hy * 0.6), Vector2(sx + 22.0, -hy * 0.6 + 26.0), Color("52616f"), 3.0)
		c.draw_line(Vector2(sx, -hy * 0.6 + 4.0), Vector2(sx + 22.0, -hy * 0.6 + 4.0), Color("d94b45"), 3.0)
	# Window glints on the side walls so facades are not blank.
	for wx in [-hx * 0.5, hx * 0.1]:
		c.draw_rect(Rect2(wx, -hy - 1.0, 14.0, 4.0), Color("a8c9d6", 0.8))
		c.draw_rect(Rect2(wx, hy - 3.0, 14.0, 4.0), Color("a8c9d6", 0.8))


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
