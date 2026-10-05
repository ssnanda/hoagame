extends SceneTree
## Headless layout check:
##   godot --headless --path . --script res://tools/validate_world.gd
const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotSlots := preload("res://scripts/world/lot_slots.gd")
const Violations := preload("res://scripts/sim/violations.gd")


func _init() -> void:
	var hood = Neighborhood.new()
	var started := Time.get_ticks_msec()
	hood.build()
	print("WORLD: %d streets, %d lots, built in %d ms" % [hood.streets.size(), hood.lots.size(), Time.get_ticks_msec() - started])
	var counts := {}
	for lot in hood.lots:
		counts[lot.kind] = int(counts.get(lot.kind, 0)) + 1
	print("WORLD: lots by kind %s" % str(counts))
	var warnings: Array = hood.validate()
	print("WORLD VALIDATION: %d warning(s)" % warnings.size())
	for w in warnings.slice(0, 60):
		print("  ", w)
	var spawn := Vector2(hood.spine_x(6900.0) - (hood.AVENUE_HALF + hood.WALK_W * 0.5), 6900.0)
	var unreachable: Array = hood.unreachable_lots(spawn)
	print("WORLD REACHABILITY: %d lot(s) unreachable on foot %s" % [unreachable.size(), str(unreachable)])
	# Every violation object must land on (or at the curb of) its own lot.
	var viol := Violations.new()
	viol.load_data()
	var rng := RandomNumberGenerator.new()
	var outside := 0
	for lot in hood.lots:
		for def in viol.catalog:
			var item := viol.make_allegation(def, 1.0, rng, 1)
			for entry in LotSlots.layout(lot, [item]):
				if entry.on_house:
					continue
				var inside := Geometry2D.is_point_in_polygon(entry.pos, lot.polygon)
				var edge_gap := 0.0
				if not inside:
					edge_gap = 1e9
					for i in lot.polygon.size():
						edge_gap = minf(edge_gap, Geometry2D.get_closest_point_to_segment(entry.pos, lot.polygon[i], lot.polygon[(i + 1) % lot.polygon.size()]).distance_to(entry.pos))
				if not inside and edge_gap > 36.0:
					outside += 1
					if outside <= 12:
						print("  Lot %d: %s object %d px outside the lot" % [lot.id, item.id, edge_gap])
	print("WORLD SLOTS: %d violation object(s) outside their lot" % outside)
	quit()
