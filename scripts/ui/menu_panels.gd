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
	var buttons := [["continue", "CONTINUE", can_continue], ["new_term", "NEW TERM", true], ["howto", "HOW TO PLAY", true],
			["settings", "SETTINGS", true], ["about", "ABOUT", true]]
	for item in buttons:
		if not bool(item[2]):
			continue
		var btn := UiKit.button(str(item[1]), 32, 82)
		btn.pressed.connect(func():
			Sfx.play("tap")
			(handlers[str(item[0])] as Callable).call())
		box.add_child(btn)
	var foot := UiKit.label("%s\nDeveloped by %s" % [str(b.get("partner_line", "")), str(b.get("developer", ""))], 18, Color(1, 1, 1, 0.85), true)
	foot.custom_minimum_size = Vector2(host_size.x - 120.0, 60.0)
	box.add_child(foot)
	return root


static func how_to_play(host_size: Vector2, on_close: Callable) -> Control:
	var modal := UiKit.modal(host_size, Vector2(640, 900), "HOW TO PLAY")
	var body: VBoxContainer = modal.body
	var steps := [
		["1  Walk", "Drag anywhere to walk. Stay on sidewalks and driveways. The golf cart is faster but can't use driveways."],
		["2  Find a complaint", "Gold pins are complaints. A complaint is not proof: some are wrong."],
		["3  Inspect", "Stand near the property and tap INSPECT PROPERTY."],
		["4  Photograph", "Use the camera. Center the house, zoom, and get close. Good photos back up your decision."],
		["5  Decide", "Tick the violations you can support, then dismiss, warn, schedule a hearing or fine."],
		["6  Follow up", "Warnings have a cure period. You'll return to reinspect. Unresolved cases go to a hearing."],
		["7  Survive", "Watch Treasury, Community and Authority, the board's support and your legal risk. Be fair, or the annual meeting will be short."],
	]
	for s in steps:
		body.add_child(UiKit.label(str(s[0]), 24, UiKit.ACCENT))
		body.add_child(UiKit.label(str(s[1]), 20, UiKit.INK))
	var btn := UiKit.button("GOT IT", 30, 78)
	btn.pressed.connect(on_close)
	modal.footer.add_child(btn)
	return modal.root


static func settings(host_size: Vector2, on_close: Callable, on_reset: Callable) -> Control:
	var modal := UiKit.modal(host_size, Vector2(640, 800), "SETTINGS")
	var body: VBoxContainer = modal.body
	for item in [["Sound effects", "sound"], ["Music", "music"], ["Haptics", "haptics"], ["Reduce motion", "reduce_motion"]]:
		var check := UiKit.check(str(item[0]), 28)
		check.button_pressed = bool(Settings.get(str(item[1])))
		check.toggled.connect(func(on):
			Settings.set(str(item[1]), on)
			Settings.save()
			Sfx.apply_settings())
		body.add_child(check)
	body.add_child(UiKit.label("Control sensitivity", 24, UiKit.ACCENT))
	var slider := HSlider.new()
	slider.min_value = 0.6
	slider.max_value = 1.6
	slider.step = 0.1
	slider.value = Settings.sensitivity
	slider.custom_minimum_size = Vector2(0, 48)
	slider.value_changed.connect(func(v):
		Settings.sensitivity = v
		Settings.save())
	body.add_child(slider)
	body.add_child(UiKit.label("Higher moves faster with less thumb travel.", 16, UiKit.MUTED))
	var reset := UiKit.button("RESET CURRENT GAME", 24, 70)
	reset.pressed.connect(on_reset)
	body.add_child(reset)
	var close := UiKit.button("DONE", 30, 78)
	close.pressed.connect(on_close)
	modal.footer.add_child(close)
	return modal.root


static func about(host_size: Vector2, on_close: Callable) -> Control:
	var b := branding()
	var modal := UiKit.modal(host_size, Vector2(640, 900), "ABOUT")
	var body: VBoxContainer = modal.body
	body.add_child(UiKit.label(str(b.get("title", "HOA PRESIDENT")), 40, UiKit.ACCENT, true))
	body.add_child(UiKit.label("Version %s" % str(ProjectSettings.get_setting("application/config/version", "dev")), 20, UiKit.MUTED, true))
	body.add_child(UiKit.section("DEVELOPED BY"))
	body.add_child(UiKit.label("%s\n%s" % [str(b.get("developer", "")), str(b.get("location", ""))], 26, UiKit.INK, true))
	body.add_child(UiKit.section("COMMUNITY MANAGEMENT PARTNER / INSPIRATION"))
	body.add_child(UiKit.label(str(b.get("partner", "")), 28, UiKit.INK, true))
	body.add_child(UiKit.label(str(b.get("partner_blurb", "")), 18, UiKit.MUTED, true))
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
