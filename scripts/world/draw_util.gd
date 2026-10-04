extends RefCounted
## Small shared drawing helpers so every painter uses the same primitives.

static var _box := StyleBoxFlat.new()


static func rr(c: CanvasItem, rect: Rect2, color: Color, radius: int) -> void:
	_box.bg_color = color
	_box.set_corner_radius_all(radius)
	c.draw_style_box(_box, rect)


static func ellipse(c: CanvasItem, center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, color)


## Oriented rectangle: `center`, half extents (along rot, across), heading rot.
static func obb(c: CanvasItem, center: Vector2, half: Vector2, rot: float, color: Color) -> void:
	var ax := Vector2.from_angle(rot) * half.x
	var ay := Vector2.from_angle(rot + PI * 0.5) * half.y
	c.draw_colored_polygon(PackedVector2Array([center + ax + ay, center + ax - ay, center - ax - ay, center - ax + ay]), color)


static func night(color: Color, dusk: float, toward: Color, amount := 0.6) -> Color:
	return color.lerp(toward, dusk * amount)
