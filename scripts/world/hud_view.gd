extends Control
## Mobile HUD drawn over the street: clock, controls, inspection prompt, camera
## frame, minimap, full map and the evidence album. Reads state from the street
## controller; the only decisions it makes are about its own panels.

const Neighborhood := preload("res://scripts/world/neighborhood.gd")
const LotScript := preload("res://scripts/world/lot.gd")
const Weather := preload("res://scripts/sim/weather.gd")
const DrawUtil := preload("res://scripts/world/draw_util.gd")
const EvidenceCamera := preload("res://scripts/world/evidence_camera.gd")

const MINI_SIZE := Vector2(104.0, 150.0)
const MINI_WINDOW := Vector2(1000.0, 1440.0)     ## world area the minimap shows around the player
const FEET_PER_PX := 0.75
const GALLERY_PAGE := 4
const ACTIVE_KINDS := ["lawn", "card", "reinspect"]
const STICK_RANGE := 86.0

var ctx
var map_open := false
var map_scroll := 0.0
var gallery_open := false
var gallery_page := 0
var gallery_sel := -1
var prompt_rect := Rect2()
var next_rect := Rect2()
var _mini: Control
var _mini_origin := Vector2.ZERO
var _mini_roads: Array = []
var _map: Control


func setup(controller) -> void:
	ctx = controller
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_mini = Control.new()
	_mini.clip_contents = true
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.draw.connect(_draw_minimap)
	add_child(_mini)
	_map = Control.new()
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_full_map)
	_map.visible = false
	add_child(_map)


func minimap_rect() -> Rect2:
	return Rect2(size.x - MINI_SIZE.x - 14.0, 14.0, MINI_SIZE.x, MINI_SIZE.y)


func _map_panel() -> Rect2:
	return Rect2(24.0, 28.0, size.x - 48.0, size.y - 56.0)


func _map_view() -> Rect2:
	var panel := _map_panel()
	return Rect2(panel.position + Vector2(20.0, 92.0), Vector2(panel.size.x - 40.0, panel.size.y - 92.0 - 76.0))


func open_map() -> void:
	map_open = true
	var view := _map_view()
	var scale := view.size.x / Neighborhood.WORLD_W
	map_scroll = clampf(ctx.player.position.y * scale - view.size.y * 0.5, 0.0, maxf(0.0, Neighborhood.WORLD_H * scale - view.size.y))


func _process(_delta: float) -> void:
	_mini.position = minimap_rect().position
	_mini.size = MINI_SIZE
	var view := _map_view()
	_map.position = view.position
	_map.size = view.size
	_map.visible = map_open
	_mini.visible = not map_open and not gallery_open
	if ctx != null:
		_mini.queue_redraw()
		_map.queue_redraw()


func _draw() -> void:
	if ctx == null or ctx.capturing:
		return
	var started := Time.get_ticks_usec()
	_draw_hud()
	ctx.perf.hud = lerpf(float(ctx.perf.hud), float(Time.get_ticks_usec() - started), 0.1)


func _draw_hud() -> void:
	_draw_ui()
	if ctx.camera_ev.active:
		_draw_camera_frame()
	if map_open:
		_draw_map_chrome()
	if gallery_open:
		_draw_gallery()
	if float(ctx.camera_flash) > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, float(ctx.camera_flash) * 0.72))


# ---------------------------------------------------------------- taps

## Returns true when a HUD control used the tap.
func handle_tap(pos: Vector2) -> bool:
	var camera = ctx.camera_ev
	if gallery_open:
		return _tap_gallery(pos)
	if map_open:
		_tap_map(pos)
		return true
	var w := size.x
	var h := size.y
	var shutter := pos.distance_to(Vector2(w - 66.0, h - 72.0)) <= 48.0
	if camera.active:
		var buttons := _zoom_buttons()
		if (buttons.cancel as Rect2).has_point(pos):
			camera.active = false
		elif (buttons.minus as Rect2).has_point(pos):
			camera.zoom = clampf(camera.zoom - 0.3, EvidenceCamera.ZOOM_MIN, EvidenceCamera.ZOOM_MAX)
		elif (buttons.plus as Rect2).has_point(pos):
			camera.zoom = clampf(camera.zoom + 0.3, EvidenceCamera.ZOOM_MIN, EvidenceCamera.ZOOM_MAX)
		elif shutter:
			ctx.take_photo()
		return true
	if shutter:
		ctx.open_camera()
		return true
	if prompt_rect.has_point(pos):
		ctx.inspect_near()
		return true
	if next_rect.has_point(pos):
		ctx.cycle_objective()
		return true
	if pos.distance_to(Vector2(w - 66.0, h - 172.0)) <= 38.0:
		gallery_open = true
		gallery_page = 0
		gallery_sel = -1
		return true
	if pos.distance_to(Vector2(w - 66.0, h - 262.0)) <= 38.0:
		ctx.toggle_cart()
		return true
	if absf(float(ctx.user_zoom) - 1.0) > 0.05 and zoom_reset_rect().has_point(pos):
		ctx.reset_zoom()
		return true
	if minimap_rect().grow(8.0).has_point(pos):
		open_map()
		return true
	return false


func zoom_reset_rect() -> Rect2:
	return Rect2(14.0, 92.0, 112.0, 48.0)


func handle_drag(delta: Vector2) -> void:
	if map_open:
		map_scroll -= delta.y


func _map_scale() -> float:
	return _map_view().size.x / Neighborhood.WORLD_W


func _tap_map(pos: Vector2) -> void:
	var view := _map_view()
	if view.has_point(pos):
		var scale := _map_scale()
		var world := Vector2((pos.x - view.position.x) / scale, (pos.y - view.position.y + map_scroll) / scale)
		var best := 60.0
		var found := -1
		for lot: LotScript in ctx.hood.lots:
			var kind: String = ctx.pins.get(lot.id, "")
			if kind in ACTIVE_KINDS or ctx.case_states.has(lot.id):
				var d := lot.center.distance_to(world)
				if d < best:
					best = d
					found = lot.id
		if found >= 0:
			ctx.set_objective(found)
	map_open = false


func _tap_gallery(pos: Vector2) -> bool:
	var panel := _map_panel()
	var camera = ctx.camera_ev
	var items: Array = camera.items()
	var pages := maxi(1, ceili(float(items.size()) / GALLERY_PAGE))
	var close := Rect2(panel.end.x - 130.0, panel.end.y - 76.0, 110.0, 56.0)
	if close.has_point(pos):
		gallery_open = false
		gallery_sel = -1
	elif gallery_sel >= 0 and gallery_sel < items.size():
		var item: Dictionary = items[gallery_sel]
		if _detail_button(panel, 0).has_point(pos):
			camera.set_best(int(item.house), int(item.index))
			ctx.evidence_changed.emit()
		elif _detail_button(panel, 1).has_point(pos):
			camera.delete_photo(int(item.house), int(item.index))
			ctx.evidence_changed.emit()
			gallery_sel = -1
		else:
			gallery_sel = -1
	elif Rect2(panel.position.x + 20.0, panel.end.y - 76.0, 110.0, 56.0).has_point(pos):
		gallery_page = maxi(0, gallery_page - 1)
	elif Rect2(panel.position.x + 140.0, panel.end.y - 76.0, 110.0, 56.0).has_point(pos):
		gallery_page = mini(pages - 1, gallery_page + 1)
	else:
		for k in GALLERY_PAGE:
			var idx := gallery_page * GALLERY_PAGE + k
			if idx < items.size() and _gallery_cell(k).has_point(pos):
				gallery_sel = idx
	return true


func _detail_button(panel: Rect2, which: int) -> Rect2:
	return Rect2(panel.position.x + 24.0 + which * 190.0, panel.end.y - 150.0, 176.0, 56.0)


# ---------------------------------------------------------------- main HUD

func _draw_ui() -> void:
	var w := size.x
	var h := size.y
	var font := ThemeDB.fallback_font
	var player = ctx.player
	# Clock / season chip.
	var clock := "%s · %s · %s" % [GameState.weekday_name(), GameState.date_text(), Weather.name_of(int(ctx.weather))]
	var clock_size := font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	DrawUtil.rr(self, Rect2(14.0, 14.0, clock_size.x + 24.0, 34.0), Color(0, 0, 0, 0.5), 10)
	draw_string(font, Vector2(26.0, 38.0), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffd36e"))
	# Next destination.
	next_rect = Rect2()
	var objective: int = ctx.objective
	if objective >= 0 and ctx.pins.get(objective, "") in ACTIVE_KINDS:
		var lot: LotScript = ctx.hood.lots[objective]
		var feet := roundi(player.position.distance_to(lot.driveway_mid()) * FEET_PER_PX)
		var text := "Next: %s · %d ft" % [lot.address, feet]
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		var box := Rect2(14.0, 54.0, minf(ts.x + 24.0, w - MINI_SIZE.x - 44.0), 30.0)
		next_rect = box.grow(6.0)
		DrawUtil.rr(self, box, Color(0, 0, 0, 0.5), 10)
		draw_string(font, box.position + Vector2(12.0, 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 20.0, 18, Color.WHITE)
	if absf(float(ctx.user_zoom) - 1.0) > 0.05 and not ctx.camera_ev.active:
		var zr := zoom_reset_rect()
		DrawUtil.rr(self, zr, Color(0, 0, 0, 0.5), 10)
		draw_string(font, zr.position + Vector2(0.0, 31.0), "RESET ZOOM", HORIZONTAL_ALIGNMENT_CENTER, zr.size.x, 16, Color.WHITE)
	if str(ctx.hint) != "":
		var hs := font.get_string_size(ctx.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		var hbox := Rect2((w - hs.x) * 0.5 - 16.0, h * 0.22, hs.x + 32.0, 46.0)
		DrawUtil.rr(self, hbox, Color(0.04, 0.08, 0.12, 0.78), 14)
		draw_string(font, hbox.position + Vector2(16.0, 31.0), ctx.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	# Virtual stick: fades with use and keeps out of the way.
	if ctx.dragging:
		var knob: Vector2 = ctx.anchor + (ctx.finger - ctx.anchor).limit_length(STICK_RANGE)
		var alpha := 0.25 + 0.35 * clampf(float(ctx.stick_hold), 0.0, 1.0)
		draw_arc(ctx.anchor, STICK_RANGE * 0.62, 0.0, TAU, 40, Color(1, 1, 1, alpha * 0.5), 3.0, true)
		DrawUtil.ellipse(self, knob, 26.0, 26.0, Color(1, 1, 1, alpha))
	elif not ctx.used and str(ctx.hint) == "" and not ctx.camera_ev.active and not map_open and not gallery_open:
		draw_string(font, Vector2(0.0, h * 0.72), "DRAG ANYWHERE TO WALK", HORIZONTAL_ALIGNMENT_CENTER, w, 24,
				Color(1, 1, 1, 0.85 + 0.15 * sin(float(ctx.time) * 3.0)))
	# Right column: camera, album, cart.
	var camera_c := Vector2(w - 66.0, h - 72.0)
	draw_circle(camera_c + Vector2(3.0, 5.0), 42.0, Color(0, 0, 0, 0.25))
	draw_circle(camera_c, 42.0, Color("f4ecd8"))
	DrawUtil.rr(self, Rect2(camera_c - Vector2(25.0, 17.0), Vector2(50.0, 36.0)), Color("273444"), 7)
	DrawUtil.rr(self, Rect2(camera_c + Vector2(-13.0, -24.0), Vector2(26.0, 10.0)), Color("273444"), 4)
	draw_circle(camera_c + Vector2(0.0, 1.0), 12.0, Color("71b9dc"))
	draw_circle(camera_c + Vector2(0.0, 1.0), 7.0, Color("182735"))
	for spec in [[172.0, "ALBUM"], [262.0, "CART"]]:
		var bc := Vector2(w - 66.0, h - float(spec[0]))
		var on: bool = spec[1] == "CART" and player.cart
		draw_circle(bc + Vector2(2.0, 4.0), 36.0, Color(0, 0, 0, 0.25))
		draw_circle(bc, 36.0, Color("7ee081") if on else Color("f4ecd8"))
		draw_string(font, bc + Vector2(-36.0, 6.0), str(spec[1]), HORIZONTAL_ALIGNMENT_CENTER, 72.0, 16, Color("273444"))
	var photo_count: int = ctx.camera_ev.photo_count()
	if photo_count > 0:
		draw_circle(Vector2(w - 36.0, h - 202.0), 11.0, Color("e0533d"))
		draw_string(font, Vector2(w - 48.0, h - 196.0), str(photo_count), HORIZONTAL_ALIGNMENT_CENTER, 24.0, 14, Color.WHITE)
	# Inspection prompt: address, status, then one clear button.
	prompt_rect = Rect2()
	var near: int = ctx.near
	if near >= 0 and not ctx.camera_ev.active:
		var lot: LotScript = ctx.hood.lots[near]
		var kind: String = ctx.pins.get(near, "")
		var spotted: bool = ctx.discoverable.has(near) and not ctx.pins.has(near)
		var active: bool = kind in ACTIVE_KINDS
		var status := "NO ACTIVE CASE"
		var label := ""
		if active:
			status = "REINSPECTION REQUIRED" if kind == "reinspect" else "COMPLAINT PENDING"
			label = "REINSPECT" if kind == "reinspect" else "INSPECT PROPERTY"
		elif spotted:
			status = "SOMETHING CATCHES YOUR EYE"
			label = "OPEN CASE"
		elif kind == "done":
			status = "INSPECTION COMPLETE"
		var caption := "%s · %s" % [lot.address, status]
		var cs := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		DrawUtil.rr(self, Rect2(16.0, h - 118.0, cs.x + 24.0, 34.0), Color(0, 0, 0, 0.55), 10)
		draw_string(font, Vector2(28.0, h - 94.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		if label != "":
			var ts2 := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
			prompt_rect = Rect2(16.0, h - 72.0, ts2.x + 40.0, 56.0)
			var pulse := 0.5 + 0.5 * sin(float(ctx.time) * 5.0)
			DrawUtil.rr(self, prompt_rect, (Color("ffd36e") if not spotted else Color("9bd0ff")).lerp(Color.WHITE, pulse * 0.3), 14)
			draw_string(font, prompt_rect.position + Vector2(20.0, 38.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("1c1b1f"))
	if float(ctx.photo_message_t) > 0.0:
		var pm: String = ctx.photo_message
		var photo_size := font.get_string_size(pm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		var photo_box := Rect2(camera_c.x - photo_size.x - 76.0, camera_c.y - 24.0, photo_size.x + 24.0, 48.0)
		DrawUtil.rr(self, photo_box, Color(0.04, 0.08, 0.12, 0.82), 12)
		draw_string(font, photo_box.position + Vector2(12.0, 32.0), pm, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)


# ---------------------------------------------------------------- camera

func _zoom_buttons() -> Dictionary:
	var frame: Rect2 = ctx.camera_ev.frame_rect(size)
	return {
		"minus": Rect2(frame.position.x, frame.end.y + 14.0, 76.0, 60.0),
		"plus": Rect2(frame.position.x + 88.0, frame.end.y + 14.0, 76.0, 60.0),
		"cancel": Rect2(frame.end.x - 76.0, frame.position.y - 70.0, 76.0, 54.0),
	}


func _draw_camera_frame() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.18))
	var frame: Rect2 = ctx.camera_ev.frame_rect(size)
	var bracket := Color("ffd36e")
	for corner in [frame.position, Vector2(frame.end.x, frame.position.y), Vector2(frame.position.x, frame.end.y), frame.end]:
		var sx := 1.0 if corner.x == frame.position.x else -1.0
		var sy := 1.0 if corner.y == frame.position.y else -1.0
		draw_line(corner, corner + Vector2(sx * 48.0, 0), bracket, 5.0, true)
		draw_line(corner, corner + Vector2(0, sy * 48.0), bracket, 5.0, true)
	var title: String = ctx.hood.lots[ctx.near].address if int(ctx.near) >= 0 else "EVIDENCE"
	draw_string(font, Vector2(0, frame.position.y - 28.0), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color.WHITE)
	var info: Dictionary = ctx.frame_info
	var quality: int = info.get("quality", 0)
	var meter_col := Color("e0533d") if quality < EvidenceCamera.USABLE_QUALITY else (Color("f2b632") if quality < 70 else Color("7ee081"))
	var meter := Rect2(frame.position.x + 190.0, frame.end.y + 30.0, frame.size.x - 190.0, 22.0)
	DrawUtil.rr(self, meter, Color(0, 0, 0, 0.5), 8)
	DrawUtil.rr(self, Rect2(meter.position, Vector2(meter.size.x * quality / 100.0, meter.size.y)), meter_col, 8)
	draw_string(font, meter.position + Vector2(0, -6), "PHOTO QUALITY %d%%" % quality, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# Never names the violation; it only says whether something worth recording is in frame.
	if bool(info.get("potential", false)):
		var tag := "Potential evidence detected"
		var tsz := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		var tag_box := Rect2((size.x - tsz.x) * 0.5 - 14.0, frame.position.y + 10.0, tsz.x + 28.0, 34.0)
		DrawUtil.rr(self, tag_box, Color(0.12, 0.45, 0.2, 0.85), 10)
		draw_string(font, tag_box.position + Vector2(14.0, 24.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	var buttons := _zoom_buttons()
	for btn_name in ["minus", "plus", "cancel"]:
		var r: Rect2 = buttons[btn_name]
		DrawUtil.rr(self, r, Color(0.04, 0.08, 0.12, 0.85), 12)
		var label := "−" if btn_name == "minus" else ("+" if btn_name == "plus" else "CANCEL")
		draw_string(font, r.position + Vector2(0, r.size.y * 0.66), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
				34 if btn_name != "cancel" else 18, Color.WHITE)
	draw_string(font, Vector2(frame.position.x, frame.end.y + 100.0), "ZOOM %.1fx · stand close, center the lot" % ctx.camera_ev.zoom,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.8))


# ---------------------------------------------------------------- maps
# Both maps draw the roads and lots straight from Neighborhood. Nothing is
# approximated, so they can never drift away from the actual streets.

func _draw_network(canvas: CanvasItem, to_map: Callable, scale: float, walk_col: Color, road_col: Color, min_width: float) -> void:
	var hood: Neighborhood = ctx.hood
	for pass_i in 2:
		var color := walk_col if pass_i == 0 else road_col
		for street in hood.streets:
			var extra: float = Neighborhood.WALK_W if pass_i == 0 else 0.0
			var width := maxf((street.half + extra) * 2.0 * scale, min_width)
			var pts := PackedVector2Array()
			for p in street.path:
				pts.append(to_map.call(p))
			canvas.draw_polyline(pts, color, width, true)
			for bulb in street.bulbs:
				canvas.draw_circle(to_map.call(bulb.center), maxf((Neighborhood.BULB_R + extra) * scale, min_width * 0.5), color)


func _draw_minimap() -> void:
	if ctx == null:
		return
	var rect := Rect2(Vector2.ZERO, MINI_SIZE)
	DrawUtil.rr(_mini, rect, Color(0.04, 0.08, 0.12, 0.62), 12)
	var player: Vector2 = ctx.player.position
	var scale := MINI_SIZE.x / MINI_WINDOW.x
	var origin := player - MINI_WINDOW * 0.5
	origin.x = clampf(origin.x, 0.0, Neighborhood.WORLD_W - MINI_WINDOW.x)
	# The road network only needs re-projecting when the window has moved noticeably.
	if _mini_origin.distance_to(origin) > 30.0 or _mini_roads.is_empty():
		_mini_origin = origin
		_mini_roads = _project_network(func(p: Vector2) -> Vector2: return (p - origin) * scale, scale, 2.0)
	var shift := (_mini_origin - origin) * scale
	for pass_i in 2:
		var color := Color("d7d9d5", 0.9) if pass_i == 0 else Color("414a56")
		for item in _mini_roads[pass_i]:
			if item.has("pts"):
				var pts := PackedVector2Array()
				for p in item.pts:
					pts.append(p + shift)
				_mini.draw_polyline(pts, color, item.width, true)
			else:
				_mini.draw_circle(item.c + shift, item.r, color)
	var to_map := func(p: Vector2) -> Vector2: return (p - origin) * scale
	for lot: LotScript in ctx.hood.lots:
		if absf(lot.center.y - player.y) > MINI_WINDOW.y * 0.6:
			continue
		var kind: String = ctx.pins.get(lot.id, "")
		var status: String = ctx.case_states.get(lot.id, "")
		if kind in ACTIVE_KINDS or status != "":
			var col := (Color("71b9dc") if kind == "reinspect" else Color("ffd36e")) if kind in ACTIVE_KINDS else Color("9aa4b2")
			_mini.draw_circle(to_map.call(lot.center), 3.0, col)
	var objective: int = ctx.objective
	if objective >= 0 and ctx.pins.get(objective, "") in ACTIVE_KINDS:
		var op: Vector2 = to_map.call(ctx.hood.lots[objective].center)
		_mini.draw_arc(op, 5.0 + 3.0 * (0.5 + 0.5 * sin(float(ctx.time) * 4.0)), 0.0, TAU, 16, Color("ffd36e"), 1.5)
	var me: Vector2 = to_map.call(player)
	_mini.draw_circle(me, 4.0, Color.WHITE)
	_mini.draw_circle(me, 7.0, Color(1, 1, 1, 0.35), false, 1.5)


## Road geometry projected once into map space: [[sidewalk items], [asphalt items]].
func _project_network(to_map: Callable, scale: float, min_width: float) -> Array:
	var hood: Neighborhood = ctx.hood
	var passes: Array = [[], []]
	for pass_i in 2:
		for street in hood.streets:
			var extra: float = Neighborhood.WALK_W if pass_i == 0 else 0.0
			var pts := PackedVector2Array()
			for p in street.path:
				pts.append(to_map.call(p))
			passes[pass_i].append({"pts": pts, "width": maxf((street.half + extra) * 2.0 * scale, min_width)})
			for bulb in street.bulbs:
				passes[pass_i].append({"c": to_map.call(bulb.center), "r": maxf((Neighborhood.BULB_R + extra) * scale, min_width * 0.5)})
	return passes


func _draw_map_chrome() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.08, 0.94))
	var panel := _map_panel()
	DrawUtil.rr(self, panel, Color("d9e2d0"), 22)
	draw_string(font, panel.position + Vector2(24.0, 45.0), "NEIGHBORHOOD", HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 26, Color("1d3340"))
	draw_string(font, panel.position + Vector2(24.0, 72.0), "Drag to scroll · tap a case to set it as your destination",
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 16, Color("435a62"))
	draw_string(font, panel.position + Vector2(24.0, panel.size.y - 30.0), "Tap empty map to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("435a62"))


func _draw_full_map() -> void:
	if ctx == null or not map_open:
		return
	var hood: Neighborhood = ctx.hood
	var view := _map_view()
	var scale := view.size.x / Neighborhood.WORLD_W
	map_scroll = clampf(map_scroll, 0.0, maxf(0.0, Neighborhood.WORLD_H * scale - view.size.y))
	var scroll := map_scroll
	var to_map := func(p: Vector2) -> Vector2: return p * scale - Vector2(0.0, scroll)
	var font := ThemeDB.fallback_font
	_map.draw_rect(Rect2(Vector2.ZERO, view.size), Color("79b66a"))
	for mark in hood.landmarks:
		var r: Rect2 = mark.rect
		var mr := Rect2(to_map.call(r.position), r.size * scale)
		var col: Color = {"park": Color("9bd68f"), "woods": Color("3c8a55"), "clubhouse": Color("d8c6a3"),
				"lake": Color("4aa9c7"), "pond": Color("4aa9c7")}.get(str(mark.type), Color.GRAY)
		if str(mark.type) in ["lake", "pond"]:
			DrawUtil.ellipse(_map, mr.get_center(), mr.size.x * 0.5, mr.size.y * 0.5, col)
		else:
			_map.draw_rect(mr, col)
	_draw_network(_map, to_map, scale, Color("d7d9d5"), Color("414a56"), 4.0)
	for street in hood.streets:
		var mid: Array = hood.sample(street, street.length * (0.5 if street.id != 0 else 0.3))
		var at: Vector2 = to_map.call(mid[0]) + Vector2(-60.0, -8.0 - street.half * scale)
		_map.draw_string(font, at, street.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("1d3340"))
	for lot: LotScript in hood.lots:
		var corners := PackedVector2Array()
		for p in lot.footprint():
			corners.append(to_map.call(p))
		_map.draw_colored_polygon(corners, (ctx.house_color(lot.id) as Color))
		var kind: String = ctx.pins.get(lot.id, "")
		var status: String = ctx.case_states.get(lot.id, "")
		var c: Vector2 = to_map.call(lot.center)
		if kind in ACTIVE_KINDS:
			_map.draw_circle(c, 14.0, Color("ffd36e", 0.45), false, 3.0)
		elif status != "":
			var tint: Color = {"warning": Color("f2c94c"), "hearing": Color("f2994a"), "fined": Color("eb5757"),
					"compliant": Color("6fcf97"), "disputed": Color("9b8cf0"), "reinspect": Color("f2c94c")}.get(status, Color("9aa4b2"))
			_map.draw_circle(c, 12.0, tint, false, 3.0)
		elif kind == "done":
			_map.draw_circle(c, 11.0, Color("50c878"), false, 3.0)
		if ctx.camera_ev.evidence.has(lot.id):
			_map.draw_circle(c + Vector2(10.0, -10.0), 4.0, Color("71b9dc"))
	var objective: int = ctx.objective
	if objective >= 0:
		var oc: Vector2 = to_map.call(hood.lots[objective].center)
		_map.draw_arc(oc, 18.0 + 4.0 * sin(float(ctx.time) * 4.0), 0.0, TAU, 24, Color("e0533d"), 3.0)
	var me: Vector2 = to_map.call(ctx.player.position)
	_map.draw_circle(me, 10.0, Color("ffd36e") if not ctx.player.cart else Color("7ee081"))
	_map.draw_circle(me, 15.0, Color("1d3340"), false, 3.0)


# ---------------------------------------------------------------- album

func _gallery_cell(k: int) -> Rect2:
	var panel := _map_panel()
	var cw := (panel.size.x - 72.0) * 0.5
	var ch := cw * 0.75 + 62.0
	return Rect2(panel.position.x + 24.0 + (k % 2) * (cw + 24.0), panel.position.y + 90.0 + (k / 2) * (ch + 14.0), cw, ch)


func _violation_label(house: int, id: String) -> String:
	for v in ctx.violations.get(house, []):
		if str(v.get("id", "")) == id:
			return str(v.get("label", id))
	return id


func _draw_gallery() -> void:
	var font := ThemeDB.fallback_font
	var camera = ctx.camera_ev
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.08, 0.94))
	var panel := _map_panel()
	DrawUtil.rr(self, panel, Color("d9e2d0"), 22)
	var items: Array = camera.items()
	var pages := maxi(1, ceili(float(items.size()) / GALLERY_PAGE))
	draw_string(font, panel.position + Vector2(24.0, 50.0), "EVIDENCE ALBUM · %d PHOTOS" % items.size(),
			HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 26, Color("1d3340"))
	if items.is_empty():
		draw_string(font, panel.position + Vector2(24.0, 140.0), "No photos yet. Stand near a lot with a complaint and use the camera.",
				HORIZONTAL_ALIGNMENT_LEFT, panel.size.x - 48.0, 20, Color("435a62"))
	if gallery_sel >= 0 and gallery_sel < items.size():
		var item: Dictionary = items[gallery_sel]
		var photo: Dictionary = item.photo
		var entry: Dictionary = item.entry
		var big := Rect2(panel.position + Vector2(24.0, 80.0), Vector2(panel.size.x - 48.0, (panel.size.x - 48.0) * 0.75))
		DrawUtil.rr(self, big, Color("1d3340"), 12)
		var tex: Texture2D = camera.thumb(str(photo.get("path", "")))
		if tex != null:
			draw_texture_rect(tex, big, false)
		var y := big.end.y + 34.0
		var lot: LotScript = ctx.hood.lots[int(item.house)]
		draw_string(font, Vector2(big.position.x, y), "%s · Day %d · %s" % [lot.address, int(photo.get("day", 0)), str(photo.get("time", "")).replace("T", " ")],
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 22, Color("1d3340"))
		var is_best := int(entry.get("best", -1)) == int(item.index)
		draw_string(font, Vector2(big.position.x, y + 30.0), "Quality %d%%%s" % [int(photo.get("quality", 0)), " · BEST PHOTO" if is_best else ""],
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 20, Color("2f9e57") if is_best else Color("435a62"))
		var labels: Array = []
		for id in photo.get("documented", []):
			labels.append(_violation_label(int(item.house), str(id)))
		draw_string(font, Vector2(big.position.x, y + 60.0), "Evidence recorded: %s" % (", ".join(labels) if not labels.is_empty() else "nothing clearly visible"),
				HORIZONTAL_ALIGNMENT_LEFT, big.size.x, 20, Color("435a62"))
		for which in 2:
			var br := _detail_button(panel, which)
			DrawUtil.rr(self, br, Color("1d3340") if which == 0 else Color("8c2f2a"), 12)
			draw_string(font, br.position + Vector2(0, 36.0), "SET AS BEST" if which == 0 else "DELETE", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 20, Color.WHITE)
	else:
		for k in GALLERY_PAGE:
			var idx := gallery_page * GALLERY_PAGE + k
			if idx >= items.size():
				break
			var cell := _gallery_cell(k)
			var item2: Dictionary = items[idx]
			var photo2: Dictionary = item2.photo
			var img_rect := Rect2(cell.position, Vector2(cell.size.x, cell.size.x * 0.75))
			DrawUtil.rr(self, img_rect, Color("1d3340"), 10)
			var tex2: Texture2D = camera.thumb(str(photo2.get("path", "")))
			if tex2 != null:
				draw_texture_rect(tex2, img_rect, false)
			var q := int(photo2.get("quality", 0))
			var lot2: LotScript = ctx.hood.lots[int(item2.house)]
			draw_string(font, cell.position + Vector2(0.0, img_rect.size.y + 22.0), lot2.address, HORIZONTAL_ALIGNMENT_LEFT, cell.size.x, 16, Color("1d3340"))
			draw_string(font, cell.position + Vector2(0.0, img_rect.size.y + 44.0),
					"Day %d · %d%% · %d noted" % [int(photo2.get("day", 0)), q, (photo2.get("documented", []) as Array).size()],
					HORIZONTAL_ALIGNMENT_LEFT, cell.size.x, 14, Color("2f9e57") if q >= 70 else Color("b3261e"))
	for spec in [[Rect2(panel.position.x + 20.0, panel.end.y - 76.0, 110.0, 56.0), "PREV"],
			[Rect2(panel.position.x + 140.0, panel.end.y - 76.0, 110.0, 56.0), "NEXT"],
			[Rect2(panel.end.x - 130.0, panel.end.y - 76.0, 110.0, 56.0), "CLOSE"]]:
		DrawUtil.rr(self, spec[0], Color("1d3340"), 12)
		draw_string(font, (spec[0] as Rect2).position + Vector2(0.0, 36.0), str(spec[1]), HORIZONTAL_ALIGNMENT_CENTER, 110.0, 20, Color.WHITE)
	draw_string(font, Vector2(panel.position.x + 270.0, panel.end.y - 40.0), "%d / %d" % [gallery_page + 1, pages], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("1d3340"))
