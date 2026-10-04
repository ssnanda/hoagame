extends Control
## HUD + day loop: walk the street, investigate complaint pins, keep score.

const CARD_SCENE := preload("res://scenes/card.tscn")
const STREET_SCRIPT := preload("res://scripts/street.gd")
const LAWN_SCRIPT := preload("res://scripts/lawn_game.gd")
const CASE_FILE_SCRIPT := preload("res://scripts/case_file.gd")
const CARD_SIZE := Vector2(600, 640)
const BOARD_NAMES := ["Pat Whitmore", "Lorraine Cho", "Ben Aldridge", "Dana Ruiz", "Walt Pruitt"]
const ANNUAL_MEETING_EVERY := 10
const FAVORED := ["friend", "board_member"]
const UPDATE_MANIFEST_URL := "https://raw.githubusercontent.com/ssnanda/hoagame/main/altstore.json"
const ALTSTORE_BUNDLE_ID := "com.ssnanda.hoagame"
const STAT_LABELS := {"budget": "BUDGET", "happiness": "HAPPY", "power": "POWER"}
const RESIDENTS := [
	"The Hendersons", "Gary & Pam", "Dave, Lot 27", "Linda", "Mr. Okafor", "The Pattersons",
	"Priya & Arun", "The Garcias", "Martha, Lot 31", "Coach Williams", "The Chens", "Beth & Her Gnomes",
]
const VIOLATION_CATALOG := [
	{"id": "tall_grass", "label": "Tall grass", "object": "weeds", "severity": 1},
	{"id": "dead_lawn", "label": "Dead lawn", "object": "dead_lawn", "severity": 1},
	{"id": "curb_bins", "label": "Bins left at curb", "object": "bins", "severity": 1},
	{"id": "rv", "label": "RV over 72 hours", "object": "rv", "severity": 2},
	{"id": "boat", "label": "Boat stored outside", "object": "boat", "severity": 2},
	{"id": "commercial_vehicle", "label": "Commercial vehicle", "object": "van", "severity": 2},
	{"id": "lawn_parking", "label": "Vehicle on lawn", "object": "car", "severity": 2},
	{"id": "broken_vehicle", "label": "Inoperable vehicle", "object": "car", "severity": 2},
	{"id": "shed", "label": "Unapproved shed", "object": "shed", "severity": 2},
	{"id": "fence", "label": "Unapproved fence", "object": "fence", "severity": 1},
	{"id": "hoop", "label": "Basketball hoop in street", "object": "hoop", "severity": 1},
	{"id": "yard_sign", "label": "Unapproved yard sign", "object": "sign", "severity": 1},
	{"id": "decorations", "label": "Expired decorations", "object": "decorations", "severity": 1},
	{"id": "paint", "label": "Exterior color violation", "object": "paint", "severity": 1},
	{"id": "siding", "label": "Damaged siding", "object": "damage", "severity": 2},
	{"id": "shrubs", "label": "Overgrown shrubs", "object": "shrubs", "severity": 1},
	{"id": "debris", "label": "Trash or construction debris", "object": "debris", "severity": 2},
	{"id": "addition", "label": "Unapproved addition", "object": "addition", "severity": 3},
	{"id": "short_rental", "label": "Short-term rental activity", "object": "rental", "severity": 2},
	{"id": "dog_waste", "label": "Pet waste issue", "object": "dog", "severity": 1},
	{"id": "noise", "label": "Noise complaint", "object": "noise", "severity": 1},
]

var _bars: Dictionary = {}
var _day_label: Label
var _score_label: Label
var _best_label: Label
var _task_label: Label
var _save_label: Label
var _version_label: Label
var _street: Control
var _margin: MarginContainer
var _overlay: ColorRect
var _card: Panel
var _over_panel: Control
var _over_label: Label
var _is_over := false
var _complaints: Dictionary = {}
var _grass: Array = []
var _active := -1
var _done := 0
var _completed: Array = []
var _phase := "street"
var _evening_bonus: Dictionary = {}
var _evidence: Dictionary = {}
var _properties: Dictionary = {}
var _cases: Dictionary = {}
var _update_request: HTTPRequest
var _update_prompt: Control
var _available_version := ""
var _altstore_launch_pending := false
var _politics: Dictionary = {}
var _projects: Array = []
var _events: Array = []
var _politics_label: Label


func _ready() -> void:
	_politics = _create_politics()
	_load_events()
	_build_ui()
	GameState.stats_changed.connect(_refresh)
	GameState.game_over.connect(_on_game_over)
	await get_tree().process_frame
	if GameState.has_saved_run:
		_resume_run()
	else:
		_start()
	_check_for_updates()


func _check_for_updates() -> void:
	_update_request = HTTPRequest.new()
	_update_request.timeout = 8.0
	add_child(_update_request)
	_update_request.request_completed.connect(_on_update_check_completed)
	var headers := PackedStringArray(["Cache-Control: no-cache", "Accept: application/json"])
	var error := _update_request.request(UPDATE_MANIFEST_URL, headers)
	if error != OK:
		_update_request.queue_free()


func _on_update_check_completed(result: int, response_code: int,
		headers: PackedStringArray, body: PackedByteArray) -> void:
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
			if _is_newer_version(remote_version,
					str(ProjectSettings.get_setting("application/config/version", "0.0.0"))):
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
	_update_prompt.z_index = 50
	add_child(_update_prompt)
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _card_style())
	panel.size = Vector2(600, 490)
	panel.position = (size - panel.size) / 2.0
	_update_prompt.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 32.0
	box.offset_right = -32.0
	box.offset_top = 32.0
	box.offset_bottom = -32.0
	panel.add_child(box)
	box.add_child(_make_label("UPDATE AVAILABLE", 38, Color("1c1b1f"), true))
	box.add_child(_make_label("HOA President %s" % _available_version, 30, Color("2f4858"), true))
	if not description.is_empty():
		box.add_child(_make_label(description, 22, Color("4d5660"), true))
	box.add_child(_make_label("AltStore will open. Choose Update in My Apps and keep AltServer running on your computer.",
			20, Color("4d5660"), true))
	var update_button := Button.new()
	update_button.text = "OPEN ALTSTORE"
	update_button.custom_minimum_size = Vector2(0, 76)
	update_button.add_theme_font_size_override("font_size", 28)
	update_button.pressed.connect(_open_altstore_update)
	box.add_child(update_button)
	var later_button := Button.new()
	later_button.text = "LATER"
	later_button.custom_minimum_size = Vector2(0, 62)
	later_button.add_theme_font_size_override("font_size", 24)
	later_button.pressed.connect(_dismiss_update_prompt)
	box.add_child(later_button)


func _open_altstore_update() -> void:
	# Start with the original app scheme. If it does not background this app, try
	# the newer AltStore Classic scheme after a short delay. The export preset
	# allowlists both schemes for iOS canOpenURL checks.
	_altstore_launch_pending = true
	OS.shell_open("altstore://")
	var fallback := get_tree().create_timer(0.65)
	fallback.timeout.connect(func():
		if _altstore_launch_pending:
			_altstore_launch_pending = false
			OS.shell_open("altstore-classic://")
	, CONNECT_ONE_SHOT)


func _dismiss_update_prompt() -> void:
	if is_instance_valid(_update_prompt):
		_update_prompt.queue_free()
	_update_prompt = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_altstore_launch_pending = false
	if what == NOTIFICATION_APPLICATION_PAUSED and is_instance_valid(_street) and not _is_over:
		_save_progress()


func _unhandled_key_input(event: InputEvent) -> void:
	if _card == null or _is_over:
		return
	if event.is_action_pressed("ui_left"):
		_card.fling("left")
	elif event.is_action_pressed("ui_right"):
		_card.fling("right")


func _load_events() -> void:
	var file := FileAccess.open("res://data/events.json", FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		_events = parsed


func _start() -> void:
	_politics = _create_politics()
	_projects = []
	_is_over = false
	_over_panel.hide()
	_close_overlay()
	GameState.clear_run()
	GameState.new_game()
	_properties = _create_properties()
	_cases = {}
	_new_day()


func _new_day() -> void:
	var season := GameState.season()
	var count := mini(4 + (GameState.day - 1) / 3, 8) + (1 if GameState.is_weekend() else 0)
	var houses: Array = range(STREET_SCRIPT.HOUSE_COUNT)
	# Repeat offenders and low-compliance homes are more likely to draw complaints.
	var order := {}
	for h in houses:
		var property: Dictionary = _properties.get(h, {})
		order[h] = randf() - 0.15 * int(property.get("repeat_count", 0)) - (0.2 if int(property.get("compliance", 60)) < 40 else 0.0)
	houses.sort_custom(func(a, b): return order[a] < order[b])
	var report: Array = []
	report.append_array(_process_open_cases())
	report.append_array(_process_projects())
	report.append_array(_process_politics())
	if GameState.day > 1 and GameState.day % ANNUAL_MEETING_EVERY == 0:
		report.append_array(_annual_meeting())
	if _is_over:
		return
	_complaints = {}
	_grass = []
	_completed = []
	_phase = "street"
	_evening_bonus = {}
	_evidence = {}
	var growth: float = [1.0, 1.15, 0.9, 0.7][season]
	for i in STREET_SCRIPT.HOUSE_COUNT:
		_grass.append(randf_range(2.5, 4.5) * growth)
	var pins := {}
	var visuals := {}
	for n in count:
		var h: int = houses[n]
		var allegations := _make_violations(h)
		var first: Dictionary = allegations[0]
		if first.id in ["tall_grass", "dead_lawn"]:
			if bool(first.actual):
				_grass[h] = randf_range(6.1, 6.9) if bool(first.borderline) else randf_range(6.8, 10.0)
			else:
				_grass[h] = randf_range(3.5, 5.4)
			_complaints[h] = {"kind": "lawn", "violations": allegations,
					"false_complaint": not bool(first.actual), "status": "assigned"}
		else:
			var false_complaint := allegations.all(func(v): return not bool(v.actual))
			_complaints[h] = {"kind": "card", "card": GameState.next_card(),
					"violations": allegations, "false_complaint": false_complaint, "status": "assigned"}
		pins[h] = _complaints[h].kind
		visuals[h] = allegations
	_done = 0
	_street.set_day(pins, _grass, 0, null, {}, visuals)
	_update_task()
	_float("DAY %d" % GameState.day, Color("ffd36e"))
	_refresh()
	_save_progress()
	if report.is_empty():
		_maybe_event()
	else:
		_show_report("MORNING REPORT · DAY %d" % GameState.day, report, "START DAY", _maybe_event)


## Generic scrolling notice panel (morning report, annual meeting, ...).
func _show_report(title: String, lines: Array, button_text: String, on_close: Callable) -> void:
	_overlay.show()
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _card_style())
	panel.size = Vector2(620, 860)
	panel.position = (size - panel.size) / 2.0
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 28.0
	box.offset_right = -28.0
	box.offset_top = 28.0
	box.offset_bottom = -28.0
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_make_label(title, 30, Color("1c1b1f"), true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for line in lines:
		list.add_child(_make_label("• %s" % str(line), 22, Color("1c1b1f")))
	var btn := Button.new()
	btn.text = button_text
	btn.custom_minimum_size = Vector2(0, 84)
	btn.add_theme_font_size_override("font_size", 32)
	btn.pressed.connect(func():
		_close_overlay()
		on_close.call())
	box.add_child(btn)


## One agenda item (architectural request, assessment, vendor bid, project, politics).
func _maybe_event() -> void:
	if _is_over or GameState.day <= 1 or _events.is_empty() or randf() > 0.55 or _overlay.visible:
		return
	if GameState.day % ANNUAL_MEETING_EVERY == 0:
		return
	var event: Dictionary = _events[randi() % _events.size()].duplicate(true)
	var house := randi() % STREET_SCRIPT.HOUSE_COUNT
	event.who = str(event.who).replace("{owner}", _property_owner(house)).replace("{address}", _property_address(house))
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
	_apply_political(effects)
	if choice.has("project"):
		_projects.append((choice.project as Dictionary).duplicate(true))
	GameState.add_score(25)
	GameState.apply_effects(effects)
	_close_overlay()
	_save_progress(true)


func _resume_run() -> void:
	var world := GameState.saved_world()
	if not world.has("complaints") or not world.has("grass"):
		_start()
		return
	_complaints = world.get("complaints", {}).duplicate(true)
	_grass = world.get("grass", []).duplicate(true)
	# Older runs had fewer lots. Fill only the new lots so existing lawn values and
	# completed cases remain intact when the denser neighborhood is introduced.
	while _grass.size() < STREET_SCRIPT.HOUSE_COUNT:
		_grass.append(randf_range(2.5, 4.5))
	_completed = world.get("completed", []).duplicate()
	_done = _completed.size()
	_phase = str(world.get("phase", "street"))
	_evening_bonus = world.get("evening_bonus", {}).duplicate(true)
	_evidence = world.get("evidence", {}).duplicate(true)
	_properties = world.get("properties", _create_properties()).duplicate(true)
	_cases = world.get("cases", {}).duplicate(true)
	_politics = world.get("politics", _create_politics()).duplicate(true)
	_projects = world.get("projects", []).duplicate(true)
	var fresh := _create_properties()
	for h in fresh:
		if not _properties.has(h):
			_properties[h] = fresh[h]
	var pins := {}
	var visuals := {}
	for house in _complaints:
		var h := int(house)
		pins[h] = "done" if h in _completed else str(_complaints[house].get("kind", "card"))
		visuals[h] = _complaints[house].get("violations", [])
	var saved_position = world.get("player_position", Vector2(-1.0, float(world.get("player_y", -1.0))))
	if int(world.get("world_version", 1)) < 2:
		saved_position = Vector2(-1.0, saved_position.y)
	_street.set_day(pins, _grass, _done, saved_position, _evidence, visuals)
	_update_task()
	_refresh()
	_float("WELCOME BACK", Color("ffd36e"))
	if _phase == "evening":
		_show_evening(GameState.day, _evening_bonus)


func _update_task() -> void:
	var left := _complaints.size() - _done
	_task_label.text = "%d inspections remaining" % left


func _on_visit(house: int) -> void:
	if _is_over or not _complaints.has(house) or _overlay.visible:
		return
	_active = house
	var comp: Dictionary = _complaints[house]
	_overlay.show()
	if comp.kind == "lawn":
		var game = LAWN_SCRIPT.new()
		game.setup(_grass[house], _resident_name(house))
		game.done.connect(_on_lawn_done)
		_overlay.add_child(game)
		game.position = ((size - Vector2(620, 880)) / 2.0).max(Vector2(20, 20))
	else:
		var property: Dictionary = _properties.get(house, {})
		var evidence: Dictionary = _street.get_evidence().get(house, {})
		var case_file = CASE_FILE_SCRIPT.new()
		case_file.setup({
			"address": _property_address(house),
			"owner": _property_owner(house),
			"relationship": property.get("relationship", "neutral"),
			"repeat_count": property.get("repeat_count", 0),
			"lot_type": property.get("lot_type", "standard"),
			"text": "%s: %s" % [str(comp.card.get("who", "Anonymous")), str(comp.card.get("text", ""))],
			"violations": comp.get("violations", []),
			"quality": evidence.get("quality", 0),
			"shots": evidence.get("shots", 0),
			"documented": evidence.get("documented", []),
			"history": property.get("history", []),
		})
		case_file.ruled.connect(_on_case_ruled)
		_overlay.add_child(case_file)
		case_file.position = ((size - CASE_FILE_SCRIPT.PANEL_SIZE) / 2.0).max(Vector2(20, 20))


func _on_photo(_house: int, quality: int, usable: bool, documented: Array) -> void:
	if not usable:
		GameState.add_score(-10)
		return
	GameState.add_score(10 + 15 * documented.size() + (10 if quality >= 80 else 0))
	_save_progress(true)


func _resident_name(house: int) -> String:
	if _properties.has(house):
		return _property_owner(house)
	if house < RESIDENTS.size():
		return RESIDENTS[house]
	return ["The Parkers", "The Robinsons", "The Patels", "The Wilsons",
			"The Nguyens", "The Millers"][house % 6]


func _create_properties() -> Dictionary:
	var result := {}
	var first_names := ["Avery", "Jordan", "Maya", "Noah", "Priya", "Mateo", "Nora", "Theo",
			"Lena", "Malik", "Sofia", "Eli", "June", "Arun", "Rosa", "Caleb"]
	var last_names := ["Parker", "Nguyen", "Patel", "Robinson", "Garcia", "Wilson", "Okafor",
			"Chen", "Miller", "Henderson", "Johnson", "Brown", "Davis", "Martinez"]
	for house in STREET_SCRIPT.HOUSE_COUNT:
		var owner := "%s %s" % [first_names[house % first_names.size()],
				last_names[(house * 7 + 3) % last_names.size()]]
		result[house] = {
			"owner": owner,
			"address": "%d %s" % [101 + house * 2, "COURT" if house >= STREET_SCRIPT.MAIN_HOUSE_COUNT else "HOA WAY"],
			"lot_type": "cul_de_sac" if house >= STREET_SCRIPT.MAIN_HOUSE_COUNT and house % 8 in [0, 1, 6, 7] else ("corner" if house % 11 == 0 else "standard"),
			"relationship": ["neutral", "friend", "critic", "board_member", "legal_threat"][house % 5],
			"repeat_count": 0,
			"history": [],
			"compliance": 55 + (house * 17) % 41,
		}
	return result


func _property_owner(house: int) -> String:
	return str(_properties.get(house, {}).get("owner", _resident_name_fallback(house)))


func _resident_name_fallback(house: int) -> String:
	if house < RESIDENTS.size():
		return RESIDENTS[house]
	return ["The Parkers", "The Robinsons", "The Patels", "The Wilsons",
			"The Nguyens", "The Millers"][house % 6]


func _property_address(house: int) -> String:
	return str(_properties.get(house, {}).get("address", "Lot %d" % (house + 1)))


func _make_violations(_house: int) -> Array:
	var season := GameState.season()
	var pool: Array = []
	for item in VIOLATION_CATALOG:
		var id := str(item.id)
		if season == 3 and id == "tall_grass":
			continue
		pool.append(item.duplicate(true))
		var boosted := (season == 1 and id in ["tall_grass", "hoop", "short_rental"]) \
				or (season >= 2 and id == "decorations") \
				or (GameState.is_weekend() and id in ["noise", "lawn_parking", "short_rental"])
		if boosted:
			pool.append(item.duplicate(true))
	pool.shuffle()
	var count := 1 + (1 if randf() < 0.3 else 0) + (1 if randf() < 0.12 else 0)
	var violations: Array = []
	var seen: Array = []
	for item in pool:
		if violations.size() >= count:
			break
		if str(item.id) in seen:
			continue
		seen.append(str(item.id))
		var roll := randf()
		item.actual = roll >= 0.22
		item.borderline = roll >= 0.22 and roll < 0.38
		item.documented = false
		violations.append(item)
	return violations


func _create_politics() -> Dictionary:
	var board: Array = []
	for i in BOARD_NAMES.size():
		board.append({"name": BOARD_NAMES[i], "support": 48 + (i * 7) % 17})
	return {"board": board, "legal": 10, "enforce": {}}


func _board_support() -> int:
	var board: Array = _politics.get("board", [])
	if board.is_empty():
		return 50
	var total := 0
	for member in board:
		total += int(member.support)
	return total / board.size()


## Shifts board support. `who` is a board index, or -1 for everyone.
func _shift_board(delta: int, who := -1) -> void:
	var board: Array = _politics.get("board", [])
	for i in board.size():
		if who < 0 or who == i:
			board[i].support = clampi(int(board[i].support) + delta, 0, 100)
	_politics.board = board


## Effects may carry the political keys "legal" (risk) and "board" (support).
func _apply_political(effects: Dictionary) -> void:
	_politics.legal = clampi(int(_politics.get("legal", 0)) + int(effects.get("legal", 0)), 0, 120)
	if effects.has("board"):
		_shift_board(int(effects.board))
	_refresh()


func _property_relationship(house: int) -> String:
	return str(_properties.get(house, {}).get("relationship", "neutral"))


func _on_case_ruled(action: String, cited: Array) -> void:
	var comp: Dictionary = _complaints[_active]
	var card: Dictionary = comp.card
	var actual_cited := 0
	var false_cited := 0
	for v in comp.get("violations", []):
		if str(v.id) in cited:
			if bool(v.actual):
				actual_cited += 1
			else:
				false_cited += 1
	var fx: Dictionary = {}
	var pts := 0
	var correct := false
	if action == "dismiss":
		fx = card.get("left", {}).get("effects", {}).duplicate(true)
		correct = bool(comp.get("false_complaint", false))
		pts = 100 if correct else -50
	else:
		fx = card.get("right", {}).get("effects", {}).duplicate(true)
		if action == "warning":
			for key in fx:
				fx[key] = roundi(float(fx[key]) * 0.6)
		elif action == "hearing":
			fx = {"power": 2}
		else:
			fx["budget"] = int(fx.get("budget", 0)) + 6
		correct = actual_cited > 0 and false_cited == 0
		pts = 100 if correct else (-25 if cited.is_empty() else -75)
	_close_overlay()
	_resolve(fx, pts, correct, action, cited)


func _record_case_outcome(house: int, action: String, correct, cited: Array) -> void:
	var complaint: Dictionary = _complaints[house]
	var false_complaint := bool(complaint.get("false_complaint", false))
	var property: Dictionary = _properties[house]
	var rel := str(property.get("relationship", "neutral"))
	var evidence: Dictionary = _street.get_evidence().get(house, {})
	var quality := int(evidence.get("quality", 0))
	var documented: Array = evidence.get("documented", [])
	var cited_actual := 0
	var cited_false := 0
	var cited_documented := 0
	for v in complaint.get("violations", []):
		if str(v.id) in cited:
			if bool(v.actual):
				cited_actual += 1
				if str(v.id) in documented:
					cited_documented += 1
			else:
				cited_false += 1
	var strength := 0.0
	if cited_actual > 0:
		strength = clampf(0.25 + 0.5 * float(cited_documented) / maxf(cited.size(), 1.0) + 0.25 * quality / 100.0, 0.0, 1.0)
		# A measured lawn is its own proof.
		if str(complaint.get("kind", "")) == "lawn":
			strength = maxf(strength, 0.7)
	var enforcing := action != "dismiss"
	var state := "cleared"
	if not enforcing:
		state = "cleared" if false_complaint else "missed_violation"
	else:
		var disputed := false_complaint or cited_false > 0 \
				or (strength < 0.5 and randf() < (0.6 if rel == "legal_threat" else 0.3))
		state = "disputed" if disputed else {"warning": "warning", "hearing": "hearing", "fine": "fined"}[action]
	var day := GameState.day
	_cases[house] = {
		"property": house,
		"address": _property_address(house),
		"owner": _property_owner(house),
		"violations": complaint.get("violations", []).duplicate(true),
		"false_complaint": false_complaint,
		"state": state,
		"action": action,
		"strength": strength,
		"opened_day": day,
		"cure_due": day + 2,
		"hearing_day": day + 1,
		"dispute_day": day + 1,
		"evidence": evidence.duplicate(true),
		"correct": correct,
	}
	var history: Array = property.get("history", [])
	history.append({"day": day, "state": state, "action": action,
			"violations": complaint.get("violations", []).duplicate(true)})
	property.history = history
	if enforcing and not false_complaint:
		property.repeat_count = int(property.get("repeat_count", 0)) + 1
	_properties[house] = property
	# Politics: who gets enforced against, and who pushes back.
	var tally: Dictionary = _politics.enforce.get(rel, {"cases": 0, "enforced": 0, "missed": 0})
	if not false_complaint:
		tally.cases = int(tally.cases) + 1
		if enforcing:
			tally.enforced = int(tally.enforced) + 1
		else:
			tally.missed = int(tally.missed) + 1
	_politics.enforce[rel] = tally
	var seat := house % BOARD_NAMES.size()
	if rel == "board_member":
		if enforcing:
			_shift_board(-12, seat)
			_shift_board(-2)
		elif not false_complaint:
			_shift_board(8, seat)
	if enforcing and (false_complaint or cited_false > 0):
		_apply_political({"legal": 6})
	if enforcing and rel == "legal_threat" and strength < 0.6:
		_apply_political({"legal": 8})
	if not enforcing and not false_complaint and rel == "critic":
		_apply_political({"board": -1})


func _compliance_roll(house: int, bonus := 0) -> bool:
	var property: Dictionary = _properties.get(house, {})
	var chance := int(property.get("compliance", 60)) + bonus - 8 * int(property.get("repeat_count", 0))
	return randi_range(0, 99) < clampi(chance, 10, 95)


func _board_vote(house: int, strength: float) -> int:
	var board: Array = _politics.board
	var rel := _property_relationship(house)
	var uphold := 0
	for i in board.size():
		var p := 0.3 + strength * 0.45 + (float(board[i].support) - 50.0) / 250.0
		if rel == "board_member":
			p -= 0.25 if i == house % board.size() else 0.1
		elif rel == "critic":
			p += 0.08
		if randf() < p:
			uphold += 1
	return uphold


## Advances every open case one day and returns report lines. Workflow:
## warning -> (uncured) hearing -> (upheld) fine -> compliance or repeat violation.
## A disputed notice is reviewed first and may be withdrawn.
func _process_open_cases() -> Array:
	var lines: Array = []
	var day := GameState.day
	for house_key in _cases.keys():
		var record: Dictionary = _cases[house_key]
		var house := int(house_key)
		var property: Dictionary = _properties.get(house, {})
		var address := _property_address(house)
		var rel := str(property.get("relationship", "neutral"))
		match str(record.get("state", "")):
			"disputed":
				if int(record.get("dispute_day", 9999)) > day:
					continue
				var strength := float(record.get("strength", 0.0))
				var win := 0.85 if bool(record.get("false_complaint", false)) else clampf((1.0 - strength) * 0.8, 0.1, 0.8)
				if randf() < win:
					record.state = "overturned"
					GameState.apply_effects({"budget": -12 if rel == "legal_threat" else -6, "happiness": 3})
					_apply_political({"legal": 6})
					lines.append("Dispute upheld at %s. Citation withdrawn." % address)
				else:
					record.state = {"warning": "warning", "hearing": "hearing", "fine": "fined"}.get(str(record.action), "warning")
					record.cure_due = day + 2
					record.hearing_day = day + 1
					GameState.apply_effects({"happiness": -2})
					lines.append("Dispute denied at %s. Notice stands." % address)
			"warning":
				if int(record.get("cure_due", 9999)) > day:
					continue
				if _compliance_roll(house):
					record.state = "compliant"
					GameState.add_score(35, true)
					lines.append("%s cured the warning." % address)
				else:
					record.state = "hearing"
					record.hearing_day = day + 1
					lines.append("No cure at %s. Hearing set for tomorrow." % address)
			"hearing":
				if int(record.get("hearing_day", 9999)) > day:
					continue
				var uphold := _board_vote(house, float(record.get("strength", 0.0)))
				var total: int = _politics.board.size()
				if uphold * 2 > total:
					var amount := 8 + 4 * int(property.get("repeat_count", 0))
					record.state = "fined"
					record.cure_due = day + 2
					GameState.apply_effects({"budget": amount, "happiness": -4})
					lines.append("Hearing at %s: board voted %d-%d. Fine upheld (+$%d)." % [address, uphold, total - uphold, amount])
				else:
					record.state = "overturned"
					GameState.apply_effects({"power": -3, "happiness": 2})
					lines.append("Hearing at %s: board voted %d-%d. Case dismissed." % [address, uphold, total - uphold])
			"fined":
				if int(record.get("cure_due", 9999)) > day:
					continue
				if _compliance_roll(house, 10):
					record.state = "compliant"
					GameState.add_score(35, true)
					lines.append("%s paid and is now compliant." % address)
				else:
					record.state = "repeat_violation"
					property.repeat_count = int(property.get("repeat_count", 0)) + 1
					property.compliance = maxi(5, int(property.get("compliance", 60)) - 8)
					GameState.apply_effects({"happiness": -3, "power": -2})
					lines.append("Repeat violation at %s (offense #%d)." % [address, int(property.repeat_count)])
			_:
				continue
		var history: Array = property.get("history", [])
		history.append({"day": day, "state": record.state, "action": "follow_up"})
		property.history = history
		_properties[house] = property
		_cases[house_key] = record
	return lines


func _process_projects() -> Array:
	var lines: Array = []
	var remaining: Array = []
	for project in _projects:
		var daily: Dictionary = project.get("daily", {})
		_apply_political(daily)
		GameState.apply_effects(daily)
		project.days = int(project.get("days", 1)) - 1
		if int(project.days) <= 0:
			var finish: Dictionary = project.get("finish", {})
			_apply_political(finish)
			GameState.apply_effects(finish)
			lines.append("%s finished." % str(project.get("name", "Project")))
		else:
			lines.append("%s: %d day(s) left." % [str(project.get("name", "Project")), int(project.days)])
			remaining.append(project)
	_projects = remaining
	return lines


func _enforce_rate(group: Array) -> Array:
	var cases := 0
	var enforced := 0
	for rel in group:
		var tally: Dictionary = _politics.enforce.get(rel, {})
		cases += int(tally.get("cases", 0))
		enforced += int(tally.get("enforced", 0))
	return [cases, float(enforced) / maxf(float(cases), 1.0)]


## Selective enforcement (critics cited far more than friends) feeds legal risk.
func _process_politics() -> Array:
	var lines: Array = []
	if GameState.day <= 1:
		return lines
	var favored := _enforce_rate(FAVORED)
	var critics := _enforce_rate(["critic", "legal_threat"])
	if int(favored[0]) >= 3 and int(critics[0]) >= 3 and float(critics[1]) - float(favored[1]) > 0.4:
		_apply_political({"legal": 8})
		lines.append("Residents allege selective enforcement. Legal risk rising.")
	else:
		_apply_political({"legal": -2})
	if int(_politics.legal) >= 100:
		GameState.apply_effects({"budget": -25, "power": -8})
		_politics.legal = 40
		lines.append("A lawsuit settles for $25. The board is not pleased.")
	elif int(_politics.legal) >= 70:
		lines.append("Legal risk is high (%d). Counsel advises caution." % int(_politics.legal))
	for member in _politics.board:
		if int(member.support) < 30:
			lines.append("%s is lobbying to remove you." % str(member.name))
			GameState.apply_effects({"power": -2})
			break
	return lines


func _annual_meeting() -> Array:
	var lines: Array = ["ANNUAL MEETING. The board votes on your future."]
	var power: int = GameState.stats.get("power", 50)
	var retain := 0
	for member in _politics.board:
		if float(member.support) + randf_range(-10.0, 10.0) + (power - 50) * 0.3 - int(_politics.legal) * 0.15 >= 45.0:
			retain += 1
	lines.append("%d of %d members vote to retain you." % [retain, _politics.board.size()])
	if retain * 2 <= _politics.board.size():
		GameState.force_end("Voted out at the annual meeting. Recount denied.")
		return lines
	var bonus := GameState.add_score(150)
	_shift_board(4)
	lines.append("Re-elected! +%d points." % bonus)
	return lines


func _open_case_count() -> int:
	var count := 0
	for record in _cases.values():
		if str(record.get("state", "")) in ["warning", "hearing", "fined", "disputed"]:
			count += 1
	return count


func _on_lawn_done(effects: Dictionary, points: int, correct: bool, fined: bool) -> void:
	var cited: Array = []
	if fined:
		cited.append(str(_complaints[_active].violations[0].id))
	_resolve(effects, points, correct, "fine" if fined else "dismiss", cited)


func _resolve(effects: Dictionary, points: int, correct, action := "warning", cited: Array = []) -> void:
	var gained := GameState.add_score(points, correct)
	GameState.apply_effects(effects)
	_close_overlay()
	if _is_over:
		return
	_float("%+d" % gained, Color("7ee081") if gained >= 0 else Color("ff6b5a"))
	_record_case_outcome(_active, action, correct, cited)
	_street.mark_done(_active)
	if _active not in _completed:
		_completed.append(_active)
	_done += 1
	_update_task()
	if _done >= _complaints.size():
		_evening()
	else:
		_save_progress(true)


func _evening() -> void:
	var finished := GameState.day
	var bonus := GameState.end_day()
	_phase = "evening"
	_evening_bonus = bonus.duplicate(true)
	_save_progress()
	_show_evening(finished, bonus)


func _show_evening(finished: int, bonus: Dictionary) -> void:
	_overlay.show()
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _card_style())
	panel.size = Vector2(600, 640)
	panel.position = (size - panel.size) / 2.0
	_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 32.0
	box.offset_right = -32.0
	box.offset_top = 32.0
	box.offset_bottom = -32.0
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(_make_label("DAY %d COMPLETE" % finished, 44, Color("1c1b1f"), true))
	box.add_child(_make_label("Day bonus  +%d" % bonus.day_bonus, 32, Color("1c1b1f")))
	box.add_child(_make_label("Balanced stats  +%d" % bonus.balance_bonus, 32, Color("1c1b1f")))
	box.add_child(_make_label("Streak  x%d" % GameState.streak, 32, Color("1c1b1f")))
	box.add_child(_make_label("Open cases  %d" % _open_case_count(), 32, Color("1c1b1f")))
	box.add_child(_make_label("SCORE  %d" % GameState.score, 44, Color("2f9e57"), true))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var btn := Button.new()
	btn.text = "NEXT DAY"
	btn.custom_minimum_size = Vector2(0, 90)
	btn.add_theme_font_size_override("font_size", 34)
	btn.pressed.connect(func():
		_close_overlay()
		GameState.next_day()
		_new_day())
	box.add_child(btn)


func _save_progress(show_feedback := false) -> void:
	if not is_instance_valid(_street) or _complaints.is_empty() or _is_over:
		return
	GameState.save_run({
		"world_version": 5,
		"politics": _politics.duplicate(true),
		"projects": _projects.duplicate(true),
		"complaints": _complaints.duplicate(true),
		"grass": _grass.duplicate(),
		"completed": _completed.duplicate(),
		"phase": _phase,
		"evening_bonus": _evening_bonus.duplicate(true),
		"evidence": _street.get_evidence(),
		"properties": _properties.duplicate(true),
		"cases": _cases.duplicate(true),
		"player_position": _street.get_player_position(),
	})
	if show_feedback and is_instance_valid(_save_label):
		_save_label.text = "SAVED"
		_save_label.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_property(_save_label, "modulate:a", 0.35, 1.2).set_delay(0.5)


func _close_overlay() -> void:
	for child in _overlay.get_children():
		child.queue_free()
	_card = null
	_overlay.hide()


func _on_game_over(reason: String) -> void:
	_is_over = true
	_close_overlay()
	_over_label.text = "%s\n\nSurvived %d days.\nScore %d  ·  Best %d" % [
			reason, GameState.day - 1, GameState.score, GameState.best]
	_over_panel.show()


func _refresh() -> void:
	_day_label.text = "DAY %d" % GameState.day
	_score_label.text = "SCORE %d" % GameState.score + ("  x%d" % GameState.streak if GameState.streak > 1 else "")
	_best_label.text = "BEST %d" % GameState.best
	if is_instance_valid(_politics_label) and not _politics.is_empty():
		_politics_label.text = "BOARD %d · LEGAL %d" % [_board_support(), int(_politics.get("legal", 0))]
	for key in _bars:
		var bar: ProgressBar = _bars[key]
		var value: int = GameState.stats[key]
		create_tween().tween_property(bar, "value", value, 0.2)
		bar.modulate = Color("e0533d") if value <= 20 or value >= 80 else Color.WHITE


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
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var info := HBoxContainer.new()
	vbox.add_child(info)
	_day_label = _make_label("DAY 1", 30, Color.WHITE)
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_day_label)
	_score_label = _make_label("SCORE 0", 30, Color("ffd36e"), true)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_score_label)
	_best_label = _make_label("BEST 0", 30, Color.WHITE)
	_best_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(_best_label)

	var meta := HBoxContainer.new()
	vbox.add_child(meta)
	_save_label = _make_label("AUTO-SAVE", 18, Color("b9d8e8"), false)
	_save_label.modulate.a = 0.35
	_save_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(_save_label)
	_politics_label = _make_label("", 18, Color("ffd36e"), false)
	_politics_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_politics_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_politics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_child(_politics_label)
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	_version_label = _make_label("v%s" % version, 18, Color("b9d8e8"), false)
	_version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_version_label.custom_minimum_size = Vector2(120, 0)
	_version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.add_child(_version_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 20)
	vbox.add_child(stats_row)
	for key in GameState.STAT_KEYS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_row.add_child(col)
		col.add_child(_make_label(STAT_LABELS[key], 22, Color.WHITE, true))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 20)
		bar.value = GameState.START_VALUE
		col.add_child(bar)
		_bars[key] = bar

	_street = Control.new()
	_street.set_script(STREET_SCRIPT)
	_street.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_street.visit.connect(_on_visit)
	_street.photo_taken.connect(_on_photo)
	vbox.add_child(_street)

	_task_label = _make_label("", 24, Color.WHITE, true)
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
	_over_panel.hide()
	add_child(_over_panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(80, 420)
	box.add_theme_constant_override("separation", 40)
	_over_panel.add_child(box)

	_over_label = _make_label("", 38, Color.WHITE, true)
	box.add_child(_over_label)

	var button := Button.new()
	button.text = "Run Again"
	button.custom_minimum_size = Vector2(0, 90)
	button.add_theme_font_size_override("font_size", 36)
	button.pressed.connect(_start)
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
		# Modern iOS reports the safe area. Use a modest fallback only when it does not.
		if top <= 0.0:
			top = 36.0
		if bottom <= 0.0:
			bottom = 18.0
	_margin.add_theme_constant_override("margin_top", 24 + int(top))
	_margin.add_theme_constant_override("margin_bottom", 24 + int(bottom))


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f4ecd8")
	style.set_corner_radius_all(28)
	style.shadow_size = 12
	style.shadow_color = Color(0, 0, 0, 0.35)
	return style


func _make_label(text: String, font_size: int, color: Color, centered := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
