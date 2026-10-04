extends Control
## Developer view of the neighborhood geometry: roads, lots, footprints,
## driveways and property ids. Used by the layout QA tools; never shown in play.

const ROOFS := [Color("c4543e"), Color("5b6f8f"), Color("8a6f56"), Color("4f7f6a"), Color("805b73"), Color("b77945")]

var hood
var world_scale := 0.25
var show_ids := false


func _draw() -> void:
	var k := world_scale
	draw_rect(Rect2(Vector2.ZERO, size), Color("58a86f"))
	for mark in hood.landmarks:
		var r: Rect2 = mark.rect
		var color: Color = {"park": Color("8fd18b"), "woods": Color("2f7a4a"), "clubhouse": Color("d8c6a3"),
				"lake": Color("4aa9c7"), "pond": Color("4aa9c7")}.get(str(mark.type), Color.GRAY)
		if str(mark.type) in ["lake", "pond"]:
			_ellipse(r.get_center() * k, r.size * 0.5 * k, color)
		else:
			draw_rect(Rect2(r.position * k, r.size * k), color)
	for pass_i in 2:
		var color := Color("d7d9d5") if pass_i == 0 else Color("414a56")
		for street in hood.streets:
			var extra: float = hood.WALK_W if pass_i == 0 else 0.0
			var pts := PackedVector2Array()
			for p in street.path:
				pts.append(p * k)
			draw_polyline(pts, color, (street.half + extra) * 2.0 * k, true)
			for bulb in street.bulbs:
				draw_circle(bulb.center * k, (hood.BULB_R + extra) * k, color)
	for lot in hood.lots:
		var poly := PackedVector2Array()
		for p in lot.polygon:
			poly.append(p * k)
		draw_polyline(poly + PackedVector2Array([poly[0]]), Color(1, 1, 1, 0.55), 1.0)
		var fp := PackedVector2Array()
		for p in lot.footprint():
			fp.append(p * k)
		draw_colored_polygon(fp, ROOFS[lot.archetype % ROOFS.size()])
		draw_line(lot.curb * k, lot.driveway_end * k, Color("b8b3a8"), lot.driveway_width * k)
		draw_circle(lot.mailbox * k, 2.0, Color("ffd36e"))
		draw_line(lot.center * k, (lot.center + lot.front * 30.0) * k, Color.WHITE, 1.0)
		if show_ids:
			draw_string(ThemeDB.fallback_font, lot.center * k, str(lot.id), HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.BLACK)
		for tree in lot.trees:
			draw_circle(Vector2(tree.x, tree.y) * k, tree.z * k, Color("1f6b43", 0.8))
	for tree in hood.street_trees:
		draw_circle(Vector2(tree.x, tree.y) * k, tree.z * k, Color("1f6b43", 0.9))
	for tree in hood.woods_trees:
		draw_circle(Vector2(tree.x, tree.y) * k, tree.z * k, Color("154d30", 0.9))


func _ellipse(c: Vector2, r: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		pts.append(c + Vector2(cos(TAU * i / 32.0) * r.x, sin(TAU * i / 32.0) * r.y))
	draw_colored_polygon(pts, color)
