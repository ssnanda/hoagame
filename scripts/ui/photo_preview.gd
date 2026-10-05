extends Control
## Review a framed shot before it becomes evidence: the picture, address, date, quality
## and what it recorded. USE PHOTO attaches it; the other buttons discard or retry.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal choice(name: String)   ## use | retake | another | cancel

var pending: Dictionary = {}
var address := ""
var labels: Array = []


func setup(shot: Dictionary, addr: String, recorded: Array) -> void:
	pending = shot
	address = addr
	labels = recorded


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.07, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var modal := UiKit.modal(size if size != Vector2.ZERO else Vector2(720, 1280), Vector2(640, 1000), "PHOTO PREVIEW")
	add_child(modal.root)
	var body: VBoxContainer = modal.body
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(pending.image)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(0, 420)
	body.add_child(rect)
	body.add_child(UiKit.label(address.to_upper(), 24, UiKit.INK, true))
	body.add_child(UiKit.label("Day %d · %s" % [GameState.day, GameState.date_text()], 18, UiKit.MUTED, true))
	var quality := int(pending.quality)
	var word := "Excellent" if quality >= 80 else ("Good" if quality >= 60 else "Usable, but weak")
	body.add_child(UiKit.label("Quality %d%% · %s" % [quality, word], 24, UiKit.GOOD if quality >= 60 else UiKit.BAD, true))
	if labels.is_empty():
		body.add_child(UiKit.label("Nothing clearly recorded in this shot.", 20, UiKit.MUTED, true))
	else:
		body.add_child(UiKit.label("Recorded: %s" % ", ".join(labels), 20, UiKit.INK, true))
	var use := UiKit.button("USE PHOTO", 32, 96)
	_gold(use)
	use.pressed.connect(func(): choice.emit("use"))
	modal.footer.add_child(use)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	modal.footer.add_child(row)
	for spec in [["RETAKE", "retake"], ["TAKE ANOTHER", "another"], ["CANCEL", "cancel"]]:
		var b := UiKit.button(str(spec[0]), 18, 64)
		b.pressed.connect(func(): choice.emit(str(spec[1])))
		row.add_child(b)


func _gold(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = UiKit.GOLD if state != "pressed" else UiKit.GOLD.darkened(0.15)
		box.set_corner_radius_all(18)
		btn.add_theme_stylebox_override(state, box)
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(slot, UiKit.INK)
