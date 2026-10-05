extends Node
## Save/resume and migration check. Run in a throwaway project copy:
##   godot --headless --path . res://tools/resume_test.tscn

const MainScene := preload("res://scenes/main.tscn")


func _make_main() -> Node:
	var main := MainScene.instantiate()
	add_child(main)
	for i in 8:
		await get_tree().process_frame
	return main


func _ready() -> void:
	Settings.tutorial_done = true      # skip the one-time intro modal
	var failures := 0
	# 1. Round trip: play a little, save, reload in a fresh instance.
	var a: Node = await _make_main()
	GameState.clear_run()
	a._begin(false)
	for i in 4:
		await get_tree().process_frame
	var house: int = a.sim.assignments.keys()[0]
	a._street.player.position = a._street.hood.lots[house].inspect_anchor()
	a._save_progress()
	var before: int = a.sim.assignments.size()
	var day := GameState.day
	a.queue_free()
	await get_tree().process_frame
	GameState.has_saved_run = true
	GameState._load_save()
	var b: Node = await _make_main()
	b._begin(true)
	for i in 4:
		await get_tree().process_frame
	if b.sim.assignments.size() != before or GameState.day != day:
		print("RESUME: FAIL round trip (%d vs %d assignments)" % [b.sim.assignments.size(), before])
		failures += 1
	else:
		print("RESUME: round trip ok (%d assignments, day %d)" % [before, day])
	b.queue_free()
	await get_tree().process_frame
	# 2. Old world versions load without errors.
	for version in [3, 5, 6, 8]:
		var old_world := {"world_version": version, "complaints": {2: {"kind": "card", "card": {"text": "Old complaint"}, "violations": [{"id": "rv", "label": "RV", "actual": true, "borderline": false, "severity": 2, "object": "rv"}]}},
				"grass": [3.0, 3.0], "completed": [], "phase": "street", "evidence": {2: {"path": "x.png", "time": "t", "quality": 70, "documented": ["rv"], "shots": 1}},
				"properties": {2: {"owner": "Old Owner", "relationship": "critic", "repeat_count": 1, "history": [], "compliance": 60}},
				"cases": {2: {"state": "warning", "cure_due": 1, "violations": []}}, "politics": {"board": [{"name": "X", "support": 50}], "legal": 5, "enforce": {"critic": {"cases": 1, "enforced": 1, "missed": 0}}},
				"projects": []}
		GameState.save_run(old_world)
		var c: Node = await _make_main()
		c._begin(true)
		for i in 6:
			await get_tree().process_frame
		var ok: bool = c.sim.assignments.size() > 0 and c._street.house_count() > 0
		print("RESUME: world_version %d %s" % [version, "ok" if ok else "FAIL"])
		if not ok:
			failures += 1
		c.queue_free()
		await get_tree().process_frame
	print("RESUME: %d failure(s)" % failures)
	get_tree().quit()
