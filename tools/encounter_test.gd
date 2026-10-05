extends SceneTree
## Headless check of the encounter catalog and picker:
##   godot --headless --path . --script res://tools/encounter_test.gd
const Encounters := preload("res://scripts/sim/encounters.gd")
const Residents := preload("res://scripts/sim/residents.gd")


func _init() -> void:
	var enc := Encounters.new()
	enc.load_data()
	var problems := 0
	for e: Dictionary in enc.catalog:
		for key in ["id", "trigger", "rarity", "tone", "pose", "lines", "choices"]:
			if not e.has(key):
				print("  %s: missing %s" % [str(e.get("id", "?")), key])
				problems += 1
		if (e.get("lines", []) as Array).is_empty() or (e.get("choices", []) as Array).is_empty():
			print("  %s: needs lines and choices" % str(e.get("id", "?")))
			problems += 1
		if (e.get("choices", []) as Array).size() > 4:
			print("  %s: more than 4 choices will not fit" % str(e.id))
			problems += 1
	print("ENCOUNTERS: %d defined, %d problem(s)" % [enc.catalog.size(), problems])
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var props := Residents.new().create(10)
	var counts := {}
	var plays := 0
	for day in range(2, 402):
		for i in 3:
			var ctx := {"trigger": ["warning", "fine", "dismiss", "reinspect", "hearing"][i], "day": day, "season": day % 4,
					"property": props[day % 10], "fairness_gap": 0.3}
			var pick := enc.pick(ctx, rng)
			if not pick.is_empty():
				enc.mark_played(str(pick.id), day)
				counts[pick.id] = int(counts.get(pick.id, 0)) + 1
				plays += 1
	print("ENCOUNTERS: %d plays over 400 days (%.2f per day)" % [plays, plays / 400.0])
	for id in counts:
		print("  %-24s %d" % [id, counts[id]])
	quit()
