extends Node
## Complaint-flow and stuck-state QA (sections 81-82): drives the real UI (buttons, camera,
## preview, case sheet) and checks that the player always ends up back in WORLD with input
## restored. Needs a renderer (off-screen window is fine):
##   HOME=<scratch> godot --path . --position 6000,6000 --resolution 540x960 res://tools/qa_flow.tscn

const MainScene := preload("res://scenes/main.tscn")
var main: Node
var street: Node
var problems := 0


func _ready() -> void:
	Settings.tutorial_done = true
	main = MainScene.instantiate()
	add_child(main)
	await _frames(10)
	main._begin(false)
	await _frames(8)
	main._close_overlay()
	street = main._street
	main.sim.encounters.catalog = []          # cinematics are covered by qa_cinematic
	await _frames(4)
	_expect("WORLD", "after starting")
	var house := int(street.objective)
	main._visited[house] = true
	_to_property(house)
	await _frames(6)
	# 1. Inspect opens the compact card, not the case sheet.
	street.inspect_near()
	await _frames(4)
	_expect("PROPERTY_CONTEXT", "after INSPECT")
	_check(_find("TAKE PHOTO") != null, "TAKE PHOTO is not on the card")
	_check(_find("< BACK") != null, "card has no Back")
	# 2. View complaint toggles details and back.
	_press("VIEW COMPLAINT")
	await _frames(3)
	_expect("COMPLAINT_VIEW", "after VIEW COMPLAINT")
	_press("HIDE DETAILS")
	await _frames(3)
	_expect("PROPERTY_CONTEXT", "after HIDE DETAILS")
	# 3. Camera -> cancel -> card -> camera again.
	_press("TAKE PHOTO")
	await _frames(4)
	_expect("CAMERA", "after TAKE PHOTO")
	street.cancel_camera()
	await _frames(4)
	_expect("PROPERTY_CONTEXT", "after camera cancel")
	_press("TAKE PHOTO")
	await _frames(4)
	_expect("CAMERA", "second camera")
	# 4. Escape closes the camera, then the card, back to WORLD.
	main.close_topmost()
	await _frames(4)
	_expect("PROPERTY_CONTEXT", "Escape from camera")
	main.close_topmost()
	await _frames(4)
	_expect("WORLD", "Escape from card")
	_check(not street.ui_locked, "world still locked after closing the card")
	# 5. Full path: inspect, photo, retake, use, review, back, review, decide.
	street.inspect_near()
	await _frames(4)
	_press("TAKE PHOTO")
	await _frames(4)
	await _shoot()
	_expect("PHOTO_PREVIEW", "after the shutter")
	_check(_find("USE PHOTO") != null and _find("RETAKE") != null, "preview is missing its buttons")
	_press("RETAKE")
	await _frames(4)
	_expect("CAMERA", "after RETAKE")
	await _shoot()
	_expect("PHOTO_PREVIEW", "second shot")
	_press("USE PHOTO")
	await _frames(4)
	_expect("PROPERTY_CONTEXT", "after USE PHOTO")
	_check(street.get_evidence().has(house), "photo was not attached")
	_check(_find("REVIEW & DECIDE") != null, "no REVIEW & DECIDE after evidence")
	_press("REVIEW & DECIDE")
	await _frames(4)
	_expect("CASE_DECISION", "case sheet")
	_press("< BACK")
	await _frames(4)
	_expect("PROPERTY_CONTEXT", "Back from the case sheet")
	_press("REVIEW & DECIDE")
	await _frames(4)
	_press("WARNING")
	await _frames(8)
	_expect("WORLD", "after ruling")
	_check(house in main.sim.completed, "ruling did not complete the case")
	# 6. Album and menu round trips.
	street.hud_view.gallery_open = true
	await _frames(3)
	_check(street._overlay_open(), "album does not lock the street")
	main.close_topmost()
	await _frames(3)
	_check(not street.hud_view.gallery_open, "Escape did not close the album")
	main._open_menu()
	await _frames(4)
	_expect("MODAL", "menu")
	main.close_topmost()
	await _frames(4)
	_expect("WORLD", "after closing the menu")
	_check(not street._overlay_open(), "street input still blocked after everything closed")
	# 7. Touches on the world behind a panel do nothing (section 81 "Modal").
	var second := -1
	for h in main.sim.assignments:
		if not h in main.sim.completed:
			second = int(h)
			break
	if second >= 0:
		main._visited[second] = true
		_to_property(second)
		await _frames(8)
		street.inspect_near()
		await _frames(4)
		_expect("PROPERTY_CONTEXT", "second property")
		var pos_before: Vector2 = street.player.position
		var visits_before := 0
		street.visit.connect(func(_h): visits_before += 1)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(200, 500)
		street._gui_input(press)
		for k in 6:
			var mv := InputEventMouseMotion.new()
			mv.position = Vector2(200, 500 - k * 20)
			street._gui_input(mv)
		var rel := InputEventMouseButton.new()
		rel.button_index = MOUSE_BUTTON_LEFT
		rel.pressed = false
		rel.position = Vector2(200, 400)
		street._gui_input(rel)
		await _frames(6)
		_check(street.player.position.distance_to(pos_before) < 1.0, "the player walked behind an open card")
		_check(not street.dragging and visits_before == 0, "world gesture leaked through the card")
		_expect("PROPERTY_CONTEXT", "after touching the world behind the card")
		main.close_topmost()
		await _frames(4)
	# 8. Reinspection uses the same card: INSPECT -> panel -> Back -> card -> choose.
	var third := -1
	for h in main.sim.assignments:
		if not h in main.sim.completed and int(h) != second:
			third = int(h)
			break
	if third >= 0:
		var asg: Dictionary = main.sim.assignments[third]
		main.sim.rule_case(third, "warning", _all_ids(asg), {})
		main.sim.completed.erase(third)
		main.sim.assignments[third] = {"kind": "reinspect", "source": "sweep", "violations": asg.violations, "false_complaint": false,
				"text": "Cure period ended. Check the property.", "status": "assigned", "result": "unchanged"}
		street.pins[third] = "reinspect"
		main._visited[third] = true
		_to_property(third)
		street.objective = third
		await _frames(8)
		street.inspect_near()
		await _frames(4)
		_expect("PROPERTY_CONTEXT", "reinspection card")
		_check(_find("INSPECT") != null, "reinspection card has no INSPECT button")
		_press("INSPECT")
		await _frames(4)
		_expect("CASE_DECISION", "reinspection panel")
		_press("< BACK")
		await _frames(4)
		_expect("PROPERTY_CONTEXT", "Back from the reinspection panel")
		_press("INSPECT")
		await _frames(4)
		_press("EXTEND 2 DAYS")
		await _frames(8)
		_expect("WORLD", "after the reinspection choice")
	print("QA FLOW: %d problem(s)" % problems)
	get_tree().quit(1 if problems > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _to_property(house: int) -> void:
	street.player.position = street.hood.lots[house].inspect_anchor()
	street.cam = street.player.position - street.size * 0.5
	street._cam_ready = false


func _shoot() -> void:
	# Like a player: let the viewfinder settle, try zoom levels until something is recorded.
	for zoom in [1.4, 1.0, 1.8, 2.2]:
		street.camera_ev.zoom = zoom
		await _frames(18)
		if bool(street.frame_info.get("potential", false)):
			break
	await street.take_photo()
	await _frames(4)


func _expect(state: String, when: String) -> void:
	_check(main.ui_state == state, "expected %s %s, got %s" % [state, when, main.ui_state])


func _check(ok: bool, msg: String) -> void:
	if not ok:
		print("  FAIL: ", msg)
		problems += 1


func _find(text: String, node: Node = null) -> Button:
	node = node if node != null else main
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree() and not (node as Button).disabled:
		return node
	for child in node.get_children():
		var found := _find(text, child)
		if found != null:
			return found
	return null


func _press(text: String) -> void:
	var b := _find(text)
	if b == null:
		print("  FAIL: no button '%s' (state %s)" % [text, main.ui_state])
		problems += 1
		return
	b.pressed.emit()


func _all_ids(a: Dictionary) -> Array:
	var ids: Array = []
	for v in a.violations:
		ids.append(str(v.id))
	return ids
