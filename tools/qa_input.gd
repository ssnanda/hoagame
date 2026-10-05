extends Node
## Input QA (sections 14, 15, 91): a drag that ends next to a property must not open it,
## a real tap on the prompt must, and a two-finger pinch must zoom without walking.
##   godot --path . --position 6000,6000 res://tools/qa_input.tscn   (needs a renderer for layout)

const MainScene := preload("res://scenes/main.tscn")
var main: Node
var street: Node
var visits := 0
var problems := 0


func _ready() -> void:
	Settings.tutorial_done = true
	main = MainScene.instantiate()
	add_child(main)
	for i in 10:
		await get_tree().process_frame
	main._begin(false)
	for i in 8:
		await get_tree().process_frame
	main._close_overlay()
	street = main._street
	street.visit.connect(func(_h): visits += 1)
	var house := -1
	for h in main.sim.assignments:
		house = int(h)
		break
	main._visited[house] = true
	street.player.position = street.hood.lots[house].inspect_anchor() + Vector2(0, 160)
	for i in 6:
		await get_tree().process_frame
	# 1. Drag toward the property and release right beside it.
	_mouse(true, Vector2(300, 700))
	for k in 12:
		_motion(Vector2(300, 700 - k * 18))
		await get_tree().process_frame
	street.player.position = street.hood.lots[house].inspect_anchor()
	_mouse(false, Vector2(300, 484))
	for i in 10:
		await get_tree().process_frame
	_check(visits == 0, "drag release opened a property (visits=%d)" % visits)
	# Let the player settle exactly on the anchor (velocity from the drag has decayed by now).
	street.player.position = street.hood.lots[house].inspect_anchor()
	street.player.velocity = Vector2.ZERO
	for i in 6:
		await get_tree().process_frame
	_check(street.near == house, "player is not near the property at its anchor (near=%d, expected %d)" % [street.near, house])
	# 2. A quick tap on the prompt opens it.
	var prompt: Rect2 = street.hud_view.prompt_rect
	_check(prompt.has_area(), "no inspect prompt shown near an active case")
	var at := prompt.get_center()
	_mouse(true, at)
	_mouse(false, at)
	await get_tree().process_frame
	_check(visits == 1, "tap on the prompt did not open the property card (visits=%d)" % visits)
	_check(main.ui_state == "PROPERTY_CONTEXT" or is_instance_valid(main._card_ui), "no card after tapping INSPECT")
	main.close_topmost()
	main._close_overlay()
	for i in 4:
		await get_tree().process_frame
	# 3. Pinch: two fingers apart -> zoom target grows; the walk gesture is cancelled.
	var before: float = street.zoom_input.target
	_touch(0, Vector2(250, 600), true)
	_touch(1, Vector2(290, 600), true)
	for k in 8:
		_drag(0, Vector2(250 - k * 10, 600))
		_drag(1, Vector2(290 + k * 10, 600))
		await get_tree().process_frame
	_touch(0, Vector2.ZERO, false)
	_touch(1, Vector2.ZERO, false)
	_check(float(street.zoom_input.target) > before + 0.2, "pinch out did not zoom in (%.2f -> %.2f)" % [before, street.zoom_input.target])
	_check(not street.dragging, "pinch left a walk drag active")
	_check(float(street.zoom_input.target) <= street.zoom_input.ZOOM_MAX + 0.001, "zoom exceeded its maximum")
	print("QA INPUT: %d problem(s)" % problems)
	get_tree().quit(1 if problems > 0 else 0)


func _check(ok: bool, msg: String) -> void:
	if not ok and msg != "":
		print("  FAIL: ", msg)
		problems += 1


func _mouse(pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	street._gui_input(e)


func _motion(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	street._gui_input(e)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	street._input(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	street._input(e)
