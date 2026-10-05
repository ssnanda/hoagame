extends "res://tools/video/video_lib.gd"
## VIDEO 05: reinspection through the real UI. Setup (hidden): a warning was issued days ago on a house about
## 900-1500 px away and its cure period just ended, so a REINSPECTION assignment exists. Recording starts
## before the walk: blue circular-arrow marker, Next chip, walk, INSPECT, card, panel, Back, reopen, optional photo,
## a real decision, back to the world. Seed 5055. No teleport while recording.

var house := -1


func _setup() -> void:
	var spawn: Vector2 = street.spawn_point()
	var pick := -1
	for h in main.sim.assignments:
		var d: float = spawn.distance_to(hood.lots[int(h)].inspect_anchor())
		if d > 800.0 and d < 1700.0:
			pick = int(h)
			break
	if pick < 0:
		pick = int(main.sim.assignments.keys()[0])
	house = pick
	var a: Dictionary = main.sim.assignments[house]
	var cited: Array = []
	for v in a.violations:
		cited.append(str(v.id))
	main.sim.rule_case(house, "warning", cited, {})
	for h in main.sim.cases:
		main.sim.cases[h].cure_due = GameState.day          # cure period ends this morning
	GameState.next_day()
	main._new_day()                                           # the morning sweep creates the reinspection
	main._morning_queue.clear()
	main._close_overlay()
	await wait(0.4)
	street.select_objective(house)
	print("VIDEO05 house=", house, " kind=", main.sim.assignments[house].kind, " result=", main.sim.assignments[house].get("result", ""))


func _ready() -> void:
	await boot_hidden(5055, true, "VIDEO 05", "REINSPECTION - FULL FLOW", _setup)
	main.sim.encounters.catalog = []
	await wait(3.5)                      # blue circular-arrow marker, Next chip says REINSPECTION, arrow, minimap
	await walk_to(hood.lots[house].inspect_anchor(), 40.0, 120.0, false, 0.75)
	await wait(3.0)
	await tap(prompt_center())           # the HUD button says REINSPECT
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(3.0)                      # card: "Cure period ended. Check whether the notice was addressed." primary INSPECT
	await press("INSPECT")
	await wait_state("CASE_DECISION", 4.0)
	await wait(3.5)                      # reinspection panel: what the walk-through found
	await press("< BACK")                # Back works
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(2.0)
	# Photo evidence too, the same way as a complaint.
	await press("TAKE PHOTO")
	await wait_state("CAMERA", 4.0)
	await wait(2.0)
	await shoot_until_preview()
	await wait(2.4)
	await press("USE PHOTO")
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(2.0)
	await press("INSPECT")
	await wait_state("CASE_DECISION", 4.0)
	await wait(3.0)
	# A real decision. Prefer closing a fixed case; otherwise extend.
	for label in ["CLOSE CASE", "EXTEND 2 DAYS", "SCHEDULE HEARING"]:
		if has_button(label):
			await press(label)
			break
	await wait_state("WORLD", 6.0)
	await wait(3.0)
	await push_direction(Vector2(0.3, 1.0), 2.4)       # control is back
	await wait(1.5)
	await finish()
