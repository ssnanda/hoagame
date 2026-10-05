extends "res://tools/video/video_lib.gd"
## VIDEO 04: try to get stuck. At a complaint property: inspect, camera, cancel, retake, take another,
## preview cancel, use photo, case sheet, back, back; then reopen, complaint details, case, back, back;
## finally walk away to prove movement is restored. Seed 4044.
## Setup (hidden): new game, player standing at the property's inspection anchor. All input is real taps.

var house := -1


func _setup() -> void:
	house = int(main.sim.assignments.keys()[0])
	for h in main.sim.assignments:
		if str(main.sim.assignments[h].kind) != "reinspect":
			house = int(h)
			break
	main._visited[house] = true
	place_player(hood.lots[house].inspect_anchor())
	street.set_objective(house)
	main.sim.encounters.catalog = []      # this video is about the flow, not the comedy
	print("VIDEO04 house=", house, " ", hood.lots[house].address)


func _inspect() -> void:
	await tap(prompt_center())
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(1.6)


func _ready() -> void:
	await boot_hidden(4044, true, "VIDEO 04", "CAMERA + UI ESCAPE STRESS TEST", _setup)
	await wait(2.5)
	await _inspect()                                          # 1-2
	await press("TAKE PHOTO")                                 # 3
	await wait_state("CAMERA", 4.0)
	await wait(2.0)
	await tap_hud(street.hud_view._zoom_buttons().cancel)    # 5 CANCEL
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(1.6)                                           # 6 back at the card
	await press("TAKE PHOTO")                                 # 7
	await wait_state("CAMERA", 4.0)
	await wait(1.6)
	await shoot_until_preview()                               # 8-9
	await wait(2.2)
	await press("RETAKE")                                     # 10
	await wait_state("CAMERA", 4.0)                           # 11
	await wait(1.4)
	await shoot_until_preview()                               # 12
	await wait(2.0)
	await press("TAKE ANOTHER")                               # 13
	await wait_state("CAMERA", 4.0)                           # 14
	await wait(1.4)
	await tap_hud(street.hud_view._zoom_buttons().plus)
	await wait(1.0)
	await shoot_until_preview()                               # 15
	await wait(2.0)
	await press("CANCEL")                                     # 16 cancel from the preview
	await wait_state("PROPERTY_CONTEXT", 4.0)                 # 17 returns to the card
	await wait(2.0)
	await press("TAKE ANOTHER")                               # more evidence
	await wait_state("CAMERA", 4.0)
	await wait(1.2)
	await tap_hud_point(street.hud_view.camera_shutter())     # try the album button too
	await wait(0.5)
	if main.ui_state != "PHOTO_PREVIEW":
		await shoot_until_preview()
	await wait(2.0)
	await press("USE PHOTO")                                  # 18
	await wait_state("PROPERTY_CONTEXT", 4.0)                 # 19
	await wait(2.0)
	await press("REVIEW & DECIDE")                            # 20
	await wait_state("CASE_DECISION", 4.0)                    # 21
	await wait(2.6)
	await press("< BACK")                                     # 22
	await wait_state("PROPERTY_CONTEXT", 4.0)                 # 23
	await wait(1.8)
	await press("< BACK")                                     # 24
	await wait_state("WORLD", 4.0)                            # 25
	await wait(2.0)
	# --- reopen and poke every exit -------------------------------------------------------------
	await _inspect()                                          # 26
	await press("VIEW COMPLAINT")                             # 27
	await wait(2.4)
	await press("HIDE DETAILS")                               # 28
	await wait(1.4)
	await press("OPEN CASE") if has_button("OPEN CASE") else await press("REVIEW & DECIDE")   # 29
	await wait_state("CASE_DECISION", 4.0)
	await wait(2.2)
	await press("< BACK")                                     # 30
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(1.4)
	await press("< BACK")                                     # 31 world
	await wait_state("WORLD", 4.0)
	await wait(1.5)
	# --- movement is restored ------------------------------------------------------------------
	await push_direction(Vector2(-0.4, 1.0), 2.6)
	await wait(1.2)
	await push_direction(Vector2(1.0, -0.2), 2.6)
	await wait(2.0)
	await finish()
