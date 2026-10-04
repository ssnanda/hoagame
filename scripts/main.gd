extends Control
## HUD + day loop: walk the street, investigate complaint pins, keep score.

const CARD_SCENE := preload("res://scenes/card.tscn")
const STREET_SCRIPT := preload("res://scripts/street.gd")
const LAWN_SCRIPT := preload("res://scripts/lawn_game.gd")
const CARD_SIZE := Vector2(600, 640)
const STAT_LABELS := {"budget": "BUDGET", "happiness": "HAPPY", "power": "POWER"}
const RESIDENTS := [
	"The Hendersons", "Gary & Pam", "Dave, Lot 27", "Linda", "Mr. Okafor", "The Pattersons",
	"Priya & Arun", "The Garcias", "Martha, Lot 31", "Coach Williams", "The Chens", "Beth & Her Gnomes",
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


func _ready() -> void:
	_build_ui()
	GameState.stats_changed.connect(_refresh)
	GameState.game_over.connect(_on_game_over)
	await get_tree().process_frame
	if GameState.has_saved_run:
		_resume_run()
	else:
		_start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and is_instance_valid(_street) and not _is_over:
		_save_progress()


func _unhandled_key_input(event: InputEvent) -> void:
	if _card == null or _is_over:
		return
	if event.is_action_pressed("ui_left"):
		_card.fling("left")
	elif event.is_action_pressed("ui_right"):
		_card.fling("right")


func _start() -> void:
	_is_over = false
	_over_panel.hide()
	_close_overlay()
	GameState.clear_run()
	GameState.new_game()
	_new_day()


func _new_day() -> void:
	var count := mini(4 + (GameState.day - 1) / 3, 8)
	var houses: Array = range(STREET_SCRIPT.HOUSE_COUNT)
	houses.shuffle()
	_complaints = {}
	_grass = []
	_completed = []
	_phase = "street"
	_evening_bonus = {}
	for i in STREET_SCRIPT.HOUSE_COUNT:
		_grass.append(randf_range(2.5, 4.5))
	var pins := {}
	for n in count:
		var h: int = houses[n]
		if randf() < 0.45:
			_grass[h] = randf_range(6.8, 10.0) if randf() < 0.5 else randf_range(3.5, 5.4)
			_complaints[h] = {"kind": "lawn"}
		else:
			_complaints[h] = {"kind": "card", "card": GameState.next_card()}
		pins[h] = _complaints[h].kind
	_done = 0
	_street.set_day(pins, _grass)
	_update_task()
	_float("DAY %d" % GameState.day, Color("ffd36e"))
	_save_progress()


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
	var pins := {}
	for house in _complaints:
		var h := int(house)
		pins[h] = "done" if h in _completed else str(_complaints[house].get("kind", "card"))
	var saved_position = world.get("player_position", Vector2(-1.0, float(world.get("player_y", -1.0))))
	if int(world.get("world_version", 1)) < 2:
		saved_position = Vector2(-1.0, saved_position.y)
	_street.set_day(pins, _grass, _done, saved_position)
	_update_task()
	_refresh()
	_float("WELCOME BACK", Color("ffd36e"))
	if _phase == "evening":
		_show_evening(GameState.day, _evening_bonus)


func _update_task() -> void:
	var left := _complaints.size() - _done
	_task_label.text = "Walk up the driveway · tap flag · camera saves photos  ·  %d left" % left


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
		_card = CARD_SCENE.instantiate()
		_card.size = CARD_SIZE
		_overlay.add_child(_card)
		_card.setup(comp.card, (size - CARD_SIZE) / 2.0)
		_card.swiped.connect(_on_swiped)


func _resident_name(house: int) -> String:
	if house < RESIDENTS.size():
		return RESIDENTS[house]
	return ["The Parkers", "The Robinsons", "The Patels", "The Wilsons",
			"The Nguyens", "The Millers"][house % 6]


func _on_lawn_done(effects: Dictionary, points: int, correct: bool) -> void:
	_resolve(effects, points, correct)


func _on_swiped(side: String) -> void:
	var data: Dictionary = _card.data
	_card.queue_free()
	_card = null
	_resolve(data.get(side, {}).get("effects", {}), 25, null)


func _resolve(effects: Dictionary, points: int, correct) -> void:
	var gained := GameState.add_score(points, correct)
	GameState.apply_effects(effects)
	_close_overlay()
	if _is_over:
		return
	_float("%+d" % gained, Color("7ee081") if gained >= 0 else Color("ff6b5a"))
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
	panel.size = Vector2(600, 560)
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
		"world_version": 3,
		"complaints": _complaints.duplicate(true),
		"grass": _grass.duplicate(),
		"completed": _completed.duplicate(),
		"phase": _phase,
		"evening_bonus": _evening_bonus.duplicate(true),
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
