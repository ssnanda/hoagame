extends "res://tools/video/video_lib.gd"
## VIDEO 06: the intentional sidewalk-obstruction complaint. Setup (hidden): a hedge on the public sidewalk of a
## nearby house is the complaint; the first-encounter showcase is marked as seen and the related homeowner scene is
## queued (QA hook) so it plays after the warning. Walk, see the obstruction, route around it over the verge,
## inspect, photograph the obstruction (house not centred), preview, ruling, scene. Seed 6066. No teleport while recording.

var house := -1
var obstruction_pos := Vector2.ZERO


func _setup() -> void:
	var spawn: Vector2 = street.spawn_point()
	var best := INF
	for lot in hood.lots:
		if lot.kind != "standard" or lot.side == 0 or main.sim.cases.has(lot.id):
			continue
		var d: float = spawn.distance_to(lot.inspect_anchor())
		if d > 500.0 and d < best:
			best = d
			house = lot.id
	var def: Dictionary = main.sim.violations.get_def("sidewalk_obstruction")
	var item: Dictionary = main.sim.violations.make_allegation(def, 1.0, main.sim.rng, 1)
	item.object = "hedge"
	item.borderline = false
	main.sim.assignments[house] = {"kind": "card", "source": "resident", "complainant": "Neighbor", "violations": [item],
			"false_complaint": false, "status": "assigned", "text": "The hedge has swallowed half the sidewalk. Strollers can't get by."}
	refresh_world(house)
	main.sim.encounters.last_seen["showcase_first"] = 1      # the first-game showcase has already been seen
	main._visited[house] = true                              # no random "visit" scene before the card
	main._photo_scene_done[house] = true                     # ...and none right after the photo
	for e: Dictionary in street.layouts.get(house, []):
		if str(e.id) == "sidewalk_obstruction":
			obstruction_pos = e.pos
	print("VIDEO06 house=", house, " ", hood.lots[house].address, " obstruction=", obstruction_pos)


func _ready() -> void:
	await boot_hidden(6066, true, "VIDEO 06", "SIDEWALK OBSTRUCTION CASE", _setup)
	var lot = hood.lots[house]
	await wait(3.0)
	# Walk along the sidewalk toward the obstruction.
	var t: Vector2 = lot.right()
	var sgn := signf((street.player.position - obstruction_pos).dot(t))
	if sgn == 0.0:
		sgn = 1.0
	var before: Vector2 = obstruction_pos + t * sgn * 130.0
	await walk_to(before, 40.0, 120.0, false, 0.7)
	await wait(2.6)                           # the hedge across the walk
	await pinch(Vector2(360.0, 620.0), 120.0, 280.0, 1.2)
	await wait(2.4)
	# Route around it over the verge (the player can pass; it is an obstruction, not a wall of the world).
	var off: Vector2 = -lot.front * 52.0
	await follow([obstruction_pos + t * sgn * 80.0 + off, obstruction_pos + off, obstruction_pos - t * sgn * 80.0 + off], 0.5, 28.0, 20.0)
	await wait(1.4)
	await tap_hud(street.hud_view.zoom_reset_rect())
	await walk_to(lot.inspect_anchor(), 36.0, 30.0, false, 0.6)
	await wait(2.4)
	await tap(prompt_center())
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(3.0)
	await press("TAKE PHOTO")
	await wait_state("CAMERA", 4.0)
	await wait(3.0)                           # framing targets the sidewalk obstruction, not the house
	await shoot_until_preview()
	await wait(4.0)                           # preview names what was recorded
	await press("USE PHOTO")
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(2.0)
	await press("REVIEW & DECIDE")
	await wait_state("CASE_DECISION", 4.0)
	await wait(4.0)
	main.sim.encounters.force_next = "sidewalk_trimmed"     # the related homeowner scene plays after the warning
	await press("WARNING")
	await wait_state("CINEMATIC", 6.0)
	await play_panel("Offer to recheck Friday")
	await push_direction(Vector2(-0.2, 1.0), 2.4)
	await wait(1.5)
	await finish()
