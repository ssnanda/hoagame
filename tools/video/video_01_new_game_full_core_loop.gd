extends "res://tools/video/video_lib.gd"
## VIDEO 01: one uninterrupted new-player run. Fresh profile, no teleporting while recording.
## Seed 7771. Real taps on real buttons, the player walks with a virtual thumb.

func _ready() -> void:
	await boot(7771, false, "VIDEO 01", "NEW GAME - FULL CORE LOOP")
	build_nav()
	# --- title, intro, brief ---------------------------------------------------------
	await wait(4.0)                          # title screen
	await press("NEW TERM")
	await wait(5.0)                          # the intro text
	await press("TAKE THE GAVEL")
	await wait(5.0)                          # daily brief: let the viewer read it
	await press("START THE DAY")
	await wait(3.5)
	# --- the assignment: Next chip, marker, minimap ---------------------------------------
	var house := int(street.objective)
	var lot = hood.lots[house]
	await wait(3.0)                          # hint, Next chip, marker, minimap
	await pinch(Vector2(360.0, 620.0), 120.0, 300.0, 1.4)    # pinch to zoom in...
	await wait(1.6)
	await tap_hud(street.hud_view.zoom_reset_rect())          # ...and RESET ZOOM
	await wait(1.6)
	await tap_hud(street.hud_view.minimap_rect())     # full map: shows streets and the selected case
	await wait(5.0)
	await tap_hud(street.hud_view._map_close_rect())
	await wait(2.0)
	# --- walk there with the thumb (no teleport) ------------------------------------------------------
	var arrived: bool = await walk_to(lot.inspect_anchor(), 36.0, 90.0, false, 0.7)
	await wait(3.0)                          # arrival cue + address
	# --- inspect -> card -> complaint -> photo ------------------------------------------------------
	await tap(prompt_center())
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(3.5)
	await press("VIEW COMPLAINT")
	await wait(4.0)
	await press("HIDE DETAILS")
	await wait(1.5)
	await press("TAKE PHOTO")
	await wait_state("CAMERA", 4.0)
	await wait(4.0)
	await shoot_until_preview()
	await wait(4.0)
	await press("USE PHOTO")
	await wait_state("PROPERTY_CONTEXT", 4.0)
	await wait(3.5)                          # "Evidence attached"
	await press("REVIEW & DECIDE")
	await wait_state("CASE_DECISION", 4.0)
	await wait(5.0)
	await press("WARNING")
	# --- the showcase cinematic ---------------------------------------------------------------
	await wait_state("CINEMATIC", 6.0)
	var panel: Control = null
	for i in 60:
		for child in main.get_children():
			if child.get_script() != null and str(child.get_script().resource_path).ends_with("encounter_panel.gd"):
				panel = child
		if panel != null:
			break
		await wait(0.1)
	await wait(2.4)                          # camera push, door opens, resident walks out
	if panel != null:
		var lines: int = (panel.data.lines as Array).size()
		for i in lines:
			await wait_text_done(panel, 1.8)
			await tap(Vector2(360.0, 520.0))
			await wait(0.3)
		await wait(2.8)                      # read the three replies
		await press("Give them a few days")
		for i in 3:
			if is_instance_valid(panel) and panel._stage == "reply":
				await wait_text_done(panel, 1.8)
				await tap(Vector2(360.0, 520.0))
	await wait_state("WORLD", 8.0)
	await wait(3.0)                          # camera and HUD are back
	# --- control returns: walk away a little -------------------------------------------------------
	await push_direction(Vector2(-0.3, 1.0), 3.0)
	await wait(1.5)
	await push_direction(Vector2(0.9, 0.3), 2.5)
	await wait(2.0)
	# --- secondary information is one tap away: STATS, then the case board ----------------------------------
	await press("STATS")
	await wait(4.0)
	await press("STATS")
	await wait(1.2)
	await press("MENU")
	await wait(2.0)
	await press("CASE BOARD")
	await wait(5.0)
	await press("CLOSE")
	await wait(2.0)
	await finish()
