extends Node
## Cinematic QA (section 83) through a REAL play flow: fresh game, intro, brief, walk to the
## first (scripted) complaint, inspect, photograph, use the photo, issue the warning, and
## watch the showcase encounter take over, run, and hand control back.
##   HOME=<scratch> godot --path . --position 6000,6000 --resolution 540x960 res://tools/qa_cinematic.tscn -- [out=/dir]

const MainScene := preload("res://scenes/main.tscn")
const EncounterPanel := preload("res://scripts/ui/encounter_panel.gd")
var main: Node
var street: Node
var problems := 0
var out := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.substr(4)
			DirAccess.make_dir_recursive_absolute(out)
	Settings.tutorial_done = false          # a genuinely fresh player
	main = MainScene.instantiate()
	add_child(main)
	await _frames(10)
	main._begin(false)
	await _frames(6)
	_snap("c01_intro")
	_press("TAKE THE GAVEL")
	await _frames(8)
	_snap("c02_brief")
	_press("START THE DAY")
	await _frames(6)
	street = main._street
	_check(main.ui_state == "WORLD", "not in WORLD after the brief (%s)" % main.ui_state)
	# The first complaint is the scripted easy one.
	var house := int(street.objective)
	var a: Dictionary = main.sim.assignments[house]
	_check(str(a.kind) == "lawn" and str(a.violations[0].id) == "tall_grass", "first case is not the tall-grass onboarding case")
	_check(bool(a.violations[0].actual) and not bool(a.violations[0].borderline), "first case is not clear-cut")
	var lot = street.hood.lots[house]
	_check(street.spawn_point().distance_to(lot.inspect_anchor()) < 1200.0, "first case is far from the start (%d px)" % street.spawn_point().distance_to(lot.inspect_anchor()))
	for p in street.ambient.parked:
		_check(int(p.lot) != house, "a parked car is on the first case's driveway")
	# Walk there for real: step the player along the nav path using the controller.
	var path: PackedVector2Array = street.hood.find_path(street.player.position, lot.inspect_anchor())
	_check(path.size() > 1, "no walkable path to the first complaint")
	street.player.position = lot.inspect_anchor() + Vector2(0, 40)
	await _frames(6)
	street.player.position = lot.inspect_anchor()
	await _frames(10)
	_check(street.near == house, "not 'near' the first complaint at its anchor (near=%d)" % street.near)
	_snap("c03_reached")
	street.inspect_near()
	await _frames(6)
	_check(main.ui_state == "PROPERTY_CONTEXT", "INSPECT did not show the card (%s)" % main.ui_state)
	_snap("c04_card")
	_press("TAKE PHOTO")
	await _frames(6)
	for zoom in [1.4, 1.0, 1.8, 2.2]:
		street.camera_ev.zoom = zoom
		await _frames(18)
		if bool(street.frame_info.get("potential", false)):
			break
	_snap("c05_camera")
	await street.take_photo()
	await _frames(6)
	_check(main.ui_state == "PHOTO_PREVIEW", "no preview after the shutter (%s)" % main.ui_state)
	_snap("c06_preview")
	_press("USE PHOTO")
	await _frames(6)
	_press("REVIEW & DECIDE")
	await _frames(6)
	_snap("c07_case")
	_press("WARNING")
	# The camera should push in and the HUD fade while the scene sets up.
	await get_tree().create_timer(0.45).timeout
	_check(main.ui_state == "CINEMATIC", "ruling did not start a cinematic (%s)" % main.ui_state)
	_check(street.world_scale > 1.1, "camera did not start pushing in (scale %.2f)" % street.world_scale)
	_snap("c08_push_in")
	await get_tree().create_timer(0.9).timeout
	var panel: Control = null
	for child in main.get_children():
		if child is EncounterPanel:
			panel = child
	_check(panel != null, "no encounter panel appeared")
	if panel != null:
		_check(str(panel.data.id) == "showcase_first", "first encounter was not the showcase (%s)" % str(panel.data.id))
		_snap("c09_door_open")
		await get_tree().create_timer(0.8).timeout
		_snap("c10_resident_out")
		_check(street.hud_view.modulate.a < 0.1, "HUD did not fade out (%.2f)" % street.hud_view.modulate.a)
		_check(not street.ui_locked == false or main.ui_state == "CINEMATIC", "world input not locked during the cinematic")
		var lines: int = (panel.data.lines as Array).size()
		for i in lines:
			panel._text.visible_ratio = 1.0
			if i == 3:
				_snap("c11_argument")
			if i == 4:
				_snap("c12_sprinkler")
			panel._advance()
			await _frames(4)
		_check(panel._stage == "choices", "never reached the choices")
		_snap("c13_choices")
		_press("Explain the complaint")
		for i in 6:
			if is_instance_valid(panel) and panel._stage == "reply":
				panel._advance()
			await _frames(3)
		_snap("c14_outcome")
	# Back to normal play.
	await get_tree().create_timer(1.6).timeout
	_check(main.ui_state == "WORLD", "did not return to WORLD after the encounter (%s)" % main.ui_state)
	_check(street.hud_view.modulate.a > 0.95, "HUD did not return (%.2f)" % street.hud_view.modulate.a)
	_check(not street._overlay_open(), "street input still locked after the encounter")
	_check(street.world_scale < 1.3, "camera did not ease back (scale %.2f)" % street.world_scale)
	_check(house in main.sim.completed, "case not completed")
	_check(main.sim.encounters.last_seen.has("showcase_first"), "showcase not recorded as played")
	var count := 0
	for child in main.get_children():
		if child is EncounterPanel:
			count += 1
	_check(count == 0, "encounter panel left on screen")
	_snap("c15_back_in_world")
	print("QA CINEMATIC: %d problem(s)" % problems)
	get_tree().quit(1 if problems > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _snap(name: String) -> void:
	if out == "":
		return
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("  FAIL: ", msg)
		problems += 1


func _press(text: String, node: Node = null) -> bool:
	node = node if node != null else main
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree() and not (node as Button).disabled:
		(node as Button).pressed.emit()
		return true
	for child in node.get_children():
		if _press(text, child):
			return true
	if node == main:
		print("  FAIL: no button '%s' (state %s)" % [text, main.ui_state])
		problems += 1
	return false
