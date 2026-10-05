extends Node
## Scripted training videos recorded from the real game with Godot's movie writer.
## Run in a throwaway project copy whose window override is 720x1560:
##   godot --path . --write-movie out.avi --fixed-fps 30 -- video=1
## video=1 Getting around, 2 Inspecting and photographing, 3 Case sheet and rulings,
## 4 Follow-ups (reinspection, hearing), 5 Board, politics and the portal,
## 6 Seasons and the neighborhood.

const FPS := 30

## Dry asides, matched by a snippet of the caption text.
const ASIDES := {
	"title screen": "Please remain seated. Your term begins immediately.",
	"Gold pins": "Gold: the color of accountability and slightly overdue lawn care.",
	"Drag anywhere": "Left, right, forward. Bureaucracy, but outdoors.",
	"Stay on sidewalks": "Walking through a fence is not a recognized inspection method.",
	"Quick taps": "We have decided accidents are the board's department.",
	"minimap": "A very small map for a very large sense of responsibility.",
	"full map": "Every street, every home, every opinion.",
	"destination": "It's like GPS, but it judges you less.",
	"golf cart": "Authority, at nine miles an hour.",
	"Carts can't": "Driveways: the final frontier.",
	"stays where you leave": "Unlike most things in this neighborhood, it stays put.",
	"not proof": "Neither is a strongly worded email at 11 pm.",
	"INSPECT button": "Do not lunge at the button. The gnomes will notice.",
	"gather evidence": "If it isn't photographed, it is gossip.",
	"Center the house": "Chin up. Your rule of thirds is also being audited.",
	"Zoom with": "Between 1.4x and 2x. Past that, it's surveillance.",
	"Potential evidence": "It sees something. It will not say what. Very corporate.",
	"shutter": "Say 'compliance'.",
	"recorded": "Your album is now legally a portfolio.",
	"blurry": "Art is subjective. Evidence is not.",
	"ALBUM": "Not for vacation photos. Please.",
	"Open a photo": "Delete the blurry ones. We saw them.",
	"Case 1": "Today's episode: a lawn.",
	"PROPERTY:": "Everyone has a story. Most of it is about mulch.",
	"COMPLAINT:": "Source reliability: 'frequent filer' means exactly what you think.",
	"OBSERVATIONS": "Facts. Gentle, laminated facts.",
	"POSSIBLE VIOLATIONS": "Tick only what you can prove. This is not the comments section.",
	"first notice": "Due process: slower than you'd like, faster than a pool committee.",
	"WARNING": "A warning is a fine that hasn't finished growing up.",
	"Points reward": "Points are not currency. The board checked.",
	"may be wrong": "It happens. Frequently. Always on a Friday.",
	"shows nothing": "No violation detected. Suspicious, but legal.",
	"false": "Be nice. They were probably just excited about a rumor.",
	"DISMISS": "The rarest sound in an HOA: 'never mind'.",
	"warning gives": "Where fines go to think about what they've done.",
	"Evening": "A long day of measuring things. Congratulations.",
	"morning report": "Overnight developments: mostly gossip, partially legal.",
	"REINSPECT": "Yes, you have to go back. Yes, the grass noticed.",
	"unchanged": "Bold strategy: ignore the notice. Let's see how it plays out.",
	"close the case": "Mercy, quietly, is allowed.",
	"Take it to the board": "Brace for minutes. They will be taken. Forever.",
	"hearing": "Where everyone is fine and no one is happy.",
	"recommendation": "The board will pretend to think about it.",
	"Five board": "Five opinions, three agendas, one sleeve of cookies.",
	"treasurer": "Counsel's favorite phrase: 'I would not say that on the record.'",
	"Treasury is dollars": "Spend it like it belongs to people who read the minutes.",
	"BOARD and LEGAL": "Two numbers that can end your career. Enjoy.",
	"WOZIG PORTAL": "Powered by Wozig, because paper cuts are a liability.",
	"records system": "Every residents' secret, filed under 'Miscellaneous'.",
	"Overview": "Charts, because feelings alone didn't pass the vote.",
	"Board:": "Five people, one gavel, zero patience.",
	"Finance": "Every dollar, tracked. Every dollar, judged.",
	"Directory": "Know your neighbors. Know their opinions. Know their dog.",
	"Work orders": "Things that are 'almost done' since March.",
	"Requests": "Colors, fences, flamingos. All of them urgent.",
	"Selective enforcement": "Equal treatment: a surprisingly hard concept for neighbors.",
	"annual meeting": "Free coffee. Mandatory feelings.",
	"Votes are shown": "Democracy, with refreshments.",
	"Spring": "Pollen: nature's way of filing a complaint.",
	"Summer": "Sprinklers and pool noodles: the leading causes of consequences.",
	"Fall": "Leaf blowers: because silence was a violation.",
	"Winter": "The grass is dormant. The neighbors are not.",
	"Weekends": "Weekdays: trucks. Weekends: opinions with lawn chairs.",
	"That's it": "You may now sit through a very long meeting.",
}

const MainScene := preload("res://scenes/main.tscn")
const LotSlots := preload("res://scripts/world/lot_slots.gd")

var main: Node
var street: Control
var hud: Control
var sim
var video := 1
var _layer: CanvasLayer
var _caption: Label
var _aside: Label
var _caption_box: PanelContainer
var _finger: Control
var _card: ColorRect


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("video="):
			video = int(arg.substr(6))
	main = MainScene.instantiate()
	add_child(main)
	_build_overlay()
	await wait(0.5)
	sim = main.sim
	street = main._street
	hud = street.hud_view
	sim.rng.seed = 7000 + video
	match video:
		1:
			await video_getting_around()
		2:
			await video_inspecting()
		3:
			await video_case_sheet()
		4:
			await video_followups()
		5:
			await video_politics()
		6:
			await video_seasons()
	await end_card()
	get_tree().quit()


# ---------------------------------------------------------------- overlay helpers

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_caption_box = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.12, 0.86)
	style.set_corner_radius_all(22)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_caption_box.add_theme_stylebox_override("panel", style)
	_caption_box.position = Vector2(40, 470)
	_caption_box.custom_minimum_size = Vector2(640, 0)
	_caption_box.visible = false
	_layer.add_child(_caption_box)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_caption_box.add_child(rows)
	_caption = Label.new()
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.custom_minimum_size = Vector2(592, 0)
	_caption.add_theme_font_size_override("font_size", 32)
	_caption.add_theme_color_override("font_color", Color.WHITE)
	rows.add_child(_caption)
	_aside = Label.new()
	_aside.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_aside.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aside.custom_minimum_size = Vector2(592, 0)
	_aside.add_theme_font_size_override("font_size", 24)
	_aside.add_theme_color_override("font_color", Color("ffd36e"))
	rows.add_child(_aside)
	_finger = Control.new()
	_finger.visible = false
	_finger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finger.draw.connect(func():
		_finger.draw_circle(Vector2.ZERO, 38.0, Color(1, 1, 1, 0.35))
		_finger.draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 4.0)
		_finger.draw_circle(Vector2.ZERO, 12.0, Color(1, 1, 1, 0.8)))
	_layer.add_child(_finger)
	_card = ColorRect.new()
	_card.color = Color("1d3340")
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.visible = false
	_layer.add_child(_card)


## Counts *drawn* frames, not process ticks: when macOS stops drawing a covered window
## the script pauses with it instead of racing ahead of the recording.
func wait(seconds: float) -> void:
	var target := Engine.get_frames_drawn() + int(seconds * FPS)
	var started := Time.get_ticks_msec()
	while Engine.get_frames_drawn() < target:
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 120000:
			break


func say(text: String, seconds := 3.0) -> void:
	print("STEP %.1fs  %s" % [float(Engine.get_frames_drawn()) / FPS, text])
	_caption.text = text
	_aside.text = ""
	for key in ASIDES:
		if text.contains(key):
			_aside.text = "(%s)" % ASIDES[key]
			break
	_aside.visible = _aside.text != ""
	_caption_box.visible = true
	_caption_box.size = Vector2(640, 0)
	if seconds > 0.0:
		await wait(seconds + (1.2 if _aside.visible else 0.0))


func hush() -> void:
	_caption_box.visible = false


func title_card(title: String, subtitle: String, seconds := 3.0) -> void:
	for child in _card.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	_card.add_child(box)
	for spec in [["HOA PRESIDENT", 40, Color("ffd36e")], [title, 62, Color.WHITE], [subtitle, 30, Color("b9d8e8")],
			["Developed by ITSpector LLC  ·  Community management powered by Wozig", 20, Color(1, 1, 1, 0.6)]]:
		var label := Label.new()
		label.text = str(spec[0])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(620, 0)
		label.add_theme_font_size_override("font_size", int(spec[1]))
		label.add_theme_color_override("font_color", spec[2])
		box.add_child(label)
	_card.visible = true
	hush()
	await wait(seconds)
	_card.visible = false


func end_card() -> void:
	await title_card("That's it!", "Replay any step from the MENU › HOW TO PLAY screen.", 2.5)


func g(local: Vector2) -> Vector2:
	return street.global_position + local


## HUD controls live in street-local coordinates.
func shutter_pos() -> Vector2:
	return Vector2(street.size.x - 66.0, street.size.y - 72.0)


func album_pos() -> Vector2:
	return Vector2(street.size.x - 66.0, street.size.y - 172.0)


func cart_button_pos() -> Vector2:
	return Vector2(street.size.x - 66.0, street.size.y - 262.0)


func tap_hud(local: Vector2) -> void:
	await tap_marker(g(local))
	hud.handle_tap(local)
	await wait(0.3)


## Rebuilds the street's per-lot visuals after the director edits a complaint.
func refresh_visuals() -> void:
	var visuals := {}
	for h in sim.assignments:
		visuals[int(h)] = sim.assignments[h].violations
	street.set_day(street.pins, main._grass, sim.completed.size(), street.player.position, {}, visuals)


## Makes sure lot `h` is a clear example: a real violation, or a false complaint.
func ensure_case(h: int, real: bool) -> void:
	var a: Dictionary = sim.assignments[h]
	a.false_complaint = not real
	for v in a.violations:
		v.actual = real
	refresh_visuals()


## A finger ring appears at `pos`, taps, and fades.
func tap_marker(pos: Vector2, seconds := 0.55) -> void:
	_finger.position = pos
	_finger.visible = true
	_finger.queue_redraw()
	await wait(seconds)
	_finger.visible = false


func press(button: Button, seconds := 0.55) -> void:
	await tap_marker(button.get_global_rect().get_center(), seconds)
	button.pressed.emit()
	await wait(0.4)


func find_button(root: Node, text_part: String) -> Button:
	if root is Button and str((root as Button).text).contains(text_part) and not (root as Button).disabled:
		return root
	for child in root.get_children():
		var found := find_button(child, text_part)
		if found != null:
			return found
	return null


func find_all(root: Node, type_name: String, out: Array) -> void:
	if root.is_class(type_name):
		out.append(root)
	for child in root.get_children():
		find_all(child, type_name, out)


## Show the virtual stick while walking, exactly as a player would see it.
func walk_to(target: Vector2, cap_seconds := 40.0) -> void:
	var path: PackedVector2Array = street.hood.find_path(street.player.position, target)
	var anchor := Vector2(360, 1180)
	var frames := 0
	var index := 0
	var drawn_start := Engine.get_frames_drawn()
	street.used = true
	street.dragging = true
	street.anchor = anchor
	while index < path.size() and frames < cap_seconds * FPS:
		var waypoint: Vector2 = path[mini(index + 2, path.size() - 1)]
		if street.player.position.distance_to(waypoint) < 18.0:
			index += 1
			continue
		var dir: Vector2 = (waypoint - street.player.position).normalized()
		street.stick = dir
		street.finger = anchor + dir * 70.0
		await get_tree().process_frame
		frames = Engine.get_frames_drawn() - drawn_start
	street.stick = Vector2.ZERO
	street.dragging = false


## Rules on every remaining assignment without touching the overlay, so the evening
## panel appears on its own once the last case is done.
func complete_rest() -> void:
	for h in sim.assignments.keys():
		if not int(h) in sim.completed:
			main._active = int(h)
			if str(sim.assignments[h].kind) == "reinspect":
				main._on_reinspection_choice("close")
			else:
				main._on_case_ruled("dismiss", [])


func finish_quietly(except: int) -> void:
	for h in sim.assignments.keys():
		if int(h) != except and not int(h) in sim.completed:
			main._active = int(h)
			if str(sim.assignments[h].kind) == "reinspect":
				main._on_reinspection_choice("close")
			else:
				main._on_case_ruled("dismiss", [])
	main._close_overlay()


func pick_case(want_real: bool, want_card := true) -> int:
	for h in sim.assignments.keys():
		var a: Dictionary = sim.assignments[h]
		if str(a.kind) == "reinspect" or (want_card and str(a.kind) != "card"):
			continue
		var v: Dictionary = a.violations[0]
		if bool(a.false_complaint) != want_real and not (v.id in LotSlots.HOUSE_IDS):
			return int(h)
	return int(sim.assignments.keys()[0])


func begin_game(skip_title := true) -> void:
	if skip_title and is_instance_valid(main._title):
		main._title.queue_free()
		main._title = null
	GameState.clear_run()
	Settings.tutorial_done = true
	main._events.clear()   # no surprise agenda cards in the middle of a lesson
	main._begin(false)
	await wait(1.0)
	main._close_overlay()


func open_overlay_ready() -> void:
	await wait(0.8)


# ---------------------------------------------------------------- video 1

func video_getting_around() -> void:
	await title_card("Getting Around", "Training 1 of 6: walking, maps and the golf cart", 3.0)
	await say("This is the HOA President title screen. Tap NEW TERM to begin.", 3.0)
	await tap_marker(Vector2(360, 740))
	await begin_game(true)
	await say("You are the inspector, standing on Maple Grove Lane. Gold pins are complaints.", 3.5)
	await say("Drag anywhere on the street to walk. The stick appears under your thumb.", 3.0)
	var start: Vector2 = street.player.position
	await walk_to(start + Vector2(10, -500), 9.0)
	await say("Stay on sidewalks and driveways. Houses, cars and fences are solid.", 3.5)
	await say("Quick taps press buttons. Dragging only ever walks, so you never inspect by accident.", 4.0)
	await say("The minimap shows nearby roads and your cases. Tap it to open the full map.", 3.0)
	await tap_hud(hud.minimap_rect().get_center())
	await wait(1.2)
	await say("The full map shows every street, home and case. Drag to scroll.", 3.5)
	hud.handle_drag(Vector2(0, -260))
	await wait(1.0)
	await say("Tap a case to make it your destination. The Next line follows you.", 3.5)
	var target: int = street.objective
	var lot = street.hood.lots[target]
	var view: Rect2 = hud._map_view()
	var scale: float = view.size.x / street.hood.WORLD_W
	hud.map_scroll = clampf(lot.center.y * scale - view.size.y * 0.5, 0.0, 99999.0)
	await wait(0.5)
	var map_pos: Vector2 = view.position + Vector2(lot.center.x * scale, lot.center.y * scale - hud.map_scroll)
	await tap_marker(g(map_pos))
	hud.handle_tap(map_pos)
	await wait(1.0)
	await say("The golf cart is faster, but it stays on the road. Tap CART beside it to hop in.", 4.0)
	street.player.position = street.cart_pos + Vector2(30, 0)
	await wait(0.4)
	await tap_marker(g(cart_button_pos()))
	street.toggle_cart()
	await wait(0.8)
	await say("Driving to the next case.", 2.0)
	hush()
	await walk_to(lot.curb, 25.0)
	await say("Carts can't go up driveways. Tap CART again to park it and step out.", 3.5)
	await tap_marker(g(cart_button_pos()))
	street.toggle_cart()
	await wait(1.0)
	await say("The cart stays where you leave it. Walk back to it to drive again.", 3.5)
	hush()


# ---------------------------------------------------------------- video 2

func video_inspecting() -> void:
	await title_card("Inspecting and Photographing", "Training 2 of 6: evidence wins cases", 3.0)
	await begin_game(true)
	var house := int(sim.assignments.keys()[0])
	sim.assignments[house].kind = "card"
	street.pins[house] = "card"
	ensure_case(house, true)
	var lot = street.hood.lots[house]
	street.set_objective(house)
	await say("A complaint is not proof. Walk to the gold pin and see for yourself.", 3.5)
	hush()
	street.player.position = lot.curb + lot.front * 280.0
	await wait(0.3)
	await walk_to(lot.driveway_mid(), 30.0)
	await say("Near a complaint, the address and status appear with an INSPECT button.", 3.5)
	await say("First, gather evidence. Tap the camera.", 2.0)
	await tap_hud(shutter_pos())
	await wait(1.2)
	await say("Center the house in the frame. The meter shows photo quality.", 3.5)
	await say("Distance, framing, zoom, trees in the way and daylight all count.", 3.5)
	await tap_marker(g(hud._zoom_buttons().plus.get_center()))
	street.camera_ev.zoom = 1.9
	await wait(1.0)
	await say("Zoom with + and −. Around 1.4x to 2x works best.", 3.0)
	street.camera_ev.zoom = 1.4
	await wait(0.8)
	if bool(street.frame_info.get("potential", false)):
		await say("'Potential evidence detected' means something worth recording is in frame. It never says what.", 4.5)
	else:
		await say("Nothing worth recording is framed yet. Move closer or recenter.", 3.0)
	await say("Tap the shutter to take the photo.", 2.0)
	await tap_hud(shutter_pos())
	await wait(2.5)
	await say("The game tells you what the photo recorded.", 3.0)
	await say("A blurry or distant shot is rejected. Duplicates are blocked too.", 3.5)
	await say("Open the ALBUM to review photos.", 2.5)
	await tap_hud(album_pos())
	await wait(1.5)
	await say("Each photo shows address, day, quality and what it documents.", 3.5)
	await tap_hud(Vector2(180, 240))
	await wait(1.5)
	await say("Open a photo to set it as the best shot or delete it. You can keep up to six.", 4.0)
	hud.gallery_open = false
	hud.gallery_sel = -1
	await wait(0.5)
	hush()


# ---------------------------------------------------------------- video 3

func take_photo_quick(house: int) -> void:
	street.player.position = street.hood.lots[house].driveway_mid()
	await wait(0.4)
	street.open_camera()
	await wait(1.0)
	for zoom in [1.4, 1.0, 1.8, 2.2]:
		street.camera_ev.zoom = zoom
		await wait(0.5)
		if bool(street.frame_info.get("potential", false)):
			break
	await street.take_photo()
	await wait(0.5)


func video_case_sheet() -> void:
	await title_card("The Case Sheet", "Training 3 of 6: judge the facts, then decide", 3.0)
	await begin_game(true)
	var keys: Array = sim.assignments.keys()
	var real := int(keys[0])
	var fake := int(keys[1])
	for h in [real, fake]:
		sim.assignments[h].kind = "card"
		main._grass[h] = 3.0
		street.pins[h] = "card"
	ensure_case(real, true)
	ensure_case(fake, false)
	finish_quietly_keep([real, fake])
	await say("Case 1. Photograph first, then open the case sheet.", 3.0)
	await take_photo_quick(real)
	street.set_objective(real)
	hush()
	await tap_marker(g(hud.prompt_rect.get_center() if hud.prompt_rect.has_area() else Vector2(120, 1000)))
	main._on_visit(real)
	await wait(1.5)
	await say("PROPERTY: who lives here, how they feel about you, and any history.", 4.0)
	await say("COMPLAINT: who filed it. Source reliability tells you how much to trust it.", 4.0)
	await say("OBSERVATIONS: your photos and what they recorded.", 3.5)
	await say("POSSIBLE VIOLATIONS: tick only what you can support. Each shows the rule.", 4.0)
	await say("ACTION: the HOA process decides what's allowed.", 3.0)
	await say("A first notice must be a warning. Fines need a prior warning and usable evidence.", 4.5)
	var panel = main._overlay.get_child(0)
	var warning := find_button(panel, "WARNING")
	if warning != null:
		await say("Issue a WARNING. It starts a cure period.", 2.5)
		await press(warning)
	await wait(2.0)
	await say("Points reward correct, well-documented decisions.", 3.0)
	main._close_overlay()
	await say("Case 2. This complaint may be wrong. Photograph it.", 3.5)
	street.set_objective(fake)
	await take_photo_quick(fake)
	main._on_visit(fake)
	await wait(1.5)
	await say("The photo shows nothing there. Observations say so.", 4.0)
	await say("Complaints can be false. Citing something you can't prove costs you.", 4.0)
	panel = main._overlay.get_child(0)
	var dismiss := find_button(panel, "DISMISS")
	if dismiss != null:
		await say("DISMISS the complaint. Dismissing a false one scores well and calms the neighbors.", 4.0)
		await press(dismiss)
	await wait(2.0)
	hush()


func finish_quietly_keep(keep: Array) -> void:
	for h in sim.assignments.keys():
		if not int(h) in keep and not int(h) in sim.completed:
			main._active = int(h)
			main._on_case_ruled("dismiss", [])
	main._close_overlay()
	main._phase = "street"
	sim.completed = sim.completed.filter(func(h): return not int(h) in keep)
	for h in keep:
		street.pins[int(h)] = str(sim.assignments[int(h)].kind)


# ---------------------------------------------------------------- video 4

## Clears whatever modal is up the way a player would, narrating the known ones.
func tap_through_panels(narrate := true) -> void:
	for i in 12:
		await wait(0.8)
		if not main._overlay.visible or main._overlay.get_child_count() == 0:
			return
		var panel: Node = main._overlay.get_child(0)
		if panel.has_signal("decided"):
			if narrate:
				await say("The hearing: the homeowner's argument, the file, and the staff recommendation.", 4.5)
				await say("You make the recommendation. Presenting strong photos adds weight.", 4.0)
			var fine_button := find_button(panel, "FINE")
			if fine_button != null:
				await press(fine_button)
		elif panel.has_signal("closed"):
			if narrate:
				await say("Five board members vote, each with their own priorities.", 4.0)
				await say("The treasurer likes revenue, the advocate hates fines, counsel watches the evidence.", 4.5)
			var go := find_button(panel, "CONTINUE")
			if go != null:
				await press(go)
		else:
			var next := find_button(panel, "NEXT DAY")
			if next == null:
				next = find_button(panel, "CONTINUE")
			if next == null:
				return
			await press(next)


func video_followups() -> void:
	await title_card("Follow-Ups", "Training 4 of 6: cure periods, reinspection and hearings", 3.0)
	await begin_game(true)
	var house := int(sim.assignments.keys()[0])
	sim.assignments[house].kind = "card"
	street.pins[house] = "card"
	ensure_case(house, true)
	finish_quietly_keep([house])
	await say("A warning gives the homeowner a cure period to fix the problem.", 3.5)
	await take_photo_quick(house)
	hush()
	main._on_visit(house)
	await wait(1.0)
	var first_id := str(sim.assignments[house].violations[0].id)
	main._on_case_ruled("warning", [first_id])
	await wait(1.5)
	await say("Finish the day's last case and the day ends.", 3.0)
	await say("Evening: your day bonus and any open cases.", 3.5)
	hush()
	sim.cases[house].cure_due = GameState.day + 1
	var evening := find_button(main._overlay, "NEXT DAY")
	if evening != null:
		await press(evening)
	await wait(1.5)
	# Morning: report, then the reinspection appears.
	for i in 3:
		if main._overlay.visible and main._overlay.get_child_count() > 0:
			var go := find_button(main._overlay.get_child(0), "CONTINUE")
			if go != null:
				if i == 0:
					await say("The morning report summarises overnight developments.", 3.5)
				await press(go)
				await wait(0.8)
	if not sim.assignments.has(house) or str(sim.assignments[house].kind) != "reinspect":
		print("TRAINING: reinspection did not appear")
		return
	sim.assignments[house].result = "unchanged"
	sim.cases[house].reinspect_result = "unchanged"
	for v in sim.assignments[house].violations:
		v.actual = true
		v.borderline = false
	refresh_visuals()
	street.set_objective(house)
	await say("The cure period ended. A REINSPECT pin appears. You must walk back and look.", 4.5)
	hush()
	var lot = street.hood.lots[house]
	street.player.position = lot.curb + lot.front * 220.0
	await walk_to(lot.driveway_mid(), 20.0)
	await wait(0.4)
	main._on_visit(house)
	await wait(1.5)
	await say("Fixed, partly fixed, unchanged or worse. Here it is unchanged.", 4.0)
	await say("You can close the case, extend the cure period, schedule a hearing or fine.", 4.5)
	var hearing := find_button(main._overlay, "SCHEDULE HEARING")
	if hearing != null:
		await say("Take it to the board.", 2.0)
		await press(hearing)
	await wait(1.5)
	hush()
	# Day ends again; tomorrow morning the hearing is held.
	await say("Finish the rest of the day, and tomorrow's morning meeting hears the case.", 3.5)
	hush()
	complete_rest()
	await wait(1.0)
	await tap_through_panels(true)
	await wait(1.0)
	hush()


# ---------------------------------------------------------------- video 5

func video_politics() -> void:
	await title_card("Board, Politics and the Portal", "Training 5 of 6: keep your seat", 3.0)
	await begin_game(true)
	finish_quietly_keep([])
	await say("Your treasury is dollars. Community and Authority sit beside it.", 4.0)
	await say("BOARD and LEGAL RISK live under them. Both can end your term.", 4.0)
	await say("Open the MENU, then the WOZIG PORTAL.", 3.0)
	await tap_marker(Vector2(90, 305))
	main._open_menu()
	await wait(1.0)
	var portal_button := find_button(main._modal, "WOZIG PORTAL")
	if portal_button != null:
		await press(portal_button)
	await wait(1.0)
	await say("The portal is Wozig's records system for your HOA.", 3.5)
	var portal = main._modal.get_child(0)
	for tab in [["OVERVIEW", "Overview: stats, plus enforcement balance by group. Big gaps invite lawsuits."],
			["BOARD", "Board: five people with priorities. Their support decides elections."],
			["FINANCE", "Finance: every fine, due and settlement as dollars."],
			["DIRECTORY", "Directory: every resident and how they feel about you."],
			["WORK ORDERS", "Work orders: vendor and community projects in progress."],
			["REQUESTS", "Requests: the agenda decisions you've made."]]:
		var button := find_button(portal, str(tab[0]))
		if button != null:
			await press(button, 0.4)
			await say(str(tab[1]), 3.5)
	var close := find_button(portal, "CLOSE")
	if close != null:
		await press(close)
	await say("Selective enforcement is tracked. Cite critics harder than friends and counsel will warn you.", 5.0)
	main._close_modal()
	await say("Every ten days is the annual meeting. Each member votes on keeping you.", 4.0)
	GameState.day = 9
	finish_quietly_keep([])
	main._phase = "evening"
	GameState.next_day()
	main._new_day()
	await wait(1.5)
	var guard := 0
	while main._overlay.visible and guard < 6:
		guard += 1
		var panel2 = main._overlay.get_child(0) if main._overlay.get_child_count() > 0 else null
		if panel2 != null and panel2.has_signal("closed"):
			await say("Votes are shown member by member, with their reasons.", 4.5)
		var go := find_button(main._overlay, "CONTINUE")
		if go != null:
			await press(go)
		else:
			break
	hush()


# ---------------------------------------------------------------- video 6

func video_seasons() -> void:
	await title_card("The Neighborhood", "Training 6 of 6: seasons, weekdays and daily life", 3.0)
	await begin_game(true)
	street.debug_scale = 1.15
	var hood = street.hood
	var spots := [["Spring: tulips, fresh lawns and rain.", 1], ["Summer: sprinklers, pool swimmers and more neighbors outside.", 15],
			["Fall: leaf piles and landscapers with leaf blowers.", 29], ["Winter: snow on the roofs, holiday lights and dormant grass.", 43]]
	for item in spots:
		GameState.day = int(item[1])
		main._new_day()
		finish_quietly_keep([])
		main._close_overlay()
		if street._dusk_tween:
			street._dusk_tween.kill()
		street.dusk = 0.0   # finishing cases brings evening on; show each season in daylight
		street.player.position = hood.streets[1].bulbs[0].center + Vector2(60, 120)
		await say(str(item[0]), 6.0)
		hush()
		street.stick = Vector2(0.5, -0.3)
		street.dragging = true
		street.anchor = Vector2(360, 1180)
		street.finger = Vector2(400, 1160)
		await wait(4.0)
		street.stick = Vector2.ZERO
		street.dragging = false
	await say("Weekends bring more neighbors and kids; weekdays bring delivery trucks and crews. Garbage trucks run Tuesday and Thursday.", 6.0)
	hush()
