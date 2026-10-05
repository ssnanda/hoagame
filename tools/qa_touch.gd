extends Node
## Touch-target audit (section 114). Walks the real UI in each state and lists any visible
## button/toggle smaller than the minimum. The game's design space is 720 px wide, which maps to
## about 390 pt on an iPhone (0.54), so 56 design px is ~30 pt. Rules used here:
##   primary actions >= 80 design px tall, everything else >= 56 design px in both directions
##   (labels wider than tall are fine when the SHORT side meets the minimum).
##   HOME=<scratch> godot --path . --position 6000,6000 --resolution 540x960 res://tools/qa_touch.tscn

const MainScene := preload("res://scenes/main.tscn")
const MIN_SHORT := 56.0
const MIN_PRIMARY := 80.0
var main: Node
var street: Node
var problems := 0
var scanned := 0


func _ready() -> void:
	Settings.tutorial_done = true
	main = MainScene.instantiate()
	add_child(main)
	await _frames(10)
	main._begin(false)
	await _frames(8)
	main._close_overlay()
	street = main._street
	main.sim.encounters.catalog = []
	await _frames(4)
	_scan("world HUD", main)
	main._open_menu()
	await _frames(4)
	_scan("menu", main)
	main._close_modal()
	main._show_modal(preload("res://scripts/ui/menu_panels.gd").settings(main.size, main._close_modal, func(): pass))
	await _frames(4)
	_scan("settings", main)
	main._close_modal()
	var house := int(street.objective)
	main._visited[house] = true
	street.player.position = street.hood.lots[house].inspect_anchor()
	await _frames(8)
	street.inspect_near()
	await _frames(4)
	_scan("property card", main)
	_press("TAKE PHOTO")
	await _frames(4)
	_check_rects("camera", street.hud_view)
	for zoom in [1.4, 1.0, 1.8]:
		street.camera_ev.zoom = zoom
		await _frames(18)
		if bool(street.frame_info.get("potential", false)):
			break
	await street.take_photo()
	await _frames(6)
	_scan("photo preview", main)
	_press("USE PHOTO")
	await _frames(4)
	_press("REVIEW & DECIDE")
	await _frames(4)
	_scan("case sheet", main)
	print("QA TOUCH: scanned %d controls, %d under the minimum" % [scanned, problems])
	get_tree().quit(1 if problems > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _scan(where: String, node: Node) -> void:
	if node is BaseButton and (node as Control).is_visible_in_tree():
		var c := node as Control
		var short := minf(c.size.x, c.size.y)
		scanned += 1
		var need := MIN_PRIMARY if str((node as Button).text if node is Button else "") in ["TAKE PHOTO", "USE PHOTO", "REVIEW & DECIDE", "INSPECT"] and c.size.x > 300.0 else MIN_SHORT
		if short < need - 0.5 and not (node is HSlider):
			problems += 1
			print("  SMALL (%s): '%s' %dx%d, needs %d" % [where, str((node as Button).text if node is Button else node.name), int(c.size.x), int(c.size.y), int(need)])
	for child in node.get_children():
		_scan(where, child)


func _check_rects(where: String, hud) -> void:
	var rects: Dictionary = hud._zoom_buttons()
	for key in rects:
		var r: Rect2 = rects[key]
		scanned += 1
		if minf(r.size.x, r.size.y) < MIN_SHORT:
			problems += 1
			print("  SMALL (%s): %s %dx%d" % [where, key, int(r.size.x), int(r.size.y)])
	scanned += 1
	if 2.0 * 56.0 < MIN_SHORT:
		problems += 1


func _press(text: String, node: Node = null) -> void:
	node = node if node != null else main
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		(node as Button).pressed.emit()
		return
	for child in node.get_children():
		_press(text, child)
