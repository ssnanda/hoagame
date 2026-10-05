extends RefCounted
## Pinch / magnify / wheel zoom for the street camera. Pure input state: the street
## controller feeds it events and reads `target`; it never touches the scene.

const ZOOM_MIN := 0.6        ## neighborhood overview ...
const ZOOM_MAX := 1.7        ## ... to close property inspection

var target := 1.0            ## where the zoom is heading (1.0 = default)
var pinching_ms := 0         ## last time two fingers were down; used to swallow the release tap

var _touches: Dictionary = {}
var _start_dist := 0.0
var _start_zoom := 1.0


func clear() -> void:
	_touches.clear()
	_start_dist = 0.0


func pinch_active() -> bool:
	return _touches.size() >= 2


## Returns true when a second finger just landed (the caller cancels its walk gesture).
func handle(event: InputEvent, inside: bool) -> bool:
	var began := false
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			_start_dist = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
			_start_zoom = target
			pinching_ms = Time.get_ticks_msec()
			began = true
		elif _touches.size() < 2:
			_start_dist = 0.0
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() == 2 and _start_dist > 0.0:
			var pts: Array = _touches.values()
			target = clampf(_start_zoom * (pts[0] as Vector2).distance_to(pts[1]) / _start_dist, ZOOM_MIN, ZOOM_MAX)
			pinching_ms = Time.get_ticks_msec()
	elif event is InputEventMagnifyGesture:
		target = clampf(target * event.factor, ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventMouseButton and event.pressed and inside:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target = clampf(target * 1.1, ZOOM_MIN, ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target = clampf(target / 1.1, ZOOM_MIN, ZOOM_MAX)
	return began


func reset() -> void:
	target = 1.0
