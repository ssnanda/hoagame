extends Control
## Compact bottom sheet shown when the player reaches an assignment: address, what was
## reported (an allegation, never a verdict) and ONE obvious next action. The world stays
## visible above it. A transparent catcher keeps touches from reaching the street.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal action(name: String)   ## photo | case | inspect | measure | back

var info: Dictionary = {}
var _expanded := false
var _sheet: PanelContainer
var _holder: VBoxContainer


func setup(data: Dictionary) -> void:
	info = data


func _ready() -> void:
	if size == Vector2.ZERO and get_parent_control() != null:
		size = get_parent_control().size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 30
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.12)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", UiKit.panel_style(26))
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sheet.offset_left = 14.0
	_sheet.offset_right = -14.0
	_sheet.offset_bottom = -(18.0 + float(info.get("bottom_margin", 0.0)))
	add_child(_sheet)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_sheet.add_child(margin)
	_holder = VBoxContainer.new()
	_holder.add_theme_constant_override("separation", 10)
	margin.add_child(_holder)
	_build()


func _build() -> void:
	for child in _holder.get_children():
		child.queue_free()
	var reinspect := str(info.get("kind", "complaint")) == "reinspect"
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_holder.add_child(top)
	var back := UiKit.button("< BACK", 22, 64)
	back.custom_minimum_size = Vector2(150, 64)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): action.emit("back"))
	top.add_child(back)
	var tag := UiKit.label("REINSPECTION" if reinspect else "COMPLAINT", 20, UiKit.ACCENT)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(tag)
	_holder.add_child(UiKit.label(str(info.get("address", "")).to_upper(), 32, UiKit.INK))
	var summary := str(info.get("text", ""))
	_holder.add_child(UiKit.label(("Cure period ended. Check whether the notice was addressed." if reinspect else summary), 22, UiKit.INK))
	if _expanded:
		if str(info.get("source", "")) != "":
			_holder.add_child(UiKit.label("Reported by: %s" % str(info.source), 18, UiKit.MUTED))
		if str(info.get("reliability", "")) != "":
			_holder.add_child(UiKit.label(str(info.reliability), 16, UiKit.MUTED))
		if str(info.get("owner", "")) != "":
			_holder.add_child(UiKit.label("%s · %s" % [str(info.owner), str(info.get("relationship", ""))], 18, UiKit.ACCENT))
	var photos := int(info.get("photos", 0))
	if photos > 0:
		_holder.add_child(UiKit.label("Evidence attached · %d photo%s · best %d%%" % [photos, "" if photos == 1 else "s", int(info.get("quality", 0))], 20, UiKit.GOOD))
	# One dominant action. Before evidence: take a photo. After: review and decide.
	var primary_name := "photo"
	var primary_text := "TAKE PHOTO"
	if reinspect:
		primary_name = "inspect"
		primary_text = "INSPECT"
	elif photos > 0:
		primary_name = "case"
		primary_text = "REVIEW & DECIDE"
	var primary := UiKit.button(primary_text, 34, 96)
	_style_primary(primary)
	primary.pressed.connect(func(): action.emit(primary_name))
	_holder.add_child(primary)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_holder.add_child(row)
	var view := UiKit.button("HIDE DETAILS" if _expanded else "VIEW COMPLAINT", 18, 64)
	view.pressed.connect(func():
		_expanded = not _expanded
		action.emit("details_open" if _expanded else "details_closed")
		_build())
	row.add_child(view)
	if primary_name != "case" and not reinspect:
		var open_case := UiKit.button("OPEN CASE", 18, 64)
		open_case.pressed.connect(func(): action.emit("case"))
		row.add_child(open_case)
	if primary_name != "photo":
		var photo := UiKit.button("TAKE PHOTO" if photos == 0 else "TAKE ANOTHER", 18, 64)
		photo.pressed.connect(func(): action.emit("photo"))
		row.add_child(photo)
	if bool(info.get("can_measure", false)):
		var measure := UiKit.button("MEASURE LAWN", 18, 64)
		measure.pressed.connect(func(): action.emit("measure"))
		row.add_child(measure)


func _style_primary(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = UiKit.GOLD if state != "pressed" else UiKit.GOLD.darkened(0.15)
		box.set_corner_radius_all(18)
		box.shadow_size = 6
		box.shadow_color = Color(0, 0, 0, 0.25)
		btn.add_theme_stylebox_override(state, box)
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(slot, UiKit.INK)


## True while the extra complaint details are showing.
func expanded() -> bool:
	return _expanded
