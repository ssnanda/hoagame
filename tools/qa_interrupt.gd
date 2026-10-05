extends Node
## Interruption QA (section 83): the app loses focus while a card/camera/cinematic is up, then
## is relaunched. Nothing may be lost, repeated or left stuck.
##   HOME=<scratch> godot --path . --position 6000,6000 --resolution 540x960 res://tools/qa_interrupt.tscn

const MainScene := preload("res://scenes/main.tscn")
const EncounterPanel := preload("res://scripts/ui/encounter_panel.gd")
var main: Node
var street: Node
var problems := 0


func _ready() -> void:
	Settings.tutorial_done = false
	main = MainScene.instantiate()
	add_child(main)
	await _frames(10)
	main._begin(false)
	await _frames(6)
	_press("TAKE THE GAVEL")
	await _frames(6)
	_press("START THE DAY")
	await _frames(6)
	street = main._street
	var house := int(street.objective)
	var lot = street.hood.lots[house]
	main._visited[house] = true
	street.player.position = lot.inspect_anchor()
	await _frames(10)
	# 1. Focus loss with the property card open: saves, card still there, nothing breaks.
	street.inspect_near()
	await _frames(4)
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check(main.ui_state == "PROPERTY_CONTEXT", "card lost on focus-out (%s)" % main.ui_state)
	# 2. Camera open + focus loss.
	_press("TAKE PHOTO")
	await _frames(4)
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	await _frames(2)
	_check(main.ui_state == "CAMERA", "camera lost on pause (%s)" % main.ui_state)
	for zoom in [1.4, 1.0, 1.8, 2.2]:
		street.camera_ev.zoom = zoom
		await _frames(18)
		if bool(street.frame_info.get("potential", false)):
			break
	await street.take_photo()
	await _frames(6)
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(main.ui_state == "PHOTO_PREVIEW", "preview lost on focus-out (%s)" % main.ui_state)
	_press("USE PHOTO")
	await _frames(6)
	_press("REVIEW & DECIDE")
	await _frames(6)
	_press("WARNING")
	await get_tree().create_timer(1.8).timeout
	_check(main.ui_state == "CINEMATIC", "cinematic did not start (%s)" % main.ui_state)
	# 3. App interrupted in the middle of the cinematic.
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	var saved: Dictionary = GameState.saved_world()
	_check(house in (saved.get("completed", []) as Array), "ruling not in the save made during the cinematic")
	_check((saved.get("encounter_seen", {}) as Dictionary).has("showcase_first"), "showcase not recorded as seen in the save")
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	await _frames(2)
	_check(main.ui_state == "CINEMATIC", "cinematic dropped by the interruption")
	# Finish it normally.
	var panel: Control = null
	for child in main.get_children():
		if child is EncounterPanel:
			panel = child
	_check(panel != null, "encounter panel vanished")
	if panel != null:
		var lines: int = (panel.data.lines as Array).size()
		for i in lines:
			if is_instance_valid(panel):
				panel._text.visible_ratio = 1.0
				panel._advance()
			await _frames(3)
		_press("Stay firm")
		for i in 6:
			if is_instance_valid(panel) and panel._stage == "reply":
				panel._advance()
			await _frames(3)
	await get_tree().create_timer(1.6).timeout
	_check(main.ui_state == "WORLD", "not back in WORLD after the interrupted encounter (%s)" % main.ui_state)
	_check(not street._overlay_open(), "street still locked")
	var rel_after: int = int(main.sim.properties[house].relationship)
	# 4. Relaunch: a fresh instance resumes the saved run; the showcase must not replay.
	main._save_progress()
	main.queue_free()
	await _frames(3)
	GameState.has_saved_run = true
	GameState._load_save()
	var b: Node = MainScene.instantiate()
	add_child(b)
	await _frames(10)
	b._begin(true)
	await _frames(8)
	_check(b.sim.encounters.last_seen.has("showcase_first"), "resume forgot the showcase was played")
	_check(house in b.sim.completed, "resume lost the completed case")
	_check(int(b.sim.properties[house].relationship) == rel_after, "relationship changed across resume (%d vs %d)" % [int(b.sim.properties[house].relationship), rel_after])
	var pick: Dictionary = b.sim.pick_encounter(house, "warning", 0)
	_check(pick.is_empty() or str(pick.id) != "showcase_first", "showcase would replay after resume")
	_check(b.ui_state == "WORLD", "resumed game not in WORLD (%s)" % b.ui_state)
	print("QA INTERRUPT: %d problem(s)" % problems)
	get_tree().quit(1 if problems > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
