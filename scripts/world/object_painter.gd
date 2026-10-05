extends RefCounted
## Violation objects, drawn where the lot-slot system placed them.
## Local frame: +x runs along the object's long axis (entry.rot), +y across it.

const DrawUtil := preload("res://scripts/world/draw_util.gd")
const ActorPainter := preload("res://scripts/world/actor_painter.gd")
const LotScript := preload("res://scripts/world/lot.gd")


## Yard objects. `pos` is in the caller's drawing coordinates (world minus camera).
static func yard_object(c: CanvasItem, base: Transform2D, entry: Dictionary, pos: Vector2, dusk: float, time: float) -> void:
	var s: float = entry.scale
	var rot: float = entry.rot
	var id: String = entry.id
	var shade := Color(0, 0, 0, 0.2)
	if id in ["rv", "commercial_vehicle", "broken_vehicle", "lawn_parking"]:
		_vehicle(c, base, id, pos, rot, s, dusk)
		return
	ActorPainter.place(c, base, pos, rot, s)
	match id:
		"tall_grass":
			for k in 9:
				var q := Vector2(sin(k * 2.1) * 20.0, cos(k * 1.7) * 14.0)
				c.draw_line(q, q + Vector2(sin(k) * 4.0, -24.0), Color("d4c54c"), 3.0, true)
		"weeds":
			for k in 7:
				var q := Vector2(-30 + k * 10, sin(k * 2.3) * 5.0)
				c.draw_line(q, q + Vector2(sin(k) * 4.0, -16.0), Color("c9d84a"), 3.0, true)
				c.draw_circle(q + Vector2(0, -17), 3.0, Color("f7e05a"))
		"dead_tree":
			DrawUtil.ellipse(c, Vector2(8, 10), 30.0, 22.0, Color(0, 0, 0, 0.18))
			c.draw_line(Vector2(0, 16), Vector2(0, -8), Color("5b4634"), 10.0, true)
			for k in 7:
				var a := -PI * 0.5 + (k - 3) * 0.5
				var tip := Vector2(0, -8) + Vector2.from_angle(a) * (30.0 + (k % 2) * 8.0)
				c.draw_line(Vector2(0, -8), tip, Color("6b5a4a"), 3.5, true)
				c.draw_line(tip, tip + Vector2.from_angle(a + 0.6) * 10.0, Color("6b5a4a"), 2.0, true)
		"landscaping":
			for k in 6:
				var q := Vector2.from_angle(k * 1.1) * (10.0 + k * 3.0)
				DrawUtil.ellipse(c, q, 9.0, 7.0, Color("9aa0a6"))
				c.draw_circle(q + Vector2(0, -6), 4.0, Color("e0533d"))
				c.draw_circle(q + Vector2(0, -10), 3.0, Color("f2c29b"))
		"trash":
			for k in 4:
				var q := Vector2(-18 + k * 12, sin(k * 2.0) * 7.0)
				DrawUtil.ellipse(c, q, 9.0, 8.0, Color("1f2227"))
				c.draw_line(q + Vector2(-3, -7), q + Vector2(3, -9), Color("1f2227"), 2.0)
		"business_traffic":
			c.draw_line(Vector2(-10, 0), Vector2(0, -26), Color("52616f"), 3.0)
			c.draw_line(Vector2(10, 0), Vector2(0, -26), Color("52616f"), 3.0)
			DrawUtil.rr(c, Rect2(-13, -18, 26, 14), Color("f7f3e8"), 2)
			c.draw_line(Vector2(-8, -11), Vector2(8, -11), Color("c4543e"), 2.0)
		"dead_lawn":
			DrawUtil.ellipse(c, Vector2.ZERO, 32.0, 24.0, Color("a38b48"))
			DrawUtil.ellipse(c, Vector2(8, 4), 14.0, 10.0, Color("7d6a38"))
		"dog_waste":
			for k in 4:
				c.draw_circle(Vector2(-16 + k * 11, sin(k * 3.0) * 12.0), 4.0, Color("6b4a2a"))
		"curb_bins":
			for b in 2:
				var bc := Vector2(0, -11 + b * 22)
				DrawUtil.rr(c, Rect2(bc - Vector2(11, 9), Vector2(22, 18)), Color("315b74") if b == 0 else Color("3f7654"), 3)
				c.draw_line(bc + Vector2(-9, -6), bc + Vector2(-9, 6), Color("1d2d35"), 3.0)
		"boat":
			DrawUtil.ellipse(c, Vector2(6, 8), 40.0, 22.0, shade)
			c.draw_colored_polygon(PackedVector2Array([Vector2(-34, -14), Vector2(8, -17), Vector2(40, 0), Vector2(8, 17), Vector2(-34, 14)]), Color("e8ecef"))
			c.draw_polyline(PackedVector2Array([Vector2(-34, -14), Vector2(8, -17), Vector2(40, 0), Vector2(8, 17), Vector2(-34, 14), Vector2(-34, -14)]), Color("2f5d8a"), 3.0)
			DrawUtil.rr(c, Rect2(-8, -9, 20, 18), Color("2f5d8a"), 3)
			c.draw_line(Vector2(-44, 0), Vector2(-34, 0), Color("52616f"), 3.0)
		"shed":
			DrawUtil.rr(c, Rect2(-15, -16, 30, 32), Color("9a6d45"), 3)
			c.draw_line(Vector2(0, -16), Vector2(0, 16), Color("6f4a2c"), 2.0)
			DrawUtil.rr(c, Rect2(13, -5, 4, 10), Color("5b3d26"), 1)
		"fence":
			for k in 9:
				c.draw_rect(Rect2(-50.5 + k * 12, -2.5, 5, 5), Color("efe0bd"))
			c.draw_line(Vector2(-48, 0), Vector2(48, 0), Color("cbb995"), 2.0)
		"hoop":
			c.draw_circle(Vector2.ZERO, 5.0, Color("52616f"))
			c.draw_line(Vector2.ZERO, Vector2(0, -24), Color("52616f"), 4.0)
			DrawUtil.rr(c, Rect2(-13, -34, 26, 8), Color("f4f4f4"), 2)
			c.draw_circle(Vector2(0, -24), 5.0, Color("e07a1f"), false, 2.5)
		"yard_sign":
			c.draw_line(Vector2(0, 0), Vector2(0, -22), Color("5b4634"), 3.0)
			DrawUtil.rr(c, Rect2(-14, -38, 28, 18), Color("e0533d"), 3)
			c.draw_line(Vector2(-8, -29), Vector2(8, -29), Color.WHITE, 2.0)
		"decorations":
			DrawUtil.ellipse(c, Vector2.ZERO, 16.0, 20.0, Color("d94b45"))
			c.draw_circle(Vector2(0, -22), 8.0, Color("f2c29b"))
			for k in 6:
				c.draw_circle(Vector2(-25 + k * 10, 24), 3.0, [Color("ffd36e"), Color("ff6b5a"), Color("7ee081")][k % 3])
				if dusk > 0.1:
					c.draw_circle(Vector2(-25 + k * 10, 24), 6.0, Color(1, 0.9, 0.5, 0.25 * dusk))
		"shrubs":
			for k in 5:
				DrawUtil.ellipse(c, Vector2(-40 + k * 20, sin(k * 2.0) * 6.0), 25.0, 21.0, Color("1f6b43").lightened(k * 0.04))
				c.draw_circle(Vector2(-40 + k * 20, sin(k * 2.0) * 6.0 - 6.0), 9.0, Color("2f8a52"))
		"sidewalk_obstruction":
			_sidewalk_obstruction(c, str(entry.get("object", "hedge")))
		"debris":
			DrawUtil.rr(c, Rect2(-24, -20, 48, 40), Color("d9822b"), 3)
			c.draw_rect(Rect2(-24, -20, 48, 40), Color("8a4f12"), false, 2.0)
			for k in 4:
				c.draw_circle(Vector2(-14 + k * 9, -4 + (k % 2) * 8), 5.0, Color("6b5a4a"))
			c.draw_line(Vector2(28, -10), Vector2(44, -4), Color("8a6747"), 5.0)
	c.draw_set_transform_matrix(base)


## What is in the way of the public sidewalk. +x runs along the walk, +y across it.
static func _sidewalk_obstruction(c: CanvasItem, variant: String) -> void:
	match variant:
		"branch":
			c.draw_line(Vector2(-34, 18), Vector2(0, -2), Color("6b4a35"), 6.0, true)
			c.draw_line(Vector2(-8, 4), Vector2(30, -14), Color("6b4a35"), 4.0, true)
			c.draw_line(Vector2(-14, 8), Vector2(22, 16), Color("6b4a35"), 3.0, true)
			for k in 9:
				DrawUtil.ellipse(c, Vector2(-20 + k * 7.0, -8.0 + sin(k * 1.9) * 12.0), 9.0, 7.0, Color("2f8a52").lightened(0.04 * (k % 3)))
		"bins":
			for k in 2:
				DrawUtil.rr(c, Rect2(-24 + k * 26, -13, 20, 26), Color("3a6f4a") if k == 0 else Color("2f4858"), 4)
				c.draw_rect(Rect2(-26 + k * 26, -15, 24, 5), Color("20252b"))
		"debris":
			DrawUtil.rr(c, Rect2(-28, -12, 56, 24), Color("a8825a"), 3)
			for k in 3:
				c.draw_line(Vector2(-26, -8 + k * 8), Vector2(26, -6 + k * 8), Color("6b4a35"), 2.0)
			DrawUtil.ellipse(c, Vector2(30, 6), 9.0, 7.0, Color("20252b"))
		"materials":
			for row in 2:
				for col in 4:
					c.draw_rect(Rect2(-28 + col * 14, -12 + row * 12, 12, 10), Color("b9573a") if (row + col) % 2 == 0 else Color("a24a30"))
			c.draw_rect(Rect2(-30, -14, 60, 28), Color("5a3a28"), false, 2.0)
		_:
			# Overgrown hedge spilling across the walk.
			for k in 6:
				DrawUtil.ellipse(c, Vector2(-30 + k * 12.0, sin(k * 2.0) * 4.0), 15.0, 14.0, Color("1f6b43").lightened(k * 0.03))
			for k in 5:
				c.draw_circle(Vector2(-26 + k * 12.0, -6.0 + sin(k * 1.7) * 6.0), 6.0, Color("3a9a5a"))


static func _vehicle(c: CanvasItem, base: Transform2D, id: String, pos: Vector2, rot: float, s: float, dusk: float) -> void:
	match id:
		"rv", "commercial_vehicle":
			ActorPainter.place(c, base, pos, rot, s)
			var rv := id == "rv"
			DrawUtil.ellipse(c, Vector2(7, 9), 46.0, 26.0, Color(0, 0, 0, 0.2))
			DrawUtil.rr(c, Rect2(-42, -22, 84, 44), Color("f0eee6") if rv else Color("f2b632"), 7)
			DrawUtil.rr(c, Rect2(26, -17, 14, 34), Color("8fb8cf"), 4)
			if rv:
				c.draw_line(Vector2(-42, 4), Vector2(26, 4), Color("c4543e"), 5.0)
				DrawUtil.rr(c, Rect2(-24, -12, 20, 24), Color("d8d4c8"), 3)
			else:
				for k in 3:
					c.draw_line(Vector2(-34 + k * 18, -22), Vector2(-34 + k * 18, 22), Color("6b6b6b"), 2.0)
				DrawUtil.rr(c, Rect2(-34, -7, 40, 14), Color("1c1b1f"), 3)
				c.draw_line(Vector2(-34, 0), Vector2(6, 0), Color("f2b632"), 3.0)
			c.draw_set_transform_matrix(base)
		"broken_vehicle":
			ActorPainter.place(c, base, pos, rot + PI * 0.5, 0.82 * s)
			ActorPainter.car(c, Color("767c86"), dusk)
			DrawUtil.rr(c, Rect2(-19, -38, 38, 18), Color("55595f"), 3)   # hood up
			c.draw_line(Vector2(-27, 20), Vector2(-27, 34), Color("e0533d"), 4.0)   # flat tire
			c.draw_set_transform_matrix(base)
		_:
			ActorPainter.place(c, base, pos, rot + PI * 0.5, 0.82 * s)
			ActorPainter.car(c, Color("3a6fd8"), dusk)
			c.draw_set_transform_matrix(base)
			for k in 2:
				var p := pos + Vector2.from_angle(rot + PI * 0.5) * (-14.0 + k * 28.0)
				c.draw_line(p - Vector2.from_angle(rot) * 70.0, p + Vector2.from_angle(rot) * 70.0, Color(0.2, 0.15, 0.08, 0.35), 5.0)


## Violations that live on the house itself. Drawn in the house's local frame
## (origin at its center, +x toward the street, +y across the frontage).
static func house_object(c: CanvasItem, entry: Dictionary, lot: LotScript, time: float) -> void:
	var dx := lot.house_size.x
	var dy := lot.house_size.y
	var s: float = entry.scale
	match str(entry.id):
		"paint":
			c.draw_rect(Rect2(-dx * 0.5, -dy * 0.5, dx, dy * 0.42 * s), Color("d94fb5", 0.82))
		"roof":
			DrawUtil.rr(c, Rect2(-dx * 0.2, -dy * 0.35, dx * 0.45, dy * 0.4 * s), Color("2f6fb8"), 2)
			for k in 3:
				c.draw_line(Vector2(-dx * 0.2, -dy * 0.35 + k * dy * 0.14 * s), Vector2(dx * 0.25, -dy * 0.35 + k * dy * 0.14 * s), Color("1d4d86"), 1.5)
		"siding":
			for k in 3:
				var q := Vector2(-dx * 0.3 + k * dx * 0.25, -dy * 0.3 + k * dy * 0.2)
				c.draw_rect(Rect2(q, Vector2(24, 16) * s), Color("2b2622"))
				c.draw_line(q, q + Vector2(30, -14) * s, Color("2b2622"), 2.0)
		"addition":
			var back := -dx * 0.5 - 24.0
			c.draw_rect(Rect2(back - 24.0, -dy * 0.3 * s, 48.0, dy * 0.6 * s), Color("c9b48a"))
			c.draw_rect(Rect2(back - 24.0, -dy * 0.3 * s, 48.0, dy * 0.6 * s), Color("7a6a44"), false, 3.0)
			for k in 4:
				c.draw_line(Vector2(back - 24.0, -dy * 0.3 * s + k * dy * 0.2 * s), Vector2(back + 24.0, -dy * 0.3 * s + k * dy * 0.2 * s), Color("8a6747"), 2.0)
		"short_rental":
			# Lockbox on the door and luggage by the step; extra cars are drawn at the curb.
			var door_y := -signf((lot.driveway_end - lot.center).dot(lot.right())) * dy * 0.35
			DrawUtil.rr(c, Rect2(dx * 0.5 + 4.0, door_y + 10.0, 8, 8), Color("2f2f33"), 2)
			DrawUtil.rr(c, Rect2(dx * 0.5 + 10.0, door_y - 20.0, 10, 14), Color("2f5d8a"), 2)
			DrawUtil.rr(c, Rect2(dx * 0.5 + 12.0, door_y - 4.0, 8, 12), Color("a33a2f"), 2)
		"noise":
			for k in 3:
				c.draw_arc(Vector2(0, 0), 26.0 + k * 14.0 + sin(time * 5.0 + k) * 3.0, -0.9, 0.9, 10, Color("ffd36e", 0.8 - k * 0.22), 3.0)
			DrawUtil.rr(c, Rect2(-dx * 0.5 - 14.0, -10, 10, 20), Color("2b2e36"), 2)
