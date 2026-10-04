extends RefCounted
## Evidence photography: framing quality, what a shot documents, and the album.
## Screenshot capture itself needs the scene tree, so the street controller does that.

const LotScript := preload("res://scripts/world/lot.gd")

const USABLE_QUALITY := 40
const ZOOM_MIN := 1.0
const ZOOM_MAX := 2.4
const MAX_PHOTOS := 6

var active := false
var zoom := 1.4
## house id -> {address, category, photos: [{path, time, quality, documented, key}], best, quality, documented, shots}
var evidence: Dictionary = {}
var _thumbs: Dictionary = {}


func frame_rect(view_size: Vector2) -> Rect2:
	return Rect2(view_size.x * 0.12, view_size.y * 0.2, view_size.x * 0.76, view_size.y * 0.56)


## Scores the current framing of `lot`. `to_screen` maps world points to screen points;
## `obstructors` are trees as Vector3(x, y, radius). Violation ids are only returned
## for the photo record. The HUD only ever shows `potential`, never what it is.
func evaluate(lot: LotScript, player: Vector2, to_screen: Callable, view_size: Vector2,
		dusk: float, entries: Array, obstructors: Array) -> Dictionary:
	if lot == null:
		return {"quality": 0, "documented": [], "potential": false}
	var frame := frame_rect(view_size)
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for corner in lot.footprint():
		var sp: Vector2 = to_screen.call(corner)
		min_p = Vector2(minf(min_p.x, sp.x), minf(min_p.y, sp.y))
		max_p = Vector2(maxf(max_p.x, sp.x), maxf(max_p.y, sp.y))
	var house := Rect2(min_p, max_p - min_p)
	var coverage := 0.0
	if house.get_area() > 0.0:
		coverage = house.intersection(frame).get_area() / house.get_area()
	var dist := player.distance_to(lot.center)
	var dist_factor := clampf(1.0 - (dist - 70.0) / 200.0, 0.15, 1.0)
	var zoom_factor := 1.0 if zoom >= 1.2 and zoom <= 2.0 else 0.6
	var blocked := 0.0
	for tree: Vector3 in obstructors:
		var tp: Vector2 = to_screen.call(Vector2(tree.x, tree.y))
		if house.grow(tree.z * 0.5).has_point(tp):
			blocked += 0.08
	blocked = minf(blocked, 0.25)
	var quality := (0.40 * coverage + 0.25 * dist_factor + 0.15 * zoom_factor + 0.20 * (1.0 - blocked / 0.25)) \
			* (1.0 - 0.25 * dusk) * 100.0
	var documented: Array = []
	if coverage >= 0.35 and dist_factor > 0.3:
		for entry: Dictionary in entries:
			if frame.has_point(to_screen.call(entry.pos)):
				documented.append(str(entry.id))
	return {"quality": roundi(quality), "documented": documented, "potential": not documented.is_empty()}


func shot_key(player: Vector2) -> String:
	return "%d:%d:%d" % [roundi(player.x / 45.0), roundi(player.y / 45.0), roundi(zoom * 3.0)]


func is_duplicate(house: int, key: String) -> bool:
	for photo in evidence.get(house, {}).get("photos", []):
		if str(photo.get("key", "")) == key:
			return true
	return false


## Stores a photo and refreshes the aggregate fields the case file reads.
## Returns {newly: violation ids documented for the first time, improved: new best}.
func add_photo(house: int, address: String, category: String, photo: Dictionary) -> Dictionary:
	var entry: Dictionary = evidence.get(house, {"address": address, "category": category, "photos": [], "best": -1}).duplicate(true)
	var photos: Array = entry.photos
	var before: Array = _union(photos)
	photos.append(photo)
	if photos.size() > MAX_PHOTOS:
		# Drop the weakest photo, never the best.
		var worst := 0
		for i in photos.size():
			if int(photos[i].quality) < int(photos[worst].quality) and i != int(entry.best):
				worst = i
		photos.remove_at(worst)
	entry.photos = photos
	var improved := _refresh(entry, int(photo.quality))
	evidence[house] = entry
	var newly: Array = []
	for id in entry.documented:
		if not id in before:
			newly.append(id)
	return {"newly": newly, "improved": improved}


func delete_photo(house: int, index: int) -> void:
	if not evidence.has(house):
		return
	var entry: Dictionary = evidence[house].duplicate(true)
	var photos: Array = entry.photos
	if index < 0 or index >= photos.size():
		return
	photos.remove_at(index)
	if photos.is_empty():
		evidence.erase(house)
		return
	entry.best = -1
	_refresh(entry, 0)
	evidence[house] = entry


func set_best(house: int, index: int) -> void:
	if evidence.has(house) and index >= 0 and index < evidence[house].photos.size():
		var entry: Dictionary = evidence[house].duplicate(true)
		entry.best = index
		_refresh(entry, 0, true)
		evidence[house] = entry


func _refresh(entry: Dictionary, newest_quality: int, pinned := false) -> bool:
	var photos: Array = entry.photos
	var best_index := int(entry.get("best", -1))
	var improved := false
	if not pinned or best_index < 0 or best_index >= photos.size():
		var previous_best := -1 if best_index < 0 or best_index >= photos.size() else int(photos[best_index].quality)
		best_index = 0
		for i in photos.size():
			if int(photos[i].quality) >= int(photos[best_index].quality):
				best_index = i
		improved = int(photos[best_index].quality) > previous_best
	entry.best = best_index
	entry.quality = int(photos[best_index].quality)
	entry.documented = _union(photos)
	entry.shots = photos.size()
	# Aggregate path/time mirror the best photo for older readers of the save.
	entry.path = str(photos[best_index].path)
	entry.time = str(photos[best_index].time)
	return improved


func _union(photos: Array) -> Array:
	var ids: Array = []
	for photo in photos:
		for id in photo.get("documented", []):
			if not id in ids:
				ids.append(id)
	return ids


func photo_count() -> int:
	var n := 0
	for house in evidence:
		n += (evidence[house].photos as Array).size()
	return n


## Flat album, newest first: {house, index, photo, entry}.
func items() -> Array:
	var list: Array = []
	for house in evidence:
		var entry: Dictionary = evidence[house]
		for i in entry.photos.size():
			list.append({"house": int(house), "index": i, "photo": entry.photos[i], "entry": entry})
	list.sort_custom(func(a, b): return str(a.photo.get("time", "")) > str(b.photo.get("time", "")))
	return list


func thumb(path: String) -> Texture2D:
	if _thumbs.has(path):
		return _thumbs[path]
	var tex: Texture2D = null
	var image := Image.load_from_file(path)
	if image != null and not image.is_empty():
		tex = ImageTexture.create_from_image(image)
	_thumbs[path] = tex
	return tex


## Accepts saves from before multi-photo albums (single path per property).
func load_saved(saved: Dictionary) -> void:
	evidence = {}
	for house in saved:
		var entry: Dictionary = (saved[house] as Dictionary).duplicate(true)
		if not entry.has("photos"):
			entry.photos = [{"path": str(entry.get("path", "")), "time": str(entry.get("time", "")),
					"quality": int(entry.get("quality", 0)), "documented": entry.get("documented", []), "key": ""}]
			entry.best = 0
		evidence[int(house)] = entry
		_refresh(evidence[int(house)], 0, true)
