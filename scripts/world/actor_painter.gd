extends RefCounted
## Vehicles and people. Everything is drawn around the origin and placed with a
## draw transform so it can face any direction.

const DrawUtil := preload("res://scripts/world/draw_util.gd")


## Draw transform that puts the local origin at `pos` (in the caller's coordinate
## system), rotated by `rot`, scaled by `k`, on top of the view's base transform.
static func place(c: CanvasItem, base: Transform2D, pos: Vector2, rot: float, k: float) -> void:
	c.draw_set_transform_matrix(base * Transform2D(rot, Vector2(k, k), 0.0, pos))


static func car(c: CanvasItem, color: Color, dusk: float) -> void:
	var body := color.lerp(Color("111522"), dusk * 0.4)
	var glass := Color("bfe2f5").lerp(Color("303b55"), dusk * 0.65)
	DrawUtil.ellipse(c, Vector2(7, 8), 29.0, 49.0, Color(0, 0, 0, 0.24))
	for wheel in [Vector2(-27, -29), Vector2(19, -29), Vector2(-27, 12), Vector2(19, 12)]:
		DrawUtil.rr(c, Rect2(wheel, Vector2(8, 22)), Color("171b24"), 3)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-21, -45), Vector2(21, -45), Vector2(25, -31), Vector2(25, 33),
			Vector2(20, 45), Vector2(-20, 45), Vector2(-25, 33), Vector2(-25, -31)]), body.darkened(0.12))
	DrawUtil.rr(c, Rect2(-21, -39, 42, 77), body, 11)
	DrawUtil.rr(c, Rect2(-17, -25, 34, 48), body.lightened(0.16), 8)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-17, -23), Vector2(-13, -17), Vector2(-13, 17), Vector2(-17, 22)]), body.darkened(0.16))
	DrawUtil.rr(c, Rect2(-13, -20, 26, 15), glass, 4)
	DrawUtil.rr(c, Rect2(-13, 7, 26, 12), glass.darkened(0.08), 4)
	c.draw_line(Vector2(-16, -34), Vector2(13, -34), body.lightened(0.38), 2.0, true)
	c.draw_circle(Vector2(-14, -39), 3.0, Color("fff1b0"))
	c.draw_circle(Vector2(14, -39), 3.0, Color("fff1b0"))
	c.draw_circle(Vector2(-14, 38), 2.8, Color("d94b45"))
	c.draw_circle(Vector2(14, 38), 2.8, Color("d94b45"))


static func truck(c: CanvasItem, kind: String) -> void:
	var delivery := kind == "delivery"
	var body := Color("e8e1d0") if delivery else Color("2f9e57")
	var accent := Color("8a5a34") if delivery else Color("1c5a3e")
	var length := 56.0
	DrawUtil.ellipse(c, Vector2(7, 8), 28.0, length + 4.0, Color(0, 0, 0, 0.24))
	DrawUtil.rr(c, Rect2(-22, -length, 44, 32), accent, 8)
	DrawUtil.rr(c, Rect2(-16, -length + 4, 32, 12), Color("bfe2f5"), 3)
	DrawUtil.rr(c, Rect2(-23, -length + 30, 46, length * 2.0 - 30), body, 5)
	if delivery:
		c.draw_line(Vector2(-23, 4), Vector2(23, 4), accent, 6.0)
		c.draw_string(ThemeDB.fallback_font, Vector2(-20, 30), "PKG", HORIZONTAL_ALIGNMENT_CENTER, 40.0, 14, accent)
	else:
		DrawUtil.rr(c, Rect2(-18, length - 14, 36, 12), Color("1c2b24"), 3)
		c.draw_circle(Vector2(0, 10), 10.0, Color("1c5a3e"), false, 3.0)


static func golf_cart(c: CanvasItem) -> void:
	DrawUtil.ellipse(c, Vector2(6, 10), 26.0, 36.0, Color(0, 0, 0, 0.22))
	for wheel in [Vector2(-22, -22), Vector2(22, -22), Vector2(-22, 24), Vector2(22, 24)]:
		DrawUtil.rr(c, Rect2(wheel - Vector2(4, 9), Vector2(8, 18)), Color("171b24"), 2)
	DrawUtil.rr(c, Rect2(-20, -34, 40, 70), Color("f4ecd8"), 10)
	DrawUtil.rr(c, Rect2(-18, 4, 36, 26), Color("2f9e57"), 6)
	DrawUtil.rr(c, Rect2(-22, -38, 44, 8), Color("4a4f58"), 4)


## Pedestrian from above: shirt, head and gait.
static func person(c: CanvasItem, tone: int, time: float, speed: float) -> void:
	var bob := sin(time * speed * 0.12) * 2.0
	var shirts := [Color("e05a47"), Color("477bd1"), Color("e6ad3b"), Color("8c5fa8")]
	var skins := [Color("f2c29b"), Color("9b6547"), Color("d89b73"), Color("6f4635")]
	DrawUtil.ellipse(c, Vector2(3, 11), 10.0, 7.0, Color(0, 0, 0, 0.16))
	c.draw_line(Vector2(-5, 7), Vector2(-7, 17 + bob), Color("253044"), 4.0, true)
	c.draw_line(Vector2(5, 7), Vector2(7, 17 - bob), Color("253044"), 4.0, true)
	DrawUtil.ellipse(c, Vector2.ZERO, 10.0, 13.0, shirts[tone % 4])
	c.draw_circle(Vector2(0, -13), 7.0, skins[tone % 4])


static func dog(c: CanvasItem, tone: int) -> void:
	var fur: Color = [Color("c78a4b"), Color("e7d2aa"), Color("6b4a34"), Color("b6a39a")][tone % 4]
	DrawUtil.ellipse(c, Vector2.ZERO, 11.0, 7.0, fur)
	c.draw_circle(Vector2(10, -4), 6.0, fur.lightened(0.08))
	c.draw_colored_polygon(PackedVector2Array([Vector2(7, -8), Vector2(5, -15), Vector2(11, -9)]), fur.darkened(0.18))
	c.draw_line(Vector2(-8, 3), Vector2(-13, 10), fur.darkened(0.15), 3.0, true)
	c.draw_line(Vector2(7, 3), Vector2(9, 10), fur.darkened(0.15), 3.0, true)
	c.draw_line(Vector2(-10, -2), Vector2(-15, -9), fur, 3.0, true)


## The inspector: suit, briefcase and a little head from above.
static func inspector(c: CanvasItem, variant: int, swing: float) -> void:
	var suits := [Color("23304a"), Color("3f315f"), Color("28544b"), Color("65412f")]
	var skins := [Color("f2c29b"), Color("9b6547"), Color("d89b73"), Color("6f4635")]
	var hairs := [Color("2b2118"), Color("141923"), Color("80552f"), Color("d7c2a1")]
	var suit: Color = suits[variant]
	c.draw_circle(Vector2(-8, swing * 12.0 + 4.0), 6.5, Color("0d1220"))
	c.draw_circle(Vector2(8, -swing * 12.0 + 4.0), 6.5, Color("0d1220"))
	c.draw_line(Vector2(-16, 0), Vector2(-19, swing * 11.0 + 4.0), suit.lightened(0.1), 6.0, true)
	var hand := Vector2(19, -swing * 10.0 + 4.0)
	c.draw_line(Vector2(16, 0), hand, suit, 6.0, true)
	c.draw_rect(Rect2(hand + Vector2(-1, -9 + absf(swing) * 3.0), Vector2(12, 24)), Color("8a5a34"))
	DrawUtil.ellipse(c, Vector2.ZERO, 18.0, 11.0, suit)
	c.draw_line(Vector2(0, -6), Vector2(0, 6), Color("e0533d"), 3.0)
	c.draw_circle(Vector2(0, -2), 11.0, skins[variant])
	c.draw_arc(Vector2(0, -2), 11.0, 0.0, PI, 14, hairs[variant], 7.0, true)
	if variant == 1:
		c.draw_line(Vector2(-8, -1), Vector2(8, -1), Color("20283a"), 2.0)
	elif variant == 2:
		c.draw_circle(Vector2(-5, -2), 2.0, Color("20283a"))
		c.draw_circle(Vector2(5, -2), 2.0, Color("20283a"))
