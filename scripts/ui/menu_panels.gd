extends RefCounted
## Title screen, how to play, settings and about. Each builder returns a Control
## and reports user choices through signals/callables.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

static var _branding: Dictionary = {}


static func branding() -> Dictionary:
	if _branding.is_empty():
		var file := FileAccess.open("res://data/branding.json", FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_branding = parsed
	return _branding


## Title screen over the live neighborhood. `handlers`: continue, new_term, howto, settings, about.
static func title_screen(host_size: Vector2, can_continue: bool, handlers: Dictionary) -> Control:
	var b := branding()
	var root := ColorRect.new()
	root.color = Color(0.03, 0.08, 0.12, 0.62)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.size = Vector2(host_size.x - 120.0, 760.0)
	box.position = Vector2(60.0, host_size.y * 0.16)
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)
	var title := UiKit.label(str(b.get("title", "HOA PRESIDENT")), 74, Color.WHITE, true)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("outline_size", 12)
	box.add_child(title)
	box.add_child(UiKit.label(str(b.get("subtitle", "")), 28, UiKit.GOLD, true))
	box.add_child(Control.new())
	var buttons := [["continue", "CONTINUE", can_continue], ["new_term", "NEW TERM", true], ["communities", "COMMUNITIES", true],
			["howto", "TRAINING", true], ["settings", "SETTINGS", true], ["about", "ABOUT", true]]
	for item in buttons:
		if not bool(item[2]) or not handlers.has(str(item[0])):
			continue
		var btn := UiKit.button(str(item[1]), 30, 74)
		btn.pressed.connect(func():
			Sfx.play("tap")
			(handlers[str(item[0])] as Callable).call())
		box.add_child(btn)
	var foot := UiKit.label("%s\nDeveloped by %s\n%s" % [str(b.get("partner_line", "")), str(b.get("developer", "")), Settings.version_text()], 18, Color(1, 1, 1, 0.85), true)
	foot.custom_minimum_size = Vector2(host_size.x - 120.0, 60.0)
	box.add_child(foot)
	return root


const LESSONS := [
	["1  Getting Around", "Drag anywhere to walk. Pinch to zoom, tap RESET ZOOM to return. Stay on sidewalks and driveways. The golf cart (CART button) is faster but stays on the road; park it and walk in. Tap the minimap for the full map, or tap the Next chip to pick another destination."],
	["2  Inspecting & Photographing", "A complaint is an allegation, not proof. Walk up to the property and tap INSPECT. Use the camera: center the house, zoom, and get close. Rain, fog and storms cost photo quality. Good evidence backs up your decision later; poor evidence gets questioned at hearings."],
	["3  The Case Sheet", "Tick only the violations you can support, then choose: dismiss, warning, hearing or fine. A fine needs a prior notice (or a severe violation) and usable evidence. The sheet shows the homeowner, history and your relationship with them."],
	["4  Follow-Ups & Hearings", "Warnings start a cure period. When it ends you'll get a reinspection: walk back and see whether it was fixed, partly fixed, unchanged or worse. Unresolved cases go to a hearing where you recommend and the board votes. They can overrule you."],
	["5  Board Politics", "Five directors with their own priorities will call, pressure and vote. Favoring friends or targeting critics is remembered; residents will quote it back at you. Keep an eye on the board's mood and counsel. Three angry directors can force a recall."],
	["6  Seasons & Neighborhood", "Spring flowers and rain, summer heat and storms, fall leaves, winter snow. Violations follow the calendar. A game day is about a week. Annual meetings every ten days decide whether you keep your seat; surviving three completes a term."],
]


## Training: six optional lessons, each one screen. Replayable any time from the title or the menu.
static func how_to_play(host_size: Vector2, on_close: Callable) -> Control:
	var modal := UiKit.modal(host_size, Vector2(640, 900), "TRAINING")
	var body: VBoxContainer = modal.body
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 10)
	body.add_child(holder)
	var show_list: Callable
	show_list = func():
		for child in holder.get_children():
			child.queue_free()
		holder.add_child(UiKit.label("Pick a lesson. They're optional; you can learn by playing.", 18, UiKit.MUTED, true))
		for lesson in LESSONS:
			var b := UiKit.button(str(lesson[0]), 24, 72)
			b.pressed.connect(func():
				for child in holder.get_children():
					child.queue_free()
				holder.add_child(UiKit.label(str(lesson[0]), 28, UiKit.ACCENT))
				holder.add_child(UiKit.label(str(lesson[1]), 22, UiKit.INK))
				var back := UiKit.button("BACK TO LESSONS", 22, 62)
				back.pressed.connect(show_list)
				holder.add_child(back))
			holder.add_child(b)
	show_list.call()
	var btn := UiKit.button("CLOSE", 30, 78)
	btn.pressed.connect(on_close)
	modal.footer.add_child(btn)
	return modal.root


static func settings(host_size: Vector2, on_close: Callable, on_reset: Callable) -> Control:
	var modal := UiKit.modal(host_size, Vector2(640, 800), "SETTINGS")
	var body: VBoxContainer = modal.body
	for item in [["Sound effects", "sound"], ["Music", "music"], ["Haptics", "haptics"], ["Reduce motion", "reduce_motion"], ["Zoom out while walking", "zoom_out_walking"]]:
		var check := UiKit.check(str(item[0]), 28)
		check.button_pressed = bool(Settings.get(str(item[1])))
		check.toggled.connect(func(on):
			Settings.set(str(item[1]), on)
			Settings.save()
			Sfx.apply_settings())
		body.add_child(check)
	for item in [["Music volume", "music_volume"], ["Effects volume", "sfx_volume"]]:
		body.add_child(UiKit.label(str(item[0]), 24, UiKit.ACCENT))
		var vol := HSlider.new()
		vol.min_value = 0.0
		vol.max_value = 1.0
		vol.step = 0.05
		vol.value = float(Settings.get(str(item[1])))
		vol.custom_minimum_size = Vector2(0, 56)
		vol.value_changed.connect(func(v):
			Settings.set(str(item[1]), v)
			Settings.save()
			Sfx.apply_settings())
		body.add_child(vol)
	body.add_child(UiKit.label("Text size (applies to new panels)", 24, UiKit.ACCENT))
	var text_slider := HSlider.new()
	text_slider.min_value = 0.9
	text_slider.max_value = 1.3
	text_slider.step = 0.05
	text_slider.value = Settings.text_scale
	text_slider.custom_minimum_size = Vector2(0, 56)
	text_slider.value_changed.connect(func(v):
		Settings.text_scale = v
		Settings.save())
	body.add_child(text_slider)
	body.add_child(UiKit.label("Control sensitivity", 24, UiKit.ACCENT))
	var slider := HSlider.new()
	slider.min_value = 0.6
	slider.max_value = 1.6
	slider.step = 0.1
	slider.value = Settings.sensitivity
	slider.custom_minimum_size = Vector2(0, 56)
	slider.value_changed.connect(func(v):
		Settings.sensitivity = v
		Settings.save())
	body.add_child(slider)
	body.add_child(UiKit.label("Higher moves faster with less thumb travel.", 16, UiKit.MUTED))
	body.add_child(UiKit.label("Difficulty (next new term)", 24, UiKit.ACCENT))
	var diff := OptionButton.new()
	for name in ["Relaxed", "Standard", "Hard"]:
		diff.add_item(name)
	diff.selected = Settings.difficulty
	diff.custom_minimum_size = Vector2(0, 56)
	diff.add_theme_font_size_override("font_size", 24)
	diff.item_selected.connect(func(i):
		Settings.difficulty = i
		Settings.save())
	body.add_child(diff)
	var replay := UiKit.button("REPLAY FIRST-DAY TUTORIAL", 22, 62)
	replay.pressed.connect(func():
		Settings.tutorial_done = false
		Settings.save()
		replay.text = "TUTORIAL WILL REPLAY ON DAY 1")
	body.add_child(replay)
	body.add_child(UiKit.label("Pinch to zoom the neighborhood. Tap RESET ZOOM to return.", 16, UiKit.MUTED))
	var reset := UiKit.button("RESET CURRENT GAME", 24, 70)
	reset.pressed.connect(on_reset)
	body.add_child(reset)
	var close := UiKit.button("DONE", 30, 78)
	close.pressed.connect(on_close)
	modal.footer.add_child(close)
	return modal.root


static func about(host_size: Vector2, on_close: Callable, update_status := "") -> Control:
	var b := branding()
	var modal := UiKit.modal(host_size, Vector2(640, 900), "ABOUT")
	var body: VBoxContainer = modal.body
	body.add_child(UiKit.label(str(b.get("title", "HOA PRESIDENT")), 40, UiKit.ACCENT, true))
	body.add_child(UiKit.label("Version %s" % Settings.version_text().trim_prefix("v"), 22, UiKit.INK, true))
	if update_status != "":
		body.add_child(UiKit.label(update_status, 18, UiKit.GOOD if update_status.begins_with("Up to date") else UiKit.MUTED, true))
	body.add_child(UiKit.section("DEVELOPED BY"))
	body.add_child(UiKit.label("%s\n%s" % [str(b.get("developer", "")), str(b.get("location", ""))], 26, UiKit.INK, true))
	body.add_child(UiKit.section("COMMUNITY MANAGEMENT PARTNER / INSPIRATION"))
	body.add_child(UiKit.label(str(b.get("partner", "")), 28, UiKit.INK, true))
	body.add_child(UiKit.label(str(b.get("partner_blurb", "")), 18, UiKit.MUTED, true))
	body.add_child(UiKit.section("MADE WITH"))
	body.add_child(UiKit.label("Godot Engine 4 — free and open source, MIT License. © Juan Linietsky, Ariel Manzur and the Godot Engine contributors. godotengine.org", 17, UiKit.INK))
	body.add_child(UiKit.label("All art and sound are generated in code. No third-party assets.", 17, UiKit.MUTED))
	body.add_child(UiKit.section("PRIVACY"))
	body.add_child(UiKit.label(str(b.get("privacy", "")), 17, UiKit.INK))
	var links: Dictionary = b.get("links", {})
	for key in ["wozig", "privacy", "support"]:
		var url := str(links.get(key, ""))
		if url != "":
			var btn := UiKit.button(str(key).capitalize(), 22, 60)
			btn.pressed.connect(func(): OS.shell_open(url))
			body.add_child(btn)
	var close := UiKit.button("CLOSE", 30, 78)
	close.pressed.connect(on_close)
	modal.footer.add_child(close)
	return modal.root


## Community picker and achievements. `career` is a Career; `on_select(id)` is called for unlocked ones.
static func communities(host_size: Vector2, career, on_select: Callable, on_close: Callable) -> Control:
	var modal := UiKit.modal(host_size, Vector2(640, 1000), "COMMUNITIES")
	var body: VBoxContainer = modal.body
	body.add_child(UiKit.label("Complete terms to unlock harder communities.   Terms: %d" % career.terms_completed, 18, UiKit.MUTED, true))
	for c: Dictionary in career.communities:
		var unlocked: bool = career.is_unlocked(str(c.id))
		var selected: bool = str(c.id) == career.selected
		body.add_child(UiKit.label("%s  ·  %s" % [str(c.name), str(c.kind)], 24, UiKit.ACCENT if unlocked else UiKit.MUTED))
		body.add_child(UiKit.label(str(c.blurb), 17, UiKit.INK if unlocked else UiKit.MUTED))
		if unlocked:
			var pick := UiKit.button("SELECTED" if selected else "SELECT FOR NEW TERM", 20, 54)
			pick.disabled = selected
			pick.pressed.connect(func():
				on_select.call(str(c.id)))
			body.add_child(pick)
		else:
			var need: int = int(c.get("unlock", {}).get("terms", 0))
			body.add_child(UiKit.label("LOCKED · complete %d term%s" % [need, "" if need == 1 else "s"], 16, UiKit.BAD))
	body.add_child(UiKit.section("ACHIEVEMENTS · %d / %d" % [career.earned.size(), career.achievements.size()]))
	for a: Dictionary in career.achievements:
		var got: bool = career.earned.has(str(a.id))
		body.add_child(UiKit.label("%s %s — %s" % ["★" if got else "☆", str(a.name), str(a.desc)], 17, UiKit.GOOD if got else UiKit.MUTED))
	var close := UiKit.button("CLOSE", 28, 74)
	close.pressed.connect(on_close)
	modal.footer.add_child(close)
	return modal.root
