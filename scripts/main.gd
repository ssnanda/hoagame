extends Control
## Orchestrator: HUD, day loop, panels and saving. The rules live in sim/hoa_sim.gd,
## the neighborhood in world/*, and each screen in ui/*.

const CARD_SCENE := preload("res://scenes/card.tscn")
const STREET_SCRIPT := preload("res://scripts/street.gd")
const LAWN_SCRIPT := preload("res://scripts/lawn_game.gd")
const CASE_FILE_SCRIPT := preload("res://scripts/case_file.gd")
const HoaSim := preload("res://scripts/sim/hoa_sim.gd")
const Board := preload("res://scripts/sim/board.gd")
const Residents := preload("res://scripts/sim/residents.gd")
const UiKit := preload("res://scripts/ui/ui_kit.gd")
const MenuPanels := preload("res://scripts/ui/menu_panels.gd")
const PortalPanel := preload("res://scripts/ui/portal_panel.gd")
const ReinspectPanel := preload("res://scripts/ui/reinspect_panel.gd")
const HearingPanel := preload("res://scripts/ui/hearing_panel.gd")
const VotePanel := preload("res://scripts/ui/vote_panel.gd")

const CARD_SIZE := Vector2(600, 640)
const UPDATE_MANIFEST_URL := "https://raw.githubusercontent.com/ssnanda/hoagame/main/altstore.json"
const ALTSTORE_BUNDLE_ID := "com.ssnanda.hoagame"
const WORLD_VERSION := 7
const STAT_LABELS := {"budget": "TREASURY", "happiness": "COMMUNITY", "power": "AUTHORITY"}
const DOLLARS_PER_POINT := 690

var sim := HoaSim.new()

var _bars: Dictionary = {}
var _stat_labels: Dictionary = {}
var _day_label: Label
var _score_label: Label
var _best_label: Label
var _task_label: Label
var _politics_label: Label
var _version_label: Label
var _street: Control
var _margin: MarginContainer
var _overlay: ColorRect
var _card: Panel
var _over_panel: Control
var _over_label: Label
var _title: Control
var _modal: Control
var _menu_button: Button
var _is_over := false
var _active := -1
var _grass: Array = []
var _measurements: Dictionary = {}
var _phase := "street"
var _evening_bonus: Dictionary = {}
var _events: Array = []
var _morning_queue: Array = []
var _update_request: HTTPRequest
var _update_prompt: Control
var _available_version := ""
var _altstore_launch_pending := false


func _ready() -> void:
	_load_events()
	_build_ui()
	GameState.stats_changed.connect(_refresh)
	GameState.game_over.connect(_on_game_over)
	await get_tree().process_frame
	sim.setup(_street.house_count())
	_show_title()
	_check_for_updates()


# ---------------------------------------------------------------- title and menus

func _show_title() -> void:
	_close_overlay()
	if is_instance_valid(_title):
		_title.queue_free()
	_street.set_hint("")
	_title = MenuPanels.title_screen(size, GameState.has_saved_run, {
		"continue": func(): _begin(true),
		"new_term": func(): _begin(false),
		"howto": func(): _show_modal(MenuPanels.how_to_play(size, _close_modal)),
		"settings": func(): _show_modal(MenuPanels.settings(size, _close_modal, _reset_game)),
		"about": func(): _show_modal(MenuPanels.about(size, _close_modal)),
	})
	_title.z_index = 40
	add_child(_title)


func _begin(resume: bool) -> void:
	if is_instance_valid(_title):
		_title.queue_free()
		_title = null
	_is_over = false
	_over_panel.hide()
	if resume and GameState.has_saved_run:
		_resume_run()
	else:
		_start()


func _show_modal(panel: Control) -> void:
	_close_modal()
	_modal = ColorRect.new()
	(_modal as ColorRect).color = Color(0, 0, 0, 0.6)
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.z_index = 60
	_modal.add_child(panel)
	add_child(_modal)


func _close_modal() -> void:
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null


func _reset_game() -> void:
	_close_modal()
	GameState.clear_run()
	GameState.new_game()
	_show_title()


func _open_menu() -> void:
	var modal := UiKit.modal(size, Vector2(560, 640), "MENU")
	for item in [["RESUME", func(): _close_modal()], ["WOZIG PORTAL", func(): _open_portal()],
			["HOW TO PLAY", func(): _show_modal(MenuPanels.how_to_play(size, _close_modal))],
			["SETTINGS", func(): _show_modal(MenuPanels.settings(size, _close_modal, _reset_game))],
			["TITLE SCREEN", func():
				_close_modal()
				_save_progress()
				_show_title()]]:
		var btn := UiKit.button(str(item[0]), 28, 72)
		btn.pressed.connect(func():
			Sfx.play("tap")
			(item[1] as Callable).call())
		modal.body.add_child(btn)
	if OS.is_debug_build():
		var debug_button := UiKit.button("DEBUG VIEW: %s" % ("ON" if _street.debug_view else "OFF"), 22, 60)
		debug_button.pressed.connect(func():
			_street.debug_view = not _street.debug_view
			_close_modal())
		modal.body.add_child(debug_button)
	_show_modal(modal.root)


func _open_portal() -> void:
	var portal: Panel = PortalPanel.new()
	portal.setup(sim, _street)
	portal.closed.connect(_close_modal)
	_show_modal(portal)


# ---------------------------------------------------------------- update check

func _check_for_updates() -> void:
	_update_request = HTTPRequest.new()
	_update_request.timeout = 8.0
	add_child(_update_request)
	_update_request.request_completed.connect(_on_update_check_completed)
	var headers := PackedStringArray(["Cache-Control: no-cache", "Accept: application/json"])
	if _update_request.request(UPDATE_MANIFEST_URL, headers) != OK:
		_update_request.queue_free()


func _on_update_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if is_instance_valid(_update_request):
		_update_request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var source = JSON.parse_string(body.get_string_from_utf8())
	if not source is Dictionary:
		return
	for app in source.get("apps", []):
		if app is Dictionary and str(app.get("bundleIdentifier", "")) == ALTSTORE_BUNDLE_ID:
			var remote_version := str(app.get("version", ""))
			if _is_newer_version(remote_version, str(ProjectSettings.get_setting("application/config/version", "0.0.0"))):
				_available_version = remote_version
				_show_update_prompt(str(app.get("versionDescription", "")))
			return


func _is_newer_version(remote: String, local: String) -> bool:
	var remote_parts := remote.split(".")
	var local_parts := local.split(".")
	for i in maxi(remote_parts.size(), local_parts.size()):
		var remote_part := int(remote_parts[i]) if i < remote_parts.size() else 0
		var local_part := int(local_parts[i]) if i < local_parts.size() else 0
		if remote_part != local_part:
			return remote_part > local_part
	return false


func _show_update_prompt(description: String) -> void:
	if is_instance_valid(_update_prompt):
		return
	_update_prompt = ColorRect.new()
	(_update_prompt as ColorRect).color = Color(0, 0, 0, 0.76)
	_update_prompt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_update_prompt.z_index = 70
	add_child(_update_prompt)
	var modal := UiKit.modal(size, Vector2(600, 520), "UPDATE AVAILABLE")
	_update_prompt.add_child(modal.root)
	modal.body.add_child(UiKit.label("HOA President %s" % _available_version, 30, UiKit.ACCENT, true))
	if not description.is_empty():
		modal.body.add_child(UiKit.label(description, 22, UiKit.MUTED, true))
	modal.body.add_child(UiKit.label("AltStore will open. Choose Update in My Apps and keep AltServer running on your computer.", 20, UiKit.MUTED, true))
	var update_button := UiKit.button("OPEN ALTSTORE", 28, 76)
	update_button.pressed.connect(_open_altstore_update)
	modal.footer.add_child(update_button)
	var later := UiKit.button("LATER", 24, 62)
	later.pressed.connect(func():
		_update_prompt.queue_free()
		_update_prompt = null)
	modal.footer.add_child(later)


func _open_altstore_update() -> void:
	# Original scheme first; try AltStore Classic if this app is not backgrounded quickly.
	_altstore_launch_pending = true
	OS.shell_open("altstore://")
	get_tree().create_timer(0.65).timeout.connect(func():
		if _altstore_launch_pending:
			_altstore_launch_pending = false
			OS.shell_open("altstore-classic://"), CONNECT_ONE_SHOT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_altstore_launch_pending = false
		if is_instance_valid(_street) and not _is_over and not sim.assignments.is_empty():
			_save_progress()


func _unhandled_key_input(event: InputEvent) -> void:
	if _card == null or _is_over:
		return
	if event.is_action_pressed("ui_left"):
		_card.fling("left")
	elif event.is_action_pressed("ui_right"):
		_card.fling("right")


# ---------------------------------------------------------------- run lifecycle

func _start() -> void:
	_is_over = false
	_over_panel.hide()
	_close_overlay()
	GameState.clear_run()
	GameState.new_game()
	sim.new_term()
	_measurements = {}
	_new_day()


func _load_events() -> void:
	_events.clear()
	for path in ["res://data/events.json", "res://data/cards.json"]:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			_events.append_array(parsed)


func _new_day() -> void:
	var info := sim.start_day(GameState.day, GameState.season(), GameState.weekday())
	if _is_over:
		return
	var season := GameState.season()
	var growth: float = [1.0, 1.15, 0.9, 0.7][season]
	_grass = []
	for i in _street.house_count():
		_grass.append(randf_range(2.5, 4.5) * growth)
	_measurements = {}
	var pins := {}
	var visuals := {}
	for house in sim.assignments:
		var h := int(house)
		var a: Dictionary = sim.assignments[house]
		pins[h] = str(a.kind)
		visuals[h] = a.violations
		for v in a.violations:
			if str(v.id) == "tall_grass":
				_grass[h] = (randf_range(6.1, 6.4) if bool(v.borderline) else randf_range(6.8, 10.0)) if bool(v.actual) else randf_range(3.5, 5.4)
	for house in sim.discoverable:
		visuals[int(house)] = sim.discoverable[house]
	_phase = "street"
	_evening_bonus = {}
	_street.set_day(pins, _grass, 0, null, {}, visuals)
	_street.set_discoverable(sim.discoverable.keys())
	_street.set_case_states(sim.case_states())
	_update_task()
	_refresh()
	_save_progress()
	_morning_queue.clear()
	if not (info.report as Array).is_empty():
		Sfx.play("notify")
		_morning_queue.append(func(): _show_report("MORNING REPORT · DAY %d" % GameState.day, info.report, "CONTINUE"))
	for house in info.hearings:
		_morning_queue.append(_run_hearing.bind(int(house)))
	if not (info.meeting as Array).is_empty():
		_morning_queue.append(_run_meeting.bind(info.meeting))
	_morning_queue.append(_maybe_event)
	_next_morning_step()


func _next_morning_step() -> void:
	if _is_over or _morning_queue.is_empty():
		return
	var step: Callable = _morning_queue.pop_front()
	step.call()


func _resume_run() -> void:
	var world := GameState.saved_world()
	if not world.has("complaints") or not world.has("grass"):
		_start()
		return
	sim.load_world(world)
	if int(world.get("world_version", 1)) < 6:
		# Neighborhood rebuilt in world version 6: keep the term, drop lot-specific state.
		sim.properties = sim.residents.create(_street.house_count())
		sim.cases = {}
		_new_day()
		return
	_grass = (world.get("grass", []) as Array).duplicate()
	while _grass.size() < _street.house_count():
		_grass.append(randf_range(2.5, 4.5))
	_phase = str(world.get("phase", "street"))
	_evening_bonus = (world.get("evening_bonus", {}) as Dictionary).duplicate(true)
	_measurements = (world.get("measurements", {}) as Dictionary).duplicate(true)
	var pins := {}
	var visuals := {}
	for house in sim.assignments:
		var h := int(house)
		var a: Dictionary = sim.assignments[house]
		if not a.has("text"):
			a.text = str((a.get("card", {}) as Dictionary).get("text", "A complaint was filed."))
			sim.assignments[house] = a
		pins[h] = "done" if h in sim.completed else str(a.get("kind", "card"))
		visuals[h] = a.get("violations", [])
	for house in sim.discoverable:
		visuals[int(house)] = sim.discoverable[house]
	var saved_position = world.get("player_position", null)
	_street.set_day(pins, _grass, sim.completed.size(), saved_position, world.get("evidence", {}), visuals)
	_street.set_discoverable(sim.discoverable.keys())
	_street.set_case_states(sim.case_states())
	_street.set_cart_state(world.get("cart", {}))
	_update_task()
	_refresh()
	_float("WELCOME BACK", Color("ffd36e"))
	if _phase == "evening":
		_show_evening(GameState.day, _evening_bonus)


func _update_task() -> void:
	var left := sim.assignments.size() - sim.completed.size()
	_task_label.text = "%d assignment%s remaining" % [left, "" if left == 1 else "s"]


func _save_progress(show_feedback := false) -> void:
	if not is_instance_valid(_street) or sim.assignments.is_empty() or _is_over:
		return
	var world := {
		"world_version": WORLD_VERSION,
		"grass": _grass.duplicate(),
		"phase": _phase,
		"evening_bonus": _evening_bonus.duplicate(true),
		"evidence": _street.get_evidence(),
		"measurements": _measurements.duplicate(true),
		"player_position": _street.get_player_position(),
		"cart": _street.get_cart_state(),
	}
	sim.save_into(world)
	GameState.save_run(world)
	if show_feedback:
		_float_small("SAVED")


# ---------------------------------------------------------------- inspecting

func _on_visit(house: int) -> void:
	if _is_over or not sim.assignments.has(house) or _overlay.visible or house in sim.completed:
		return
	_active = house
	Sfx.play("tap")
	Settings.haptic(15)
	var a: Dictionary = sim.assignments[house]
	_overlay.show()
	if str(a.kind) == "reinspect":
		var record: Dictionary = sim.cases.get(house, {})
		var panel: Panel = ReinspectPanel.new()
		var labels: Array = []
		for v in record.get("violations", []):
			if str(v.id) in record.get("cited", []):
				labels.append(str(v.label))
		panel.setup({"address": _street.lot_address(house), "owner": sim.owner_of(house), "relationship": sim.relationship_text(house),
				"result": str(a.get("result", "unchanged")), "labels": labels, "options": sim.reinspection_options(house)})
		panel.chose.connect(_on_reinspection_choice)
		_overlay.add_child(panel)
	elif str(a.kind) == "lawn" and not _measurements.has(house):
		var game = LAWN_SCRIPT.new()
		game.setup(_grass[house], sim.owner_of(house))
		game.measured.connect(_on_lawn_measured)
		_overlay.add_child(game)
		game.position = ((size - Vector2(620, 880)) / 2.0).max(Vector2(20, 20))
	else:
		_open_case_sheet(house)


func _on_lawn_measured(reading: float, precise: bool) -> void:
	_measurements[_active] = {"reading": reading, "precise": precise}
	_close_overlay()
	_overlay.show()
	_open_case_sheet(_active)


## Evidence as the rules see it: photos, plus a precise lawn measurement for tall grass.
func _evidence_for(house: int) -> Dictionary:
	var evidence: Dictionary = (_street.get_evidence().get(house, {}) as Dictionary).duplicate(true)
	var measured: Dictionary = _measurements.get(house, {})
	# A precise reading over the limit documents the violation; under it, it clears it.
	if bool(measured.get("precise", false)) and float(measured.get("reading", 0.0)) > 6.0:
		var documented: Array = evidence.get("documented", [])
		if not "tall_grass" in documented:
			documented.append("tall_grass")
		evidence.documented = documented
		evidence.quality = maxi(int(evidence.get("quality", 0)), 60)
	return evidence


func _open_case_sheet(house: int) -> void:
	var a: Dictionary = sim.assignments[house]
	var property: Dictionary = sim.property_of(house)
	var evidence := _evidence_for(house)
	var documented: Array = evidence.get("documented", [])
	var quality := int(evidence.get("quality", 0))
	var rows: Array = []
	var notes: Array = []
	for v in a.violations:
		var seen := str(v.id) in documented
		# A strong photo that shows nothing counts as evidence the complaint is wrong.
		var cleared: bool = quality >= 55 and not bool(v.actual) and (evidence.get("photos", []) as Array).size() > 0
		var reading: Dictionary = _measurements.get(house, {})
		if str(v.id) == "tall_grass" and bool(reading.get("precise", false)) and float(reading.get("reading", 99.0)) <= 6.0:
			cleared = true
		rows.append({"id": v.id, "label": v.label, "documented": seen, "cleared": cleared})
		if seen:
			notes.append("%s: %s" % [str(v.label), str(v.borderline_note) if bool(v.borderline) and str(v.borderline_note) != "" else "clearly visible in the photo."])
		elif cleared:
			notes.append("%s: not visible. %s" % [str(v.label), str(v.hint)])
	var measured: Dictionary = _measurements.get(house, {})
	if not measured.is_empty():
		notes.append("Lawn measured at %.1f in (limit 6.0)%s." % [float(measured.reading), " — over the limit" if float(measured.reading) > 6.0 else " — compliant"])
	var history: Array = []
	var past: Array = property.get("history", [])
	for entry in past.slice(maxi(0, past.size() - 3)):
		history.append("Day %d · %s" % [int(entry.get("day", 0)), str(entry.get("state", "")).replace("_", " ")])
	var photos: Array = []
	var shots: Array = (evidence.get("photos", []) as Array).duplicate()
	shots.sort_custom(func(x, y): return int(x.quality) > int(y.quality))
	for shot in shots.slice(0, 3):
		var tex: Texture2D = _street.camera_ev.thumb(str(shot.get("path", "")))
		if tex != null:
			photos.append(tex)
	var traits: Array = property.get("traits", [])
	var blurb: String = str(Residents.TRAIT_BLURBS.get(traits[0], "")) if not traits.is_empty() else ""
	var source := str(a.get("source", "resident"))
	var case_file = CASE_FILE_SCRIPT.new()
	case_file.setup({
		"address": _street.lot_address(house), "owner": sim.owner_of(house), "relationship": sim.relationship_text(house),
		"repeat_count": property.get("repeat_count", 0), "lot_type": _street.lot_kind(house), "blurb": blurb, "history": history,
		"source": str(a.get("complainant", sim.violations.source_label(source))), "text": str(a.get("text", "")),
		"reliability": "Source reliability: %s" % _reliability_word(sim.violations.source_reliability(source)),
		"photos": photos, "quality": quality, "shots": (evidence.get("photos", []) as Array).size(), "observations": notes,
		"violations": rows, "options_for": func(cited: Array) -> Dictionary: return sim.ruling_options(house, cited, evidence),
	})
	case_file.ruled.connect(_on_case_ruled)
	_overlay.add_child(case_file)
	case_file.position = ((size - CASE_FILE_SCRIPT.PANEL_SIZE) / 2.0).max(Vector2(8, 8))


func _reliability_word(value: float) -> String:
	if value >= 0.85:
		return "high"
	if value >= 0.65:
		return "moderate"
	return "low"


func _on_case_ruled(action: String, cited: Array) -> void:
	var house := _active
	var result := sim.rule_case(house, action, cited, _evidence_for(house))
	_apply_result(result)
	_finish_case(house)


func _on_reinspection_choice(choice: String) -> void:
	var house := _active
	var result := sim.resolve_reinspection(house, choice)
	result.correct = true
	_apply_result(result)
	_finish_case(house)


func _apply_result(result: Dictionary) -> void:
	var correct = result.get("correct", null)
	var gained := GameState.add_score(int(result.points), correct)
	GameState.apply_effects(result.effects)
	_close_overlay()
	if _is_over:
		return
	_float("%+d" % gained, Color("7ee081") if gained >= 0 else Color("ff6b5a"))
	Sfx.play("good" if gained >= 0 else "bad")
	Settings.haptic(30 if gained >= 0 else 45)


func _finish_case(house: int) -> void:
	if _is_over:
		return
	_street.mark_done(house)
	_street.set_case_states(sim.case_states())
	_update_task()
	_refresh()
	if sim.completed.size() >= sim.assignments.size():
		_evening()
	else:
		_save_progress(true)


func _on_discover(house: int) -> void:
	if _overlay.visible or _is_over:
		return
	var info := sim.open_discovered(house)
	if info.is_empty():
		return
	_street.add_assignment(house, "card")
	_street.set_discoverable(sim.discoverable.keys())
	for line in info.lines:
		_float_small(str(line))
	_update_task()
	Sfx.play("notify")
	_save_progress()


func _on_photo(_house: int, quality: int, usable: bool, documented: Array) -> void:
	if not usable:
		GameState.add_score(-10)
		Sfx.play("bad")
		return
	Sfx.play("shutter")
	Settings.haptic(25)
	GameState.add_score(10 + 15 * documented.size() + (10 if quality >= 80 else 0))
	_save_progress(true)


# ---------------------------------------------------------------- hearings, meetings, events

func _run_hearing(house: int) -> void:
	if _is_over:
		return
	var info := sim.build_hearing(house)
	info.address = _street.lot_address(house)
	_overlay.show()
	var panel: Panel = HearingPanel.new()
	panel.setup(info)
	panel.decided.connect(func(recommendation: String, present: bool):
		_close_overlay()
		var result := sim.hold_hearing(house, recommendation, present)
		GameState.apply_effects(result.effects)
		GameState.add_score(40)
		_street.set_case_states(sim.case_states())
		var votes_panel: Panel = VotePanel.new()
		votes_panel.setup("HEARING · %s" % _street.lot_address(house), result.lines, result.votes)
		votes_panel.closed.connect(func():
			_close_overlay()
			_next_morning_step())
		_overlay.show()
		_overlay.add_child(votes_panel))
	_overlay.add_child(panel)


func _run_meeting(votes: Array) -> void:
	var retain := sim.board.tally(votes)
	var lines: Array = ["%d of %d members vote to retain you." % [retain, votes.size()]]
	var ousted := retain * 2 <= votes.size()
	if ousted:
		lines.append("You have been voted out.")
	else:
		var bonus := GameState.add_score(150)
		sim.board.shift(sim.politics, 4)
		lines.append("Re-elected! +%d points." % bonus)
	_overlay.show()
	var panel: Panel = VotePanel.new()
	panel.setup("ANNUAL MEETING", lines, votes, "CONTINUE")
	panel.closed.connect(func():
		_close_overlay()
		if ousted:
			GameState.force_end("Voted out at the annual meeting. Recount denied.")
		else:
			_next_morning_step())
	_overlay.add_child(panel)


func _show_report(title: String, lines: Array, button_text: String) -> void:
	_overlay.show()
	var modal := UiKit.modal(size, Vector2(620, 860), title)
	_overlay.add_child(modal.root)
	for line in lines:
		modal.body.add_child(UiKit.label("• %s" % str(line), 22, UiKit.INK))
	var btn := UiKit.button(button_text, 32, 84)
	btn.pressed.connect(func():
		_close_overlay()
		_next_morning_step())
	modal.footer.add_child(btn)


## One agenda item (architectural request, assessment, vendor bid, project, politics, drama).
func _maybe_event() -> void:
	if _is_over or GameState.day <= 1 or _events.is_empty() or randf() > 0.5 or _overlay.visible:
		return
	if GameState.day % HoaSim.ANNUAL_MEETING_EVERY == 0:
		return
	var event: Dictionary = (_events[randi() % _events.size()] as Dictionary).duplicate(true)
	var house: int = randi() % _street.house_count()
	event.who = str(event.who).replace("{owner}", sim.owner_of(house)).replace("{address}", _street.lot_address(house))
	_overlay.show()
	_card = CARD_SCENE.instantiate()
	_card.size = CARD_SIZE
	_overlay.add_child(_card)
	_card.setup(event, (size - CARD_SIZE) / 2.0)
	_card.swiped.connect(_on_event_swiped)


func _on_event_swiped(side: String) -> void:
	var data: Dictionary = _card.data
	_card.queue_free()
	_card = null
	var choice: Dictionary = data.get(side, {})
	var effects: Dictionary = choice.get("effects", {})
	sim.apply_political(effects)
	if choice.has("project"):
		sim.projects.append((choice.project as Dictionary).duplicate(true))
	GameState.add_score(25)
	GameState.apply_effects(effects)
	_close_overlay()
	_save_progress(true)
	_refresh()


# ---------------------------------------------------------------- evening

func _evening() -> void:
	var finished := GameState.day
	var bonus := GameState.end_day()
	_phase = "evening"
	_evening_bonus = bonus.duplicate(true)
	if finished == 1:
		Settings.tutorial_done = true
		Settings.save()
	_save_progress()
	_show_evening(finished, bonus)


func _show_evening(finished: int, bonus: Dictionary) -> void:
	_overlay.show()
	var modal := UiKit.modal(size, Vector2(600, 700), "DAY %d COMPLETE" % finished)
	_overlay.add_child(modal.root)
	var body: VBoxContainer = modal.body
	body.add_child(UiKit.label("Day bonus  +%d" % int(bonus.day_bonus), 30))
	body.add_child(UiKit.label("Balanced stats  +%d" % int(bonus.balance_bonus), 30))
	body.add_child(UiKit.label("Streak  x%d" % GameState.streak, 30))
	body.add_child(UiKit.label("Open cases  %d" % sim.open_case_count(), 30))
	body.add_child(UiKit.label("SCORE  %s" % _commas(GameState.score), 42, UiKit.GOOD, true))
	var counsel: String = sim.board.counsel_warning(sim.politics)
	if counsel != "":
		body.add_child(UiKit.label("LEGAL COUNSEL: \"%s\"" % counsel, 19, UiKit.BAD))
	var btn := UiKit.button("NEXT DAY", 34, 90)
	btn.pressed.connect(func():
		_close_overlay()
		GameState.next_day()
		_new_day())
	modal.footer.add_child(btn)


# ---------------------------------------------------------------- HUD

func _close_overlay() -> void:
	for child in _overlay.get_children():
		child.queue_free()
	_card = null
	_overlay.hide()


func _on_game_over(reason: String) -> void:
	_is_over = true
	_close_overlay()
	_over_label.text = "%s\n\nSurvived %d days.\nScore %s  ·  Best %s" % [reason, GameState.day - 1, _commas(GameState.score), _commas(GameState.best)]
	_over_panel.show()
	Sfx.play("bad")


func _commas(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if value < 0 else "") + out


func _refresh() -> void:
	if not is_instance_valid(_day_label):
		return
	_day_label.text = "DAY %d" % GameState.day
	_score_label.text = "SCORE %s" % _commas(GameState.score) + ("  x%d" % GameState.streak if GameState.streak > 1 else "")
	_best_label.text = "BEST %s" % _commas(GameState.best)
	for key in _bars:
		var bar: ProgressBar = _bars[key]
		var value: int = GameState.stats[key]
		create_tween().tween_property(bar, "value", value, 0.2)
		bar.modulate = Color("e0533d") if value <= 20 or value >= 80 else Color.WHITE
		if key == "budget":
			(_stat_labels[key] as Label).text = "%s  $%s" % [STAT_LABELS[key], _commas(value * DOLLARS_PER_POINT)]
		else:
			(_stat_labels[key] as Label).text = "%s  %d" % [STAT_LABELS[key], value]
	if sim.politics.is_empty():
		_politics_label.text = ""
	else:
		_politics_label.text = "BOARD %d%% · LEGAL RISK %d%%" % [sim.board_support(), sim.legal_risk()]


func _float(text: String, color: Color) -> void:
	var label := _make_label(text, 72, color, true)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 10)
	label.size = Vector2(size.x, 100)
	label.position = Vector2(0, size.y * 0.3)
	label.z_index = 20
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 120.0, 1.1)
	tween.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


func _float_small(text: String) -> void:
	if _overlay.visible:
		return
	var label := _make_label(text, 26, Color.WHITE, true)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(size.x - 80, 60)
	label.position = Vector2(40, size.y * 0.42)
	label.z_index = 20
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.4).set_delay(0.8)
	tween.tween_callback(label.queue_free)


func _process(_delta: float) -> void:
	if not is_instance_valid(_street) or _street.house_count() == 0:
		return
	_update_hint()


## First-day coaching: one short line at a time, gone once the loop is understood.
func _update_hint() -> void:
	if Settings.tutorial_done or GameState.day != 1 or _phase != "street" or _overlay.visible or is_instance_valid(_title):
		_street.set_hint("")
		return
	var hint := ""
	var target: int = _street.objective
	if not _street.used:
		hint = "Drag anywhere to walk"
	elif target >= 0 and _street.near != target:
		hint = "Walk to the gold pin: %s" % _street.lot_address(target)
	elif target >= 0 and not _street.get_evidence().has(target) and not _street.camera_ev.active:
		hint = "Tap the camera to photograph the property"
	elif target >= 0 and _street.camera_ev.active:
		hint = "Center the house and take the photo"
	elif target >= 0:
		hint = "Tap INSPECT PROPERTY to open the case"
	_street.set_hint(hint)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("2f4858")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	_margin = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var info := HBoxContainer.new()
	vbox.add_child(info)
	_day_label = _make_label("DAY 1", 28, Color.WHITE)
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_day_label)
	_score_label = _make_label("SCORE 0", 28, Color("ffd36e"), true)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	info.add_child(_score_label)
	_best_label = _make_label("BEST 0", 28, Color.WHITE)
	_best_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(_best_label)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 14)
	vbox.add_child(stats_row)
	for key in GameState.STAT_KEYS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_row.add_child(col)
		var label := _make_label(STAT_LABELS[key], 17, Color.WHITE, true)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		col.add_child(label)
		_stat_labels[key] = label
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 16)
		bar.value = GameState.START_VALUE
		col.add_child(bar)
		_bars[key] = bar
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 10)
	vbox.add_child(meta)
	_menu_button = Button.new()
	_menu_button.text = "MENU"
	_menu_button.custom_minimum_size = Vector2(96, 40)
	_menu_button.add_theme_font_size_override("font_size", 18)
	_menu_button.pressed.connect(func():
		Sfx.play("tap")
		_open_menu())
	meta.add_child(_menu_button)
	_politics_label = _make_label("", 17, Color("ffd36e"), true)
	_politics_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_politics_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_politics_label)
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	_version_label = _make_label("v%s" % version, 16, Color("b9d8e8"), false)
	_version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(_version_label)
	_street = Control.new()
	_street.set_script(STREET_SCRIPT)
	_street.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_street.visit.connect(_on_visit)
	_street.photo_taken.connect(_on_photo)
	_street.discover.connect(_on_discover)
	_street.evidence_changed.connect(func(): _save_progress())
	vbox.add_child(_street)
	_task_label = _make_label("", 22, Color.WHITE, true)
	vbox.add_child(_task_label)
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)
	_build_game_over()
	_refresh()


func _build_game_over() -> void:
	_over_panel = ColorRect.new()
	(_over_panel as ColorRect).color = Color(0, 0, 0, 0.8)
	_over_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_panel.z_index = 45
	_over_panel.hide()
	add_child(_over_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(80, 420)
	box.add_theme_constant_override("separation", 40)
	_over_panel.add_child(box)
	_over_label = _make_label("", 36, Color.WHITE, true)
	box.add_child(_over_label)
	var button := Button.new()
	button.text = "New Term"
	button.custom_minimum_size = Vector2(0, 90)
	button.add_theme_font_size_override("font_size", 36)
	button.pressed.connect(func():
		_over_panel.hide()
		_show_title())
	box.add_child(button)


## Push the HUD clear of the notch / Dynamic Island and the home indicator.
func _apply_safe_area() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var top := 0.0
	var bottom := 0.0
	if win.x > 0.0 and safe.size != Vector2i.ZERO:
		var k := get_viewport_rect().size.x / win.x
		top = maxf(float(safe.position.y) * k, 0.0)
		bottom = maxf((win.y - float(safe.end.y)) * k, 0.0)
	if OS.get_name() == "iOS":
		if top <= 0.0:
			top = 36.0
		if bottom <= 0.0:
			bottom = 18.0
	_margin.add_theme_constant_override("margin_top", 14 + int(top))
	_margin.add_theme_constant_override("margin_bottom", 14 + int(bottom))


func _make_label(text: String, font_size: int, color: Color, centered := false) -> Label:
	return UiKit.label(text, font_size, color, centered)
