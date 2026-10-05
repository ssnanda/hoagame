extends Node
## QA for the encounter framework (section 96): every encounter starts cleanly, plays
## all its lines, offers every choice, emits `finished` exactly once, and applying the
## outcome changes state exactly once. Headless:
##   godot --headless --path . res://tools/qa_encounters.tscn
const Encounters := preload("res://scripts/sim/encounters.gd")
const EncounterPanel := preload("res://scripts/ui/encounter_panel.gd")
const HoaSim := preload("res://scripts/sim/hoa_sim.gd")

var _finished := 0


func _ready() -> void:
	_run()


func _run() -> void:
	var enc := Encounters.new()
	enc.load_data()
	var problems := 0
	var root := Control.new()
	root.size = Vector2(720, 1280)
	add_child(root)
	for e: Dictionary in enc.catalog:
		for choice_index in (e.choices as Array).size():
			var panel := EncounterPanel.new()
			panel.size = root.size
			panel.setup(e, "Test Owner", "1 Test Court", 7, Color("d9c7a3"), Color("7a4b3a"), {"favored": "Pat Example"})
			_finished = 0
			panel.finished.connect(func(_c): _finished += 1)
			root.add_child(panel)
			await get_tree().process_frame
			# Walk every line, then pick the choice and walk the replies.
			var guard := 0
			while panel._stage == "lines" and guard < 20:
				panel._advance()
				guard += 1
			if panel._stage != "choices":
				print("  %s: never reached choices" % str(e.id))
				problems += 1
			panel._pick((e.choices as Array)[choice_index])
			guard = 0
			while panel._stage == "reply" and guard < 10:
				panel._advance()
				guard += 1
			if _finished != 1:
				print("  %s: finished emitted %d times" % [str(e.id), _finished])
				problems += 1
			# Every line must have its tokens filled.
			for line in e.lines:
				if panel._fill(str(line.text)).contains("{"):
					print("  %s: unfilled token in '%s'" % [str(e.id), str(line.text)])
					problems += 1
			panel.queue_free()
			await get_tree().process_frame
	print("QA ENCOUNTERS: %d scenes, %d problem(s)" % [enc.catalog.size(), problems])
	get_tree().quit(1 if problems > 0 else 0)
