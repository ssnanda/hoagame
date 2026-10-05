extends "res://tools/video/video_lib.gd"
## VIDEO 09: the game does not reveal complaint truth. Case 1 is the scripted FALSE complaint (bins that are not
## there): marker says only COMPLAINT, the camera shows nothing, the case sheet shows "nothing seen", DISMISS. Case 2
## is the scripted BORDERLINE grass report on day two: ambiguous until you investigate. Seed 9099.
## Setup (hidden): fresh game started on day one (scripted cases exist); no teleport while recording.

var false_house := -1
var border_house := -1


func _find(kind_id: String, borderline: bool) -> int:
	for h in main.sim.assignments:
		var a: Dictionary = main.sim.assignments[h]
		if str(a.kind) == "reinspect":
			continue
		var v: Dictionary = a.violations[0]
		if borderline and str(v.id) == "tall_grass" and bool(v.borderline) and bool(v.actual):
			return int(h)
		if not borderline and str(v.id) == kind_id and not bool(v.actual) and bool(a.get("false_complaint", false)):
			return int(h)
	return -1


func _setup() -> void:
	false_house = _find("curb_bins", false)
	print("VIDEO09 false_house=", false_house)


func _select_by_chip(target: int) -> void:
	for i in 10:
		if int(street.objective) == target:
			return
		await tap_hud(street.hud_view.next_rect)
		await wait(1.6)


func _ready() -> void:
	await boot_hidden(9099, false, "VIDEO 09", "FALSE + BORDERLINE COMPLAINTS", _setup)
	await wait(3.0)
	# --- case 1: the false complaint -----------------------------------------------------------------
	await _select_by_chip(false_house)
	await wait(2.4)
	var lot = hood.lots[false_house]
	await walk_to(lot.inspect_anchor(), 40.0, 120.0, false, 0.75)
	await wait(3.0)                                  # marker: COMPLAINT. Nothing says whether it is true.
	await tap(prompt_center())
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(3.5)
	await press("TAKE PHOTO")
	await wait_state("CAMERA", 4.0)
	await wait(3.0)                                  # no "potential evidence" tag: nothing to record
	await shoot_until_preview()
	await wait(3.5)                                  # "Nothing clearly recorded"
	await press("USE PHOTO")
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(2.0)
	await press("REVIEW & DECIDE")
	await wait_state("CASE_DECISION", 4.0)
	await wait(5.0)                                  # the photo cleared the allegation
	await press("DISMISS")
	await wait_state("WORLD", 6.0)
	await wait(3.0)
	# --- case 2: the borderline report on day two ------------------------------------------------------------------
	var fade := await fade_black(0.7)
	for h in main.sim.assignments:
		if not h in main.sim.completed:
			main.sim.completed.append(int(h))            # setup: the rest of day one is done
	GameState.next_day()
	main._new_day()                                      # day two: the scripted borderline report is created
	build_nav()
	await wait(0.4)
	await unfade(fade, 0.6)
	await wait(2.5)
	await press("START THE DAY")
	await dismiss_modals()
	await wait(1.5)
	border_house = _find("tall_grass", true)
	print("VIDEO09 border_house=", border_house)
	await _select_by_chip(border_house)
	await wait(2.4)
	var lot2 = hood.lots[border_house]
	await walk_to(lot2.inspect_anchor(), 40.0, 120.0, false, 0.75)
	await wait(3.0)
	await tap(prompt_center())
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(3.5)                                      # "It might be right at the limit."
	await press("MEASURE LAWN")
	await wait(4.0)                                      # the measuring tool: judgment, not a verdict
	await press("< BACK")
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(1.5)
	await press("TAKE PHOTO")
	await wait_state("CAMERA", 4.0)
	await wait(2.4)
	await shoot_until_preview()
	await wait(3.0)
	await press("USE PHOTO")
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(1.6)
	await press("REVIEW & DECIDE")
	await wait_state("CASE_DECISION", 4.0)
	await wait(5.0)                                      # evidence shows it; whether to act is the player's call
	await press("< BACK")
	await wait(1.6)
	await press("< BACK")
	await wait(2.0)
	await finish()
