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
const Career := preload("res://scripts/sim/career.gd")
const Weather := preload("res://scripts/sim/weather.gd")
const PropertyCard := preload("res://scripts/ui/property_card.gd")
const PhotoPreview := preload("res://scripts/ui/photo_preview.gd")
const EncounterPanel := preload("res://scripts/ui/encounter_panel.gd")

const CARD_SIZE := Vector2(600, 640)
const UPDATE_MANIFEST_URL := "https://raw.githubusercontent.com/ssnanda/hoagame/main/altstore.json"
const ALTSTORE_BUNDLE_ID := "com.ssnanda.hoagame"
const WORLD_VERSION := 9          ## 8: encounters, ARC memory, vendors, community mods. 9: wider sidewalks changed lot ids/positions (older runs keep the term but drop lot-specific state)
const STAT_LABELS := {"budget": "TREASURY", "happiness": "COMMUNITY", "power": "AUTHORITY"}
const DOLLARS_PER_POINT := 690

var sim := HoaSim.new()
var career := Career.new()

var _bars: Dictionary = {}
var _stat_labels: Dictionary = {}
var _day_label: Label
var _score_label: Label
var _best_label: Label
var _task_label: Label
var _politics_label: Label
var _version_label: Label
var _version_chip: Label            ## always-visible version at the bottom of the screen
var _street: Control
var _margin: MarginContainer
var _overlay: ColorRect
var _card: Panel
var _over_panel: Control
var _over_label: Label
var _title: Control
var _modal: Control
var _menu_button: Button
var _stats_button: Button
var _details: VBoxContainer
var _is_over := false
var _encounter_active := false
var _info_row: HBoxContainer
var _small_floats := 0
var _hearing_active := false
var _first_case := -1             ## onboarding property chosen for the first game (-1 otherwise)
var _card_ui: Control            ## compact property card (PROPERTY_CONTEXT / COMPLAINT_VIEW)
var _preview_ui: Control         ## photo preview (PHOTO_PREVIEW)
var _pending_shot: Dictionary = {}
var ui_state := "WORLD"          ## derived every frame from what is actually on screen (see _compute_ui_state)
var _built_community := "oak_meadow"     ## community whose layout this scene was built with
var _debug_clock := 0.0
var _photo_scene_done: Dictionary = {}   ## houses that already had their one "photo" scene today
var _visited: Dictionary = {}     ## houses already approached today (one "visit" scene per house)
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
var update_status := "Checking for updates..."   ## shown next to the version so you can tell if you are current
var _altstore_launch_pending := false


func _ready() -> void:
	career.load_all()
	_load_events()
	_build_ui()
	GameState.stats_changed.connect(_refresh)
	GameState.game_over.connect(_on_game_over)
	await get_tree().process_frame
	sim.setup(_street.house_count())
	_show_title()
	_check_for_updates()
	# A community change reloads the scene so the new layout is built; carry on where the player was heading.
	var pending := Settings.pending_action
	Settings.pending_action = ""
	if pending == "new":
		_begin(false)
	elif pending == "continue":
		_begin(true)


# ---------------------------------------------------------------- title and menus

func _show_title() -> void:
	_close_property_card()
	_close_preview()
	_close_overlay()
	if is_instance_valid(_title):
		_title.queue_free()
	_street.set_hint("")
	_title = MenuPanels.title_screen(size, GameState.has_saved_run, {
		"continue": func(): _begin(true),
		"new_term": func(): _begin(false),
		"communities": func(): _open_communities(),
			"howto": func(): _show_modal(MenuPanels.how_to_play(size, _close_modal)),
		"settings": func(): _show_modal(MenuPanels.settings(size, _close_modal, _reset_game)),
		"about": func(): _show_modal(MenuPanels.about(size, _close_modal, update_status)),
	})
	_title.z_index = 40
	add_child(_title)


func _begin(resume: bool) -> void:
	# The street layout belongs to a community; rebuild it when the wanted one differs.
	var wanted := _built_community
	if resume and GameState.has_saved_run:
		wanted = str(GameState.saved_world().get("community_id", "oak_meadow"))
	elif not resume:
		wanted = career.selected
	if wanted != _built_community and Settings.pending_action == "":
		career.selected = wanted
		career.save()
		Settings.pending_action = "continue" if resume else "new"
		get_tree().reload_current_scene()
		return
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
	var modal := UiKit.modal(size, Vector2(560, 820), "MENU")
	for item in [["RESUME", func(): _close_modal()], ["CASE BOARD", func(): _open_portal("cases")], ["WOZIG PORTAL", func(): _open_portal()],
			["TRAINING", func(): _show_modal(MenuPanels.how_to_play(size, _close_modal))],
			["SETTINGS", func(): _show_modal(MenuPanels.settings(size, _close_modal, _reset_game))],
			["TITLE SCREEN", func():
				_close_modal()
				_save_progress()
				_show_title()]]:
		var btn := UiKit.button(str(item[0]), 26, 66)
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
	modal.footer.add_child(UiKit.label("%s\n%s" % [Settings.version_text(), update_status], 16, UiKit.MUTED, true))
	_show_modal(modal.root)


func _open_communities() -> void:
	_show_modal(MenuPanels.communities(size, career, func(id: String):
		career.selected = id
		career.save()
		_open_communities(), _close_modal))


## Always-visible achievement toast, independent of overlays.
func _toast(text: String) -> void:
	var label := _make_label(text, 24, Color("ffd36e"), true)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	label.size = Vector2(size.x - 60, 70)
	label.position = Vector2(30, size.y * 0.16)
	label.z_index = 90
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(2.4)
	tween.tween_callback(label.queue_free)


## Notification ladder: small (quiet line), medium (toast), important (banner + sound),
## major (large banner, stronger sound and haptic). No modal boxes for any of them.
func _notify(level: String, text: String) -> void:
	match level:
		"small":
			_float_small(text)
		"medium":
			_toast(text)
		"important":
			Sfx.play("notify")
			_toast(text.to_upper())
		"major":
			Sfx.play("bad")
			Settings.haptic(50)
			_float(text.to_upper(), Color("ffd36e"))


func _award(id: String) -> void:
	if career.award(id):
		Sfx.play("good")
		_toast("ACHIEVEMENT · %s" % career.achievement_name(id).to_upper())


func _open_portal(tab := "overview") -> void:
	var portal: Panel = PortalPanel.new()
	portal.start_tab = tab
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
		update_status = "Couldn't check for updates (offline?)"
		_refresh_version_chip()
		return
	var source = JSON.parse_string(body.get_string_from_utf8())
	if not source is Dictionary:
		update_status = "Couldn't read the update list"
		_refresh_version_chip()
		return
	for app in source.get("apps", []):
		if app is Dictionary and str(app.get("bundleIdentifier", "")) == ALTSTORE_BUNDLE_ID:
			var remote_version := str(app.get("version", ""))
			var remote_build := int(str(app.get("buildVersion", "0")))
			var remote_label := "%s (build %d)" % [remote_version, remote_build]
			if _is_newer_build(remote_version, remote_build, Settings.version_name(), Settings.build_number()):
				_available_version = remote_version
				update_status = "Update available: %s" % remote_label
				_show_update_prompt(str(app.get("versionDescription", "")))
			else:
				update_status = "Up to date (latest is %s)" % remote_label
			_refresh_version_chip()
			return
	update_status = "App not found in the update list"
	_refresh_version_chip()


## Newer by version number, or the same version with a higher build number.
func _is_newer_build(remote: String, remote_build: int, local: String, local_build: int) -> bool:
	if _is_newer_version(remote, local):
		return true
	return not _is_newer_version(local, remote) and remote_build > local_build


func _refresh_version_chip() -> void:
	if is_instance_valid(_version_chip):
		_version_chip.text = "%s" % Settings.version_text()
	if is_instance_valid(_version_label):
		_version_label.text = "%s · %s" % [sim.community_name, Settings.version_text()]


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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Calls, control center and swipe-away all lose focus first: save on the way out.
		if is_instance_valid(_street) and not _is_over and not sim.assignments.is_empty():
			_save_progress()      # safe mid-cinematic: the ruling is already applied and the scene is flagged as seen
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_altstore_launch_pending = false
		if is_instance_valid(_street) and not _is_over and not sim.assignments.is_empty():
			_save_progress()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and close_topmost():
		get_viewport().set_input_as_handled()
		return
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
	sim.new_term(career.current())
	_measurements = {}
	if Settings.tutorial_done:
		_new_day()
	else:
		_show_intro()


## One-time humorous setup, then straight into day one.
func _show_intro() -> void:
	_overlay.show()
	var modal := UiKit.modal(size, Vector2(600, 620), "")
	_overlay.add_child(modal.root)
	modal.body.add_child(UiKit.label(str(MenuPanels.branding().get("intro", "You are now HOA President.")), 30, UiKit.INK, true))
	var go := UiKit.button("TAKE THE GAVEL", 30, 84)
	go.pressed.connect(func():
		Sfx.play("good")
		_close_overlay()
		_new_day())
	modal.footer.add_child(go)


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
	_close_property_card()
	_close_preview()
	_street.camera_ev.active = false
	var info := sim.start_day(GameState.day, GameState.season(), GameState.weekday())
	if _is_over:
		return
	_first_case = _force_first_case() if (GameState.day == 1 and not Settings.tutorial_done) else -1
	if GameState.day == 2 and not bool(sim.politics.get("scripted_day2", false)):
		sim.politics.scripted_day2 = true
		_force_borderline_case()
	var season := GameState.season()
	var growth: float = [1.0, 1.15, 0.9, 0.7][season] * sim.landscaper_growth()
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
	_visited.clear()
	_photo_scene_done.clear()
	_phase = "street"
	_evening_bonus = {}
	_street.set_day(pins, _grass, 0, null, {}, visuals)
	if _first_case >= 0:
		_street.clear_lot_parking(_first_case)
		_street.set_objective(_first_case)
	_street.set_discoverable(sim.discoverable.keys())
	_street.set_case_states(sim.case_states())
	_update_task()
	_refresh()
	_save_progress()
	_morning_queue.clear()
	var brief := _daily_brief(info)
	if GameState.day > 1 or not brief.is_empty():
		Sfx.play("notify")
		_morning_queue.append(func(): _show_report("%s %s" % [GameState.weekday_name(), GameState.date_text()], brief + (info.report as Array), "START THE DAY"))
	for house in info.hearings:
		_morning_queue.append(_run_hearing.bind(int(house)))
	if not (info.meeting as Array).is_empty():
		_morning_queue.append(_run_meeting.bind(info.meeting, str(info.get("meeting_title", "ANNUAL MEETING"))))
	_morning_queue.append(_maybe_board_call)
	_morning_queue.append(_maybe_event)
	_next_morning_step()


## Onboarding: the very first complaint is deliberately easy. A plain tall-grass report on a
## standard lot near the starting point, no parked car, trees kept off the access route
## (Neighborhood.validate guarantees that), and a certain, unambiguous violation. It is also
## the ruling that triggers the scripted showcase encounter.
func _force_first_case() -> int:
	var hood = _street.hood
	var spawn: Vector2 = _street.spawn_point()
	var best := -1
	var best_d := INF
	for lot in hood.lots:
		if lot.kind != "standard" or lot.side == 0:
			continue
		var d: float = spawn.distance_to(lot.inspect_anchor())
		if d < best_d:
			best_d = d
			best = lot.id
	if best < 0:
		return -1
	var def: Dictionary = sim.violations.get_def("tall_grass")
	var item: Dictionary = sim.violations.make_allegation(def, 1.0, sim.rng, 1)
	item.borderline = false
	sim.assignments[best] = {"kind": "lawn", "source": "management", "complainant": "Wozig management inspection",
			"violations": [item], "false_complaint": false, "status": "assigned",
			"text": "The front lawn is well over the 6 inch grass limit."}
	_force_second_case(best)
	return best


## Case 2 of the first game: a plainly FALSE complaint (curb bins that are not there), so the player
## learns that a complaint is an allegation. Nearest standard lot to the start after the first case.
func _force_second_case(not_lot: int) -> void:
	var lot_id := _nearest_standard_lot(not_lot)
	if lot_id < 0:
		return
	var def: Dictionary = sim.violations.get_def("curb_bins")
	var item: Dictionary = sim.violations.make_allegation(def, 0.0, sim.rng, 0)
	item.borderline = false
	sim.assignments[lot_id] = {"kind": "card", "source": "resident", "complainant": "Neighbor", "violations": [item],
			"false_complaint": true, "status": "assigned", "text": "Trash bins have been left at the curb all week."}


## Day 2 of the first game: a borderline tall-grass report (just over the limit) to introduce judgment.
func _force_borderline_case() -> void:
	var lot_id := _nearest_standard_lot(-1)
	if lot_id < 0 or sim.assignments.has(lot_id) and str(sim.assignments[lot_id].kind) == "reinspect":
		return
	var def: Dictionary = sim.violations.get_def("tall_grass")
	var item: Dictionary = sim.violations.make_allegation(def, 1.0, sim.rng, 1)
	item.borderline = true
	sim.assignments[lot_id] = {"kind": "lawn", "source": "resident", "complainant": "Neighbor", "violations": [item],
			"false_complaint": false, "status": "assigned", "text": "The grass looks long. It might be right at the limit."}


func _nearest_standard_lot(skip: int) -> int:
	var spawn: Vector2 = _street.spawn_point()
	var best := -1
	var best_d := INF
	for lot in _street.hood.lots:
		if lot.kind != "standard" or lot.side == 0 or lot.id == skip or sim.cases.has(lot.id):
			continue
		var d: float = spawn.distance_to(lot.inspect_anchor())
		if d < best_d:
			best_d = d
			best = lot.id
	return best


## Short morning summary: what is waiting, the forecast and the next big date.
func _daily_brief(info: Dictionary) -> Array:
	var lines: Array = []
	var fresh := 0
	var again := 0
	for house in sim.assignments:
		if str(sim.assignments[house].kind) == "reinspect":
			again += 1
		else:
			fresh += 1
	lines.append("%d new complaint%s" % [fresh, "" if fresh == 1 else "s"])
	if again > 0:
		lines.append("%d follow-up inspection%s due" % [again, "" if again == 1 else "s"])
	if not (info.hearings as Array).is_empty():
		lines.append("%d hearing%s tonight" % [info.hearings.size(), "" if info.hearings.size() == 1 else "s"])
	lines.append(Weather.brief_line(Weather.for_day(GameState.day, GameState.season()), GameState.day))
	var to_meeting := GameState.days_to_meeting(HoaSim.ANNUAL_MEETING_EVERY)
	if to_meeting == 0:
		lines.append("The annual meeting is today.")
	elif to_meeting <= 3:
		lines.append("Annual meeting in %d day%s." % [to_meeting, "" if to_meeting == 1 else "s"])
	return lines


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
	if int(world.get("world_version", 1)) < 9:
		# Neighborhood rebuilt (v6, and again in v9 with wider sidewalks): keep the term, drop lot-specific state.
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
	if int(world.get("objective", -1)) >= 0:
		_street.set_objective(int(world.get("objective", -1)))
	_update_task()
	_refresh()
	_float("WELCOME BACK", Color("ffd36e"))
	if _phase == "evening":
		_show_evening(GameState.day, _evening_bonus)


## One consistent status line, derived from the street's own pins so it can never
## disagree with the "Next:" chip: inspections, reinspections, or "all done".
func _update_task() -> void:
	var fresh := 0
	var again := 0
	for house in _street.pins:
		match str(_street.pins[house]):
			"lawn", "card":
				fresh += 1
			"reinspect":
				again += 1
	if fresh + again == 0:
		_task_label.text = "All of today's inspections are done"
		return
	var parts: Array = []
	if fresh > 0:
		parts.append("%d inspection%s" % [fresh, "" if fresh == 1 else "s"])
	if again > 0:
		parts.append("%d reinspection%s" % [again, "" if again == 1 else "s"])
	_task_label.text = " · ".join(parts) + " to go"


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
		"objective": _street.objective,
		"community_id": _built_community,
	}
	sim.save_into(world)
	GameState.save_run(world)
	if show_feedback:
		_float_small("SAVED")


# ---------------------------------------------------------------- inspecting

func _on_visit(house: int) -> void:
	if _is_over or not sim.assignments.has(house) or _overlay.visible or house in sim.completed or _encounter_active \
			or is_instance_valid(_card_ui) or is_instance_valid(_preview_ui):
		return
	# The resident may come out to meet you before anything opens.
	if not _visited.has(house):
		_visited[house] = true
		await _play_encounter(house, "visit")
		if _is_over or _overlay.visible:
			return
	_active = house
	Sfx.play("tap")
	Settings.haptic(15)
	_open_property_card(house)


# ---------------------------------------------------------------- property card flow
# World -> compact card (INSPECT) -> camera -> photo preview -> card with evidence ->
# case sheet. Every step has a Back that returns to the step before it.

func _open_property_card(house: int) -> void:
	_close_property_card()
	var a: Dictionary = sim.assignments[house]
	var evidence := _evidence_for(house)
	var photos := (evidence.get("photos", []) as Array).size()
	var source := str(a.get("source", "resident"))
	_card_ui = PropertyCard.new()
	_card_ui.size = size
	(_card_ui as PropertyCard).setup({
		"address": _street.lot_address(house), "kind": "reinspect" if str(a.kind) == "reinspect" else "complaint",
		"text": str(a.get("text", "A complaint was filed.")), "photos": photos, "quality": int(evidence.get("quality", 0)),
		"source": str(a.get("complainant", sim.violations.source_label(source))),
		"reliability": "Source reliability: %s" % _reliability_word(sim.violations.source_reliability(source)),
		"owner": sim.owner_of(house), "relationship": sim.relationship_text(house),
		"can_measure": str(a.kind) == "lawn" and not _measurements.has(house),
		"bottom_margin": float(_margin.get_theme_constant("margin_bottom")),
	})
	_card_ui.action.connect(_on_card_action)
	add_child(_card_ui)
	_street.ui_locked = true


func _close_property_card() -> void:
	if is_instance_valid(_card_ui):
		_card_ui.queue_free()
	_card_ui = null


func _on_card_action(name: String) -> void:
	var house := _active
	match name:
		"back":
			_close_property_card()
			_street.ui_locked = false
		"photo":
			_close_property_card()
			_street.ui_locked = false
			_street.open_camera(true)
		"inspect":
			_close_property_card()
			_show_reinspect_panel(house)
		"case":
			_close_property_card()
			_overlay.show()
			_open_case_sheet(house)
		"measure":
			_close_property_card()
			_overlay.show()
			var game = LAWN_SCRIPT.new()
			game.setup(_grass[house], sim.owner_of(house))
			game.measured.connect(_on_lawn_measured)
			game.closed.connect(_back_to_card)
			_overlay.add_child(game)
			game.position = ((size - Vector2(620, 880)) / 2.0).max(Vector2(20, 20))


## Leaves whatever full-screen panel is open and returns to the property card.
func _back_to_card() -> void:
	_close_overlay()
	if _active >= 0 and sim.assignments.has(_active) and not _active in sim.completed:
		_open_property_card(_active)


func _show_reinspect_panel(house: int) -> void:
	var a: Dictionary = sim.assignments[house]
	_overlay.show()
	var record: Dictionary = sim.cases.get(house, {})
	var panel: Panel = ReinspectPanel.new()
	var labels: Array = []
	for v in record.get("violations", []):
		if str(v.id) in record.get("cited", []):
			labels.append(str(v.label))
	panel.setup({"address": _street.lot_address(house), "owner": sim.owner_of(house), "relationship": sim.relationship_text(house),
			"result": str(a.get("result", "unchanged")), "labels": labels, "options": sim.reinspection_options(house)})
	panel.chose.connect(_on_reinspection_choice)
	panel.closed.connect(_back_to_card)
	_overlay.add_child(panel)


func _on_lawn_measured(reading: float, precise: bool) -> void:
	_measurements[_active] = {"reading": reading, "precise": precise}
	_close_overlay()
	_open_property_card(_active)


# ---------------------------------------------------------------- camera flow

func _on_camera_exit(reason: String) -> void:
	# Left the viewfinder without a photo: return to the card we came from.
	if reason == "cancel" and _street.camera_from_card and _active >= 0 and sim.assignments.has(_active):
		_open_property_card(_active)


func _on_photo_captured(pending: Dictionary) -> void:
	_pending_shot = pending
	_close_preview()
	var house: int = pending.house
	_preview_ui = PhotoPreview.new()
	_preview_ui.size = size
	(_preview_ui as PhotoPreview).setup(pending, _street.lot_address(house), _street.recorded_labels(house, pending.documented))
	_preview_ui.choice.connect(_on_preview_choice)
	add_child(_preview_ui)
	_street.ui_locked = true
	Sfx.play("shutter")
	Settings.haptic(25)


func _close_preview() -> void:
	if is_instance_valid(_preview_ui):
		_preview_ui.queue_free()
	_preview_ui = null


func _on_preview_choice(name: String) -> void:
	var shot := _pending_shot
	_pending_shot = {}
	_close_preview()
	match name:
		"use":
			_street.commit_photo(shot)
			Sfx.play("good")
			# Sometimes the resident notices the camera and comes out before you decide anything.
			if not _photo_scene_done.has(_active):
				_photo_scene_done[_active] = true
				await _play_encounter(_active, "photo")
			if not _is_over and sim.assignments.has(_active) and not _active in sim.completed and not _overlay.visible:
				_open_property_card(_active)
		"another":
			_street.commit_photo(shot)
			_street.ui_locked = false
			_street.open_camera(true)
		"retake":
			_street.ui_locked = false
			_street.open_camera(true)
		_:
			_open_property_card(_active)


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
		rows.append({"id": v.id, "label": v.label, "documented": seen, "cleared": cleared,
				"rule": str(sim.violations.get_def(str(v.id)).get("description", ""))})
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
		"next": _next_step_text(house, a),
		"photos": photos, "quality": quality, "shots": (evidence.get("photos", []) as Array).size(), "observations": notes,
		"violations": rows, "options_for": func(cited: Array) -> Dictionary: return sim.ruling_options(house, cited, evidence),
	})
	case_file.ruled.connect(_on_case_ruled)
	case_file.closed.connect(_back_to_card)
	_overlay.add_child(case_file)
	case_file.position = ((size - CASE_FILE_SCRIPT.PANEL_SIZE) / 2.0).max(Vector2(8, 8))


## One line for the case sheet: what the player should do next with this property.
func _next_step_text(house: int, a: Dictionary) -> String:
	var record: Dictionary = sim.cases.get(house, {})
	if str(a.get("source", "")) == "arc":
		return "Compare the work with what was approved."
	if str(record.get("state", "")) in HoaSim.OPEN_STATES and int(record.get("cure_due", 0)) > GameState.day:
		return "A notice is already open; cure deadline day %d." % int(record.cure_due)
	if (_street.get_evidence().get(house, {}) as Dictionary).is_empty():
		return "Photograph the property, then decide."
	return "Tick what the evidence supports, then decide."


func _reliability_word(value: float) -> String:
	if value >= 0.85:
		return "high"
	if value >= 0.65:
		return "moderate"
	return "low"


func _on_case_ruled(action: String, cited: Array) -> void:
	var house := _active
	var result := sim.rule_case(house, action, cited, _evidence_for(house))
	_apply_result(result, "%s · %s" % ["Fine" if action == "fine" else ("Wrongful citation" if not bool(result.correct) else "Enforcement"), _street.lot_address(house)])
	if action == "fine" and bool(result.correct):
		career.bump("fines")
		_award("first_fine")
		if "tall_grass" in cited:
			_award("not_on_my_lawn")
	await _play_encounter(house, action)
	_notify("important" if action in ["hearing", "fine"] else "medium",
			{"dismiss": "Complaint dismissed", "warning": "Warning issued", "hearing": "Hearing scheduled", "fine": "Fine issued"}.get(action, "Ruling recorded"))
	_finish_case(house)


func _on_reinspection_choice(choice: String) -> void:
	var house := _active
	var had_warning := str(sim.cases.get(house, {}).get("action", "")) == "warning"
	var result := sim.resolve_reinspection(house, choice)
	result.correct = true
	if choice == "close" and had_warning:
		_award("due_process")
	_apply_result(result, "Reinspection · %s" % _street.lot_address(house))
	await _play_encounter(house, "reinspect")
	_finish_case(house)


func _apply_result(result: Dictionary, label := "Case ruling") -> void:
	var correct = result.get("correct", null)
	var gained := GameState.add_score(int(result.points), correct)
	sim.apply_effects(label, result.effects)
	_close_overlay()
	if _is_over:
		return
	_float("%+d" % gained, Color("7ee081") if gained >= 0 else Color("ff6b5a"))
	Sfx.play("good" if gained >= 0 else "bad")
	Settings.haptic(30 if gained >= 0 else 45)


## Close-up encounter after a ruling: camera pushes toward the door, the resident comes
## out, the player answers, and the outcome is applied exactly once.
func _play_encounter(house: int, trigger: String) -> void:
	if _is_over:
		return
	var enc := sim.pick_encounter(house, trigger, GameState.season())
	if enc.is_empty():
		return
	if str(enc.id) == "slapstick_blanket":
		_award("slapstick")
	if DisplayServer.get_name() == "headless":
		# Test runs have no one to answer: take the first reply so bots never stall.
		sim.apply_encounter_outcome(house, enc, (enc.choices as Array)[0], _street.lot_address(house))
		return
	_encounter_active = true
	Sfx.set_mood("absurd" if str(enc.get("tone", "")) in ["slapstick", "comic"] else ("tense" if str(enc.get("tone", "")) in ["angry", "tense"] else "calm"))
	Sfx.play("door")
	_street.begin_cinematic(house)
	# HUD fades out while the camera pushes toward the front door.
	var fade_out := create_tween().set_parallel(true)
	fade_out.tween_property(_street.hud_view, "modulate:a", 0.0, 0.35)
	for node: Control in [_info_row, _details, _task_label]:
		fade_out.tween_property(node, "modulate:a", 0.0, 0.35)
	await get_tree().create_timer(0.7 if not Settings.reduce_motion else 0.2).timeout
	if _is_over:
		_street.end_cinematic()
		_encounter_active = false
		_street.hud_view.modulate.a = 1.0
		for node: Control in [_info_row, _details, _task_label]:
			node.modulate.a = 1.0
		return
	var styles: Array = _street.world_view.styles()
	var style: Dictionary = styles[house] if house < styles.size() else {}
	var panel := EncounterPanel.new()
	panel.size = size
	panel.setup(enc, sim.owner_of(house), _street.lot_address(house), house * 7 + 3,
			style.get("wall", Color("d9c7a3")), style.get("roof", Color("7a4b3a")), {"favored": sim.favored_name(house)})
	panel.modulate.a = 0.0
	add_child(panel)
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.35)
	var choice: Dictionary = await panel.finished
	var fade := create_tween()
	fade.tween_property(panel, "modulate:a", 0.0, 0.3)
	await fade.finished
	panel.queue_free()
	var applied := sim.apply_encounter_outcome(house, enc, choice, _street.lot_address(house))
	if float(applied.slow) > 0.0:
		_street.apply_slow(float(applied.slow))
		_float_small("SLOWED DOWN FOR A WHILE")
	if int(applied.score) != 0:
		GameState.add_score(int(applied.score))
	if str(enc.get("footer", "")) != "":
		_float_small(str(enc.footer).capitalize())
	_street.end_cinematic()
	_encounter_active = false
	Sfx.set_mood("calm")
	var fade_in := create_tween().set_parallel(true)
	fade_in.tween_property(_street.hud_view, "modulate:a", 1.0, 0.4)
	for node: Control in [_info_row, _details, _task_label]:
		fade_in.tween_property(node, "modulate:a", 1.0, 0.4)
	_refresh()


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
		Sfx.play("bad")      # no score penalty: a bad frame is just a retry
		return
	Sfx.play("shutter")
	Settings.haptic(25)
	if career.bump("photos") >= 25:
		_award("paparazzi")
	GameState.add_score(10 + 15 * documented.size() + (10 if quality >= 80 else 0))
	_save_progress(true)


# ---------------------------------------------------------------- hearings, meetings, events

func _run_hearing(house: int) -> void:
	if _is_over:
		return
	var info := sim.build_hearing(house)
	info.address = _street.lot_address(house)
	_overlay.show()
	Sfx.set_loop("murmur", 0.8)
	Sfx.set_mood("tense")
	_hearing_active = true
	var panel: Panel = HearingPanel.new()
	panel.setup(info)
	panel.decided.connect(func(recommendation: String, present: bool):
		_close_overlay()
		_hearing_active = false
		var result := sim.hold_hearing(house, recommendation, present)
		Settings.haptic(45)
		if sim.board.tally(result.votes) == 3:
			_award("unanimous_ish")
		sim.apply_effects("Hearing · %s" % _street.lot_address(house), result.effects)
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


func _run_meeting(votes: Array, title := "ANNUAL MEETING") -> void:
	var retain := sim.board.tally(votes)
	Settings.haptic(60)
	var lines: Array = ["%d of %d members vote to retain you." % [retain, votes.size()]]
	var ousted := retain * 2 <= votes.size()
	var term_done := false
	if ousted:
		lines.append("You have been voted out.")
	else:
		var bonus := GameState.add_score(150)
		sim.board.shift(sim.politics, 4)
		lines.append("Re-elected! +%d points." % bonus)
		# Third annual meeting survived: the term is complete (once per term).
		if title == "ANNUAL MEETING" and GameState.day / HoaSim.ANNUAL_MEETING_EVERY >= Career.TERM_MEETINGS \
				and not bool(sim.politics.get("term_done", false)):
			sim.politics.term_done = true
			term_done = true
	_overlay.show()
	Sfx.set_loop("murmur", 0.8)
	Sfx.set_mood("tense" if ousted or retain * 2 <= votes.size() + 1 else "triumph")
	var panel: Panel = VotePanel.new()
	panel.setup(title, lines, votes, "CONTINUE")
	panel.closed.connect(func():
		_close_overlay()
		if ousted:
			GameState.force_end("Voted out at the annual meeting. Recount denied.")
		elif term_done:
			_show_term_complete()
		else:
			_next_morning_step())
	_overlay.add_child(panel)


## A full term survived: rating, unlock progress, and the choice to keep governing.
func _show_term_complete() -> void:
	var support := sim.board_support()
	var rating := career.record_term(int(GameState.stats.power), int(GameState.stats.happiness), int(GameState.stats.budget), support, sim.legal_risk())
	_award("term_complete")
	_overlay.show()
	var modal := UiKit.modal(size, Vector2(620, 600), "TERM COMPLETE")
	_overlay.add_child(modal.root)
	modal.body.add_child(UiKit.label("%s survived %d annual meetings." % [sim.community_name, Career.TERM_MEETINGS], 26, UiKit.INK, true))
	modal.body.add_child(UiKit.label("Governance rating  %d / 100" % rating, 34, UiKit.GOOD, true))
	var unlocked: Array = []
	for c: Dictionary in career.communities:
		if int(c.get("unlock", {}).get("terms", 0)) == career.terms_completed:
			unlocked.append(str(c.name))
	if not unlocked.is_empty():
		modal.body.add_child(UiKit.label("New community unlocked: %s" % ", ".join(unlocked), 24, UiKit.ACCENT, true))
	modal.body.add_child(UiKit.label("Keep governing for a higher score, or start a new term somewhere harder from the title screen.", 18, UiKit.MUTED, true))
	var go := UiKit.button("KEEP GOVERNING", 28, 80)
	go.pressed.connect(func():
		_close_overlay()
		_next_morning_step())
	modal.footer.add_child(go)
	var title := UiKit.button("TITLE SCREEN", 24, 66)
	title.pressed.connect(func():
		_close_overlay()
		_save_progress()
		_show_title())
	modal.footer.add_child(title)


func _show_report(title: String, lines: Array, button_text: String) -> void:
	_overlay.show()
	var modal := UiKit.modal(size, Vector2(620, clampf(300.0 + 46.0 * lines.size(), 420.0, 860.0)), title)
	_overlay.add_child(modal.root)
	for line in lines:
		modal.body.add_child(UiKit.label("• %s" % str(line), 22, UiKit.INK))
	var btn := UiKit.button(button_text, 32, 84)
	btn.pressed.connect(func():
		_close_overlay()
		_next_morning_step())
	modal.footer.add_child(btn)


## A director phones with a request. Complying is tempting; consistency is remembered.
func _maybe_board_call() -> void:
	if _is_over or _overlay.visible:
		_next_morning_step()
		return
	var call := sim.pick_board_call(GameState.day)
	if call.is_empty():
		_next_morning_step()
		return
	var text := str(call.text).replace("{who}", str(call.who_name)).replace("{owner}", sim.owner_of(int(call.house))) \
			.replace("{address}", _street.lot_address(int(call.house)))
	_overlay.show()
	Sfx.play("notify")
	var modal := UiKit.modal(size, Vector2(620, 540), "INCOMING CALL")
	_overlay.add_child(modal.root)
	modal.body.add_child(UiKit.label(str(Board.member(int(call.member_index)).temperament), 18, UiKit.MUTED, true))
	modal.body.add_child(UiKit.label(text, 26, UiKit.INK))
	for choice: Dictionary in call.choices:
		var btn := UiKit.button(str(choice.label), 24, 76)
		btn.pressed.connect(func():
			Sfx.play("tap")
			var line := sim.apply_board_call(call, choice)
			_close_overlay()
			_refresh()
			_float_small(line)
			_next_morning_step())
		modal.footer.add_child(btn)


## One agenda item (architectural request, assessment, vendor bid, project, politics, drama).
func _maybe_event() -> void:
	if _is_over or GameState.day <= 1 or _events.is_empty() or randf() > 0.5 or _overlay.visible:
		return
	if GameState.day % HoaSim.ANNUAL_MEETING_EVERY == 0:
		return
	# Complexity arrives gradually: vendors, politics and legal items wait for later days.
	var min_day := {"architectural": 2, "assessment": 3, "vendor": 4, "project": 3, "politics": 5, "insurance": 6, "reserve": 6, "legal": 7}
	var eligible: Array = []
	for e: Dictionary in _events:
		if GameState.day >= int(min_day.get(str(e.get("category", "")), 2)):
			eligible.append(e)
	if eligible.is_empty():
		return
	var event: Dictionary = (eligible[randi() % eligible.size()] as Dictionary).duplicate(true)
	var house: int = randi() % _street.house_count()
	event.who = str(event.who).replace("{owner}", sim.owner_of(house)).replace("{address}", _street.lot_address(house))
	event.house = house
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
	if choice.has("vendor"):
		sim.apply_vendor(choice.vendor)
	if choice.has("policy"):
		sim.apply_policy(choice.policy)
	if choice.has("arc") and data.has("house"):
		# Approved work is remembered; a later complaint asks whether it was built as approved.
		sim.register_arc(int(data.house), choice.arc)
	if choice.has("project"):
		sim.projects.append((choice.project as Dictionary).duplicate(true))
	sim.record_agenda(str(data.get("who", "Agenda")), str(choice.get("label", side)))
	GameState.add_score(25)
	sim.apply_effects(str(data.get("who", "Agenda item")), effects)
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
	var modal := UiKit.modal(size, Vector2(600, 560), "DAY %d COMPLETE" % finished)
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
	_hearing_active = false
	Sfx.set_loop("murmur", 0.0)
	Sfx.set_mood("calm")
	for child in _overlay.get_children():
		child.queue_free()
	_card = null
	_overlay.hide()


func _on_game_over(reason: String) -> void:
	_close_property_card()
	_close_preview()
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
	var alarm := false
	for key in GameState.STAT_KEYS:
		var v: int = GameState.stats[key]
		alarm = alarm or v <= 20 or v >= 80
	if sim.politics.size() > 0 and (sim.board_support() < 35 or sim.legal_risk() > 65):
		alarm = true
	_stats_button.text = "STATS !" if alarm else "STATS"
	if int(GameState.stats.get("happiness", 50)) <= 10:
		_award("everyone_hates_me")
	_refresh_version_chip()
	_stats_button.add_theme_color_override("font_color", Color("ff8a7a") if alarm else Color.WHITE)
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
		_politics_label.text = "MOOD: %s · COUNSEL: %s" % [sim.board.outlook(sim.politics, GameState.stats, GameState.day), sim.board.counsel_mood(sim.politics)]


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
	var slot := _small_floats
	_small_floats += 1
	var label := _make_label(text, 26, Color.WHITE, true)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(size.x - 80, 60)
	label.position = Vector2(40, size.y * 0.42 + slot * 46.0)
	label.z_index = 20
	add_child(label)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 0.0, 1.4).set_delay(0.8)
	tween.tween_callback(func():
		_small_floats = maxi(0, _small_floats - 1)
		label.queue_free())


## The one source of truth for "what owns the screen right now". Derived from the nodes that
## are actually showing, so it cannot drift out of sync with the UI. WORLD means the player can walk.
func _compute_ui_state() -> String:
	if _encounter_active:
		return "CINEMATIC"
	if is_instance_valid(_preview_ui):
		return "PHOTO_PREVIEW"
	if _street.camera_ev.active:
		return "CAMERA"
	if is_instance_valid(_card_ui):
		return "COMPLAINT_VIEW" if (_card_ui as PropertyCard).expanded() else "PROPERTY_CONTEXT"
	if _overlay.visible:
		return "HEARING" if _hearing_active else "CASE_DECISION"
	if is_instance_valid(_title) or is_instance_valid(_modal) or is_instance_valid(_update_prompt) or _is_over:
		return "MODAL"
	return "WORLD"


## Backs out of the topmost layer: the same action every Back/Close button performs.
func close_topmost() -> bool:
	match ui_state:
		"PHOTO_PREVIEW":
			_on_preview_choice("cancel")
		"CAMERA":
			_street.cancel_camera()
		"PROPERTY_CONTEXT", "COMPLAINT_VIEW":
			_on_card_action("back")
		"CASE_DECISION":
			_back_to_card()
		"MODAL":
			if is_instance_valid(_modal):
				_close_modal()
			else:
				return false
		_:
			if _street.hud_view.gallery_open:
				_street.hud_view.gallery_open = false
			elif _street.hud_view.map_open:
				_street.hud_view.map_open = false
			else:
				return false
	return true


func _process(_delta: float) -> void:
	if not is_instance_valid(_street) or _street.house_count() == 0:
		return
	ui_state = _compute_ui_state()
	_street.ui_locked = ui_state != "WORLD" and ui_state != "CAMERA"
	_street.warm_up = _overlay.visible or is_instance_valid(_title) or is_instance_valid(_modal)
	if _street.debug_view and OS.is_debug_build():
		_debug_clock -= _delta
		if _debug_clock <= 0.0:
			_debug_clock = 1.0
			_street.debug_labels.clear()
			for house in sim.properties:
				var p: Dictionary = sim.properties[house]
				_street.debug_labels[int(house)] = "%s %s rel%d %s" % [str(p.owner), ",".join(p.get("traits", [])), int(p.get("relationship", 0)),
						str(sim.cases.get(house, {}).get("state", ""))]
	_update_hint()


## First-day coaching: one short line at a time, gone once the loop is understood.
func _update_hint() -> void:
	if Settings.tutorial_done or GameState.day != 1 or _phase != "street" or _overlay.visible or is_instance_valid(_title) or _encounter_active:
		_street.set_hint("")
		return
	var hint := ""
	var target: int = _street.objective
	match ui_state:
		"WORLD":
			if not _street.used:
				hint = "Drag anywhere to walk · pinch to zoom"
			elif target < 0 and not sim.completed.is_empty():
				hint = "Good work. Warnings start a cure period; you'll be back to reinspect."
			elif target >= 0 and _street.near != target:
				var gap: float = _street.player.position.distance_to(_street.hood.lots[target].inspect_anchor())
				hint = ("Follow the gold arrow to %s" % _street.lot_address(target)) if gap > 450.0 else ("Approach %s" % _street.lot_address(target))
			elif target >= 0:
				hint = "Tap INSPECT"
		"PROPERTY_CONTEXT", "COMPLAINT_VIEW":
			if target >= 0 and not _street.get_evidence().has(target):
				hint = "Tap TAKE PHOTO"
			elif target >= 0:
				hint = "Tap REVIEW & DECIDE"
		"CAMERA":
			hint = "Frame the issue, then tap the shutter"
		"PHOTO_PREVIEW":
			hint = "Tap USE PHOTO"
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
	_info_row = info
	info.add_theme_constant_override("separation", 10)
	vbox.add_child(info)
	_day_label = _make_label("DAY 1", 26, Color.WHITE)
	_day_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_day_label.custom_minimum_size = Vector2(110, 0)
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(_day_label)
	_score_label = _make_label("SCORE 0", 26, Color("ffd36e"), true)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(_score_label)
	_stats_button = Button.new()
	_stats_button.text = "STATS"
	_stats_button.custom_minimum_size = Vector2(112, 58)
	_stats_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stats_button.add_theme_font_size_override("font_size", 18)
	_stats_button.pressed.connect(func():
		Sfx.play("tap")
		_details.visible = not _details.visible)
	info.add_child(_stats_button)
	_menu_button = Button.new()
	_menu_button.text = "MENU"
	_menu_button.custom_minimum_size = Vector2(112, 58)
	_menu_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_menu_button.add_theme_font_size_override("font_size", 18)
	_menu_button.pressed.connect(func():
		Sfx.play("tap")
		_open_menu())
	info.add_child(_menu_button)
	# Secondary information: collapsed by default so the neighborhood stays dominant.
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	_details.visible = false
	vbox.add_child(_details)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 14)
	_details.add_child(stats_row)
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
	_details.add_child(meta)
	_politics_label = _make_label("", 17, Color("ffd36e"), true)
	_politics_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_politics_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_politics_label)
	_best_label = _make_label("BEST 0", 16, Color("b9d8e8"))
	_best_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	meta.add_child(_best_label)
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	_version_label = _make_label(Settings.version_text(), 16, Color("b9d8e8"), false)
	_version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	meta.add_child(_version_label)
	_street = Control.new()
	_street.set_script(STREET_SCRIPT)
	_street.world_seed = int(career.current().get("seed", 7771))
	_built_community = str(career.current().get("id", "oak_meadow"))
	_street.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_street.visit.connect(_on_visit)
	_street.photo_taken.connect(_on_photo)
	_street.discover.connect(_on_discover)
	_street.camera_exit.connect(_on_camera_exit)
	_street.photo_captured.connect(_on_photo_captured)
	_street.preview_enabled = true
	_street.evidence_changed.connect(func(): _save_progress())
	vbox.add_child(_street)
	_task_label = _make_label("", 22, Color.WHITE, true)
	_task_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bottom := HBoxContainer.new()
	vbox.add_child(bottom)
	bottom.add_child(_task_label)
	_version_chip = _make_label(Settings.version_text(), 16, Color(1, 1, 1, 0.75))
	_version_chip.autowrap_mode = TextServer.AUTOWRAP_OFF
	_version_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(_version_chip)
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
