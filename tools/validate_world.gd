extends SceneTree
## Headless layout check:
##   godot --headless --path . --script res://tools/validate_world.gd
const Neighborhood := preload("res://scripts/world/neighborhood.gd")


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
	quit()
