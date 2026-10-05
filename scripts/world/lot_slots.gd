extends RefCounted
## Where violation objects physically sit on a lot. Everything is expressed in the
## lot's own frame so it works for straight streets and wedge-shaped cul-de-sac lots.

const LotScript := preload("res://scripts/world/lot.gd")
const Neighborhood := preload("res://scripts/world/neighborhood.gd")

## Violations that are drawn on the house itself rather than as a yard object.
const HOUSE_IDS := ["paint", "siding", "roof", "addition", "short_rental", "noise"]

## Half extents (forward, sideways) of the object footprint, used for collision.
const HALF := {
	"rv": Vector2(42.0, 22.0), "boat": Vector2(38.0, 17.0), "commercial_vehicle": Vector2(40.0, 22.0),
	"lawn_parking": Vector2(44.0, 24.0), "broken_vehicle": Vector2(44.0, 24.0), "shed": Vector2(15.0, 16.0),
	"curb_bins": Vector2(12.0, 14.0), "hoop": Vector2(12.0, 12.0), "debris": Vector2(24.0, 22.0),
	"dead_tree": Vector2(14.0, 14.0), "sidewalk_obstruction": Vector2(30.0, 14.0),
}


## Lateral sign of the driveway: +1 when it sits on the lot's right side.
static func drive_side(lot: LotScript) -> float:
	var s := signf((lot.driveway_end - lot.center).dot(lot.right()))
	return s if s != 0.0 else 1.0


static func _spot(lot: LotScript, name: String) -> Vector2:
	var ds := drive_side(lot)
	var hx := lot.house_size.x * 0.5
	var hy := lot.house_size.y * 0.5
	match name:
		"driveway":
			return lot.curb.lerp(lot.driveway_end, 0.55)
		"driveway_edge":
			return lot.curb.lerp(lot.driveway_end, 0.18) + lot.right() * ds * (lot.driveway_width * 0.5 + 14.0)
		"curb":
			return lot.curb - lot.front * 14.0 + lot.right() * ds * (lot.driveway_width * 0.5 + 34.0)
		"front_lawn":
			return lot.local_point(hx + 30.0, -ds * (hy - 52.0))
		"front_lawn_curb":
			return lot.local_point(hx + 44.0, -ds * (hy - 32.0))
		"front_beds":
			return lot.local_point(hx + 9.0, -ds * (hy * 0.35))
		"backyard":
			return lot.local_point(-hx - 28.0, -ds * hy * 0.4)
		"back_side":
			return lot.local_point(-hx - 26.0, ds * (hy - 34.0))
		"fence_line":
			return lot.local_point(-8.0, -ds * (hy + 10.0))
		"sidewalk":
			# On the public walk itself, just past the driveway apron, centred across the sidewalk.
			return lot.sidewalk_spot
	return lot.center


## Entries: {id, object, pos, rot, scale, half, on_house}. `rot` is the heading of
## the object's long axis. Only real violations get an object; false complaints show nothing.
static func layout(lot: LotScript, violations: Array) -> Array:
	var result: Array = []
	var along_front := lot.front.angle()
	var along_right := lot.right().angle()
	var drive_dir := (lot.driveway_end - lot.curb).normalized().angle()
	var used: Dictionary = {}
	for v in violations:
		if not bool(v.get("actual", false)):
			continue
		var id := str(v.get("id", ""))
		var object := str(v.get("object", ""))
		var spot := ""
		var rot := along_front
		match id:
			"rv", "commercial_vehicle":
				spot = "driveway"
				rot = drive_dir
			"broken_vehicle":
				spot = "driveway"
				rot = drive_dir
			"lawn_parking":
				spot = "front_lawn"
				rot = along_right
			"boat":
				spot = "back_side"
				rot = along_right
			"shed":
				spot = "backyard"
			"curb_bins":
				spot = "curb"
			"hoop":
				spot = "driveway_edge"
			"yard_sign":
				spot = "front_lawn_curb"
			"decorations", "dog_waste", "tall_grass", "dead_lawn", "landscaping":
				spot = "front_lawn"
			"weeds":
				spot = "front_beds"
			"dead_tree":
				spot = "backyard"
			"trash", "street_parking":
				spot = "curb"
			"business_traffic":
				spot = "driveway_edge"
			"shrubs":
				spot = "front_beds"
			"debris":
				spot = "backyard"
			"fence":
				spot = "fence_line"
			"sidewalk_obstruction":
				spot = "sidewalk"
				rot = along_right
		var on_house := id in HOUSE_IDS
		var pos := lot.center
		if not on_house:
			var key := spot
			var nudge := 0
			while used.has(key) and nudge < 3:
				nudge += 1
				key = "%s%d" % [spot, nudge]
			used[key] = true
			pos = _spot(lot, spot) + lot.right() * 28.0 * float(nudge) * drive_side(lot)
		var half: Vector2 = HALF.get(id, Vector2.ZERO)
		var scale := 0.7 if bool(v.get("borderline", false)) else 1.0
		if id == "sidewalk_obstruction":
			scale *= 1.6      # big enough to read from the street at default zoom
		result.append({"id": id, "object": object, "pos": pos, "rot": rot, "scale": scale,
				"half": half * scale, "on_house": on_house, "violation": v})
	return result


## Oriented-box test used for walking collision.
static func entry_contains(entry: Dictionary, p: Vector2, margin: float) -> bool:
	var half: Vector2 = entry.half
	if half == Vector2.ZERO:
		return false
	var local: Vector2 = (p - (entry.pos as Vector2)).rotated(-float(entry.rot))
	return absf(local.x) <= half.x + margin and absf(local.y) <= half.y + margin
