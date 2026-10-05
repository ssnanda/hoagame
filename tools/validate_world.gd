extends SceneTree
## Headless layout check:
##   godot --headless --path . --script res://tools/validate_world.gd
const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotSlots := preload("res://scripts/world/lot_slots.gd")
const Violations := preload("res://scripts/sim/violations.gd")


func _init() -> void:
	# Optional: -- seeds=25 sweeps seeds 1..25 and reports layout warnings per seed.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seeds="):
			_sweep(int(arg.substr(6)))
			quit()
			return
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
	var probe = Neighborhood.new()
	probe.build()
	probe.street_trees.append(Vector3(probe.lots[0].inspect_anchor().x, probe.lots[0].inspect_anchor().y, 24.0))
	var probe_warnings: Array = probe.validate()
	var caught := false
	for w in probe_warnings:
		caught = caught or "covers" in str(w) or "blocks the sidewalk" in str(w)
	print("WORLD SELF-TEST: validator %s a tree dropped on an inspection anchor" % ("catches" if caught else "MISSES"))
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
				if item.id == "sidewalk_obstruction":
					# Belongs ON the public sidewalk of its own street (not inside the lot).
					var ed: float = hood.edge_distance(entry.pos, -1, lot.street_id)
					if ed < -4.0 or ed > hood.WALK_W + 6.0:
						outside += 1
						print("  Lot %d: sidewalk obstruction is %d px from the sidewalk" % [lot.id, int(ed)])
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
	# Parked cars, crews and visitor cars must never seal a property's public inspection point.
	var Ambient := preload("res://scripts/world/ambient.gd")
	var sealed := 0
	for day in range(1, 29):
		var amb = Ambient.new()
		amb.setup(hood, day, (day - 1) % 7, {}, ((day - 1) / 14) % 4, 1.0)
		for entry: Dictionary in amb.obstacles():
			for lot in hood.lots:
				if absf(lot.center.y - (entry.pos as Vector2).y) > 400.0:
					continue
				for spot in [lot.inspect_anchor(), lot.mailbox]:
					if LotSlots.entry_contains(entry, spot, 4.0):
						sealed += 1
						if sealed <= 8:
							print("  Lot %d (%s): %s covers its %s on day %d" % [lot.id, lot.address, str(entry.get("src", "?")), "mailbox" if spot == lot.mailbox else "inspection anchor", day])
	print("WORLD ACCESS: %d vehicle(s) cover an inspection anchor or mailbox over 28 days" % sealed)
	quit()



func _sweep(count: int) -> void:
	var bad := 0
	for seed_value in range(1, count + 1):
		var hood = Neighborhood.new()
		hood.build(seed_value)
		var warnings: Array = hood.validate()
		if not warnings.is_empty():
			bad += 1
			print("SEED %d: %d warning(s), first: %s" % [seed_value, warnings.size(), warnings[0]])
	print("SEED SWEEP: %d of %d seeds had layout warnings" % [bad, count])
