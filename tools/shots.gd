extends Node
## Visual QA harness: boots the real game, forces states and writes PNGs.
##   HOME=<scratch> godot --path . res://tools/shots.tscn -- out=/path/dir [shots=a,b,c]
## Needs a real renderer (not --headless). Uses a throwaway profile via HOME.

const MainScene := preload("res://scenes/main.tscn")
const EncounterPanel := preload("res://scripts/ui/encounter_panel.gd")

var out := "/tmp"
var main: Node
var street: Node


func _ready() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.substr(4)
		elif arg.begins_with("shots="):
			only = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	Settings.tutorial_done = true
	main = MainScene.instantiate()
	add_child(main)
	for i in 10:
		await get_tree().process_frame
	street = main._street
	var list: Array = (only.split(",") if only != "" else ["title", "street", "hud_stats", "cul_de_sac", "weather", "seasons", "encounters", "menus", "maps", "flow", "life", "card", "walk", "markers", "sign"])
	for name in list:
		await call("_shot_" + name)
	get_tree().quit()


func _snap(name: String, settle := 12) -> void:
	for i in settle:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("SHOT ", name, " ", img.get_size())


func _begin() -> void:
	main._begin(false)
	for i in 6:
		await get_tree().process_frame
	# Dismiss morning brief and any modals.
	for i in 4:
		main._close_overlay()
		await get_tree().process_frame


func _teleport(p: Vector2) -> void:
	street.player.position = p
	street.cam = p - street.size * 0.5
	street._cam_ready = false


func _shot_title() -> void:
	await _snap("01_title", 20)


func _shot_street() -> void:
	await _begin()
	await _snap("02_street_start", 30)


func _shot_hud_stats() -> void:
	main._details.show()
	await _snap("03_hud_stats", 8)
	main._details.hide()


func _shot_cul_de_sac() -> void:
	await _ensure_started()
	var lot = null
	for l in street.hood.lots:
		if l.kind == "cul_de_sac":
			lot = l
			break
	_teleport(lot.inspect_anchor())
	await _snap("04_cul_de_sac", 40)
	var corner = null
	for l in street.hood.lots:
		if l.kind == "corner":
			corner = l
			break
	if corner != null:
		_teleport(corner.inspect_anchor())
		await _snap("05_corner_lot", 40)


func _shot_weather() -> void:
	await _ensure_started()
	var lot = street.hood.lots[10]
	_teleport(lot.inspect_anchor())
	for kind in [0, 1, 2, 3, 4, 5, 6, 7]:
		street.weather = kind
		await _snap("06_weather_%d" % kind, 12)


func _shot_seasons() -> void:
	await _ensure_started()
	street.weather = 0
	for season in 4:
		street.season = season
		street.world_view.invalidate()
		await _snap("07_season_%d" % season, 60)


func _shot_encounters() -> void:
	var enc = main.sim.encounters
	var lot = street.hood.lots[10]
	var styles: Array = street.world_view.styles()
	for e: Dictionary in enc.catalog:
		var panel := EncounterPanel.new()
		panel.size = main.size
		panel.setup(e, "Dana Whitaker", lot.address, 7, styles[10].wall, styles[10].roof, {"favored": "Pat Example"})
		main.add_child(panel)
		for i in 20:
			await get_tree().process_frame
		# Advance to the staging peak for multi-prop scenes.
		for k in (e.lines as Array).size() - 1:
			panel._advance()
			for i in 4:
				await get_tree().process_frame
		for i in 10:
			await get_tree().process_frame
		panel._text.visible_ratio = 1.0
		await _snap("enc_%s" % str(e.id), 4)
		panel.queue_free()
		await get_tree().process_frame


func _ensure_started() -> void:
	if main.sim.assignments.is_empty():
		await _begin()


func _shot_menus() -> void:
	await _ensure_started()
	main._open_menu()
	await _snap("08_menu", 6)
	main._close_modal()
	main._show_modal(preload("res://scripts/ui/menu_panels.gd").settings(main.size, main._close_modal, func(): pass))
	await _snap("09_settings", 6)
	main._close_modal()
	main._open_communities()
	await _snap("10_communities", 6)
	main._close_modal()
	main._open_portal("cases")
	await _snap("11_portal_cases", 6)
	main._close_modal()
	main._show_modal(preload("res://scripts/ui/menu_panels.gd").how_to_play(main.size, main._close_modal))
	await _snap("12_training", 6)
	main._close_modal()
	main._show_modal(preload("res://scripts/ui/menu_panels.gd").about(main.size, main._close_modal))
	await _snap("13_about", 6)
	main._close_modal()


func _shot_maps() -> void:
	await _ensure_started()
	street.hud_view.open_map()
	await _snap("14_full_map", 10)
	street.hud_view.map_open = false


func _cited(house: int) -> Array:
	var ids: Array = []
	for v in main.sim.assignments[house].violations:
		ids.append(str(v.id))
	return ids


func _first_house(kind := "") -> int:
	for h in main.sim.assignments:
		if kind == "" or str(main.sim.assignments[h].kind) == kind:
			return int(h)
	return -1


func _shot_flow() -> void:
	await _ensure_started()
	# Morning brief.
	main._new_day()
	await _snap("20_brief", 8)
	main._close_overlay()
	await get_tree().process_frame
	var h := _first_house()
	main._visited[h] = true
	_teleport(street.hood.lots[h].inspect_anchor())
	await _snap("21_at_property", 30)
	street.open_camera()
	await _snap("22_camera_frame", 40)
	street.camera_ev.active = false
	await street.take_photo()
	street.camera_ev.active = false
	await _snap("23_after_photo", 10)
	main._on_visit(h)
	await get_tree().process_frame
	await _snap("24_case_sheet", 10)
	main._close_overlay()
	# Warning, then advance until reinspection.
	main.sim.rule_case(h, "warning", _cited(h), main._evidence_for(h))
	main.sim.completed = main.sim.assignments.keys()
	for d in 6:
		GameState.next_day()
		main._new_day()
		await get_tree().process_frame
		main._close_overlay()
		if _first_house("reinspect") >= 0:
			break
	if _first_house("reinspect") < 0:
		for hk in main.sim.cases:
			main.sim.cases[hk].cure_due = GameState.day
		GameState.next_day()
		main._new_day()
		await get_tree().process_frame
		main._close_overlay()
	var r := _first_house("reinspect")
	if r >= 0:
		main._visited[r] = true
		_teleport(street.hood.lots[r].inspect_anchor())
		main._on_visit(r)
		await _snap("25_reinspect", 10)
		main._close_overlay()
	# Hearing + vote.
	var hh := _first_house()
	if hh >= 0 and not main.sim.cases.has(hh):
		main.sim.rule_case(hh, "warning", _cited(hh), main._evidence_for(hh))
	if hh >= 0:
		main.sim.cases[hh].state = "hearing"
		main.sim.cases[hh].hearing_day = GameState.day
		main._run_hearing(hh)
		await _snap("26_hearing", 10)
		for child in main._overlay.get_children():
			if child.has_signal("decided"):
				child.decided.emit("fine", true)
		await _snap("27_vote", 10)
		main._close_overlay()
	# Board call, agenda card, evening, term complete.
	GameState.day = 8
	for i in 60:
		main._overlay.hide()
		main._maybe_board_call()
		await get_tree().process_frame
		if main._overlay.visible:
			break
	await _snap("28_board_call", 8)
	main._close_overlay()
	for i in 60:
		main._overlay.hide()
		main._maybe_event()
		await get_tree().process_frame
		if main._overlay.visible:
			break
	await _snap("29_agenda_card", 14)
	main._close_overlay()
	main._show_evening(1, {"day_bonus": 60, "balance_bonus": 30})
	await _snap("30_evening", 8)
	main._close_overlay()
	main._show_term_complete()
	await _snap("31_term_complete", 8)
	main._close_overlay()
	main._run_meeting(main.sim.board.election(main.sim.politics, 50, main.sim.rng))
	await _snap("32_meeting", 10)
	main._close_overlay()


func _shot_life() -> void:
	await _ensure_started()
	var h := _first_house()
	main._visited[h] = true
	_teleport(street.hood.lots[h].inspect_anchor() + Vector2(0, 60))
	await _snap("40_near_porch", 120)
	street.player.cart = true
	street.cart_fx = 1.0
	await _snap("41_cart", 20)
	street.player.cart = false
	# Side street with visitor cars: look at each mover.
	for m in street.ambient.movers:
		var lot = street.hood.lots[int(m.lot)]
		street.ambient.time = 10.0 - float(m.t0) + 40.0
		_teleport(lot.curb)
		await _snap("42_mover_%d" % int(m.lot), 30)
		break
	street.weather = 0
	street.user_zoom = 0.6
	street.zoom_input.target = 0.6
	await _snap("43_zoom_out", 60)
	street.zoom_input.target = 1.7
	await _snap("44_zoom_in", 60)


func _press(text: String, node: Node = null) -> bool:
	node = node if node != null else main
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		(node as Button).pressed.emit()
		return true
	for child in node.get_children():
		if _press(text, child):
			return true
	return false


func _shot_card() -> void:
	await _ensure_started()
	main.sim.encounters.catalog = []
	var h: int = street.objective
	main._visited[h] = true
	_teleport(street.hood.lots[h].inspect_anchor())
	await _snap("50_arrival", 40)
	street.inspect_near()
	await _snap("51_card", 20)
	if is_instance_valid(main._card_ui):
		print("CARD rect ", main._card_ui.get_global_rect(), " sheet ", main._card_ui._sheet.get_global_rect(), " vis ", main._card_ui.visible, " z ", main._card_ui.z_index)
	_press("VIEW COMPLAINT")
	await _snap("52_card_details", 10)
	_press("HIDE DETAILS")
	_press("TAKE PHOTO")
	await _snap("53_camera", 40)
	for zoom in [1.4, 1.0, 1.8, 2.2]:
		street.camera_ev.zoom = zoom
		for i in 18:
			await get_tree().process_frame
		if bool(street.frame_info.get("potential", false)):
			break
	await street.take_photo()
	await _snap("54_preview", 12)
	_press("USE PHOTO")
	await _snap("55_card_evidence", 12)
	_press("REVIEW & DECIDE")
	await _snap("56_case_sheet", 12)
	# Off-screen arrow: walk away from the selected property.
	main._close_overlay()
	main._close_property_card()
	_teleport(street.hood.lots[h].inspect_anchor() + Vector2(0, 700))
	street.objective = h
	await _snap("57_edge_arrow", 40)


func _shot_walk() -> void:
	await _ensure_started()
	main.sim.encounters.catalog = []
	# Wide sidewalks on the avenue and a cul-de-sac.
	var spine_pos: Vector2 = street.spawn_point()
	_teleport(spine_pos)
	await _snap("60_sidewalk_avenue", 40)
	# A sidewalk obstruction case, all five variants, one lot each.
	var variants := ["hedge", "branch", "bins", "debris", "materials"]
	var std: Array = []
	for l in street.hood.lots:
		if l.kind == "standard" and l.side != 0:
			std.append(l)
	var pins := {}
	var visuals := {}
	var def: Dictionary = main.sim.violations.get_def("sidewalk_obstruction")
	for i in variants.size():
		var item: Dictionary = main.sim.violations.make_allegation(def, 1.0, main.sim.rng, 1)
		item.object = variants[i]
		item.borderline = false
		var h: int = std[i].id
		main.sim.assignments[h] = {"kind": "card", "source": "resident", "complainant": "Resident", "violations": [item],
				"false_complaint": false, "status": "assigned", "text": str(item.complaint)}
		pins[h] = "card"
		visuals[h] = [item]
	street.set_day(pins, main._grass, 0, null, {}, visuals)
	street.objective = int(std[0].id)
	street.zoom_input.target = 1.6
	for i in 3:
		var l = std[i]
		_teleport(l.sidewalk_spot + Vector2(0, 80).rotated(l.front.angle() - PI / 2.0) * 0.0)
		main._visited[l.id] = true
		await _snap("61_obstruction_%s" % variants[i], 50)
	street.zoom_input.target = 1.0
	# Camera framing the obstruction itself.
	var l0 = std[0]
	_teleport(l0.inspect_anchor())
	street.objective = l0.id
	await _snap("64_obstruction_reached", 40)
	street.inspect_near()
	await get_tree().process_frame
	_press("TAKE PHOTO")
	for zoom in [1.4, 1.8, 2.2]:
		street.camera_ev.zoom = zoom
		for i in 18:
			await get_tree().process_frame
		if bool(street.frame_info.get("potential", false)):
			break
	await _snap("65_obstruction_camera", 20)
	print("WALK quality ", street.frame_info, " zoom ", street.camera_ev.zoom)


func _shot_markers() -> void:
	await _ensure_started()
	main.sim.encounters.catalog = []
	# One complaint and one reinspection side by side, selected and unselected.
	var lots: Array = []
	for l in street.hood.lots:
		if l.kind == "standard" and l.side != 0:
			lots.append(l)
	var a: int = lots[0].id
	var b: int = lots[1].id
	street.pins[a] = "card"
	street.pins[b] = "reinspect"
	street.objective = a
	street.zoom_input.target = 1.5
	_teleport(lots[0].inspect_anchor() + (lots[1].inspect_anchor() - lots[0].inspect_anchor()) * 0.5)
	await _snap("70_markers", 60)


func _shot_sign() -> void:
	await _ensure_started()
	var painter = street.world_view.painter
	for item in painter.furniture:
		if str(item.type) == "name":
			street.zoom_input.target = 1.7
			_teleport(item.pos + Vector2(0, 40))
			await _snap("71_street_sign", 60)
			break
