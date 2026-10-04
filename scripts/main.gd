extends Control
## Builds the HUD in code, spawns cards, handles game over.

const CARD_SCENE := preload("res://scenes/card.tscn")
const CARD_SIZE := Vector2(600, 640)
const STAT_LABELS := {"budget": "BUDGET", "happiness": "HAPPY", "power": "POWER"}

var _bars: Dictionary = {}
var _day_label: Label
var _card_area: Control
var _card: Panel
var _over_panel: Control
var _over_label: Label
var _is_over := false


func _ready() -> void:
	_build_ui()
	GameState.stats_changed.connect(_refresh)
	GameState.game_over.connect(_on_game_over)
	await get_tree().process_frame  # let containers lay out before placing the card
	_start()


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
	GameState.new_game()
	_spawn_card()


func _spawn_card() -> void:
	_card = CARD_SCENE.instantiate()
	_card.size = CARD_SIZE
	_card_area.add_child(_card)
	var x := (_card_area.size.x - CARD_SIZE.x) / 2.0
	_card.setup(GameState.next_card(), Vector2(x, 20))
	_card.swiped.connect(_on_swiped)


func _on_swiped(side: String) -> void:
	var data: Dictionary = _card.data
	_card.queue_free()
	_card = null
	GameState.choose(data, side)
	if not _is_over:
		_spawn_card()


func _on_game_over(reason: String) -> void:
	_is_over = true
	_over_label.text = "%s\n\nSurvived %d days." % [reason, GameState.day - 1]
	_over_panel.show()


func _refresh() -> void:
	_day_label.text = "DAY %d" % GameState.day
	for key in _bars:
		var bar: ProgressBar = _bars[key]
		var value: int = GameState.stats[key]
		create_tween().tween_property(bar, "value", value, 0.2)
		bar.modulate = Color("e0533d") if value <= 20 or value >= 80 else Color.WHITE


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("2f4858")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "HOA PRESIDENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	vbox.add_child(title)

	_day_label = Label.new()
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_day_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_day_label)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 20)
	vbox.add_child(stats_row)
	for key in GameState.STAT_KEYS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_row.add_child(col)
		var label := Label.new()
		label.text = STAT_LABELS[key]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 24)
		bar.value = GameState.START_VALUE
		col.add_child(bar)
		_bars[key] = bar

	var street := Control.new()
	street.set_script(preload("res://scripts/street.gd"))
	vbox.add_child(street)

	_card_area = Control.new()
	_card_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_card_area)

	_build_game_over()


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

	_over_label = Label.new()
	_over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_label.add_theme_font_size_override("font_size", 38)
	box.add_child(_over_label)

	var button := Button.new()
	button.text = "Run Again"
	button.custom_minimum_size = Vector2(0, 90)
	button.add_theme_font_size_override("font_size", 36)
	button.pressed.connect(_start)
	box.add_child(button)
