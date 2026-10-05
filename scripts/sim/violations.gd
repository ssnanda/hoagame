extends RefCounted
## Data-driven violation catalog (data/violations.json) and complaint generation.
## Everything about what a violation is lives in the data file, not in code.

const PATH := "res://data/violations.json"

## Who can file a complaint, how reliable they are, and the label shown to the player.
const SOURCES := {
	"resident": {"label": "Resident", "reliability": 0.74},
	"chronic": {"label": "Resident (frequent filer)", "reliability": 0.5},
	"board": {"label": "Board member", "reliability": 0.8},
	"management": {"label": "Wozig management inspection", "reliability": 0.93},
	"anonymous": {"label": "Anonymous submission", "reliability": 0.55},
	"security": {"label": "Security patrol", "reliability": 0.86},
	"arc": {"label": "Architectural committee", "reliability": 0.88},
	"sweep": {"label": "Routine compliance sweep", "reliability": 0.9},
	"player": {"label": "Your own observation", "reliability": 1.0},
}

var catalog: Array = []
var _by_id: Dictionary = {}


func load_data() -> void:
	catalog.clear()
	_by_id.clear()
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("Missing %s" % PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		catalog = parsed
		for item in catalog:
			_by_id[str(item.id)] = item


func get_def(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Violations that can plausibly occur this season (no tall grass under snow, etc.).
func available(season: int, weekend: bool) -> Array:
	var pool: Array = []
	for item in catalog:
		var allowed := false
		for s in item.get("seasons", [0, 1, 2, 3]):
			allowed = allowed or int(s) == season   # JSON numbers load as floats
		if not allowed:
			continue
		pool.append(item)
		# Seasonal tendencies make the neighborhood feel like it has a calendar.
		if (season == 1 and str(item.id) in ["tall_grass", "hoop", "short_rental", "noise"]) \
				or (season >= 2 and str(item.id) in ["decorations", "trash"]) \
				or (weekend and str(item.id) in ["noise", "lawn_parking", "short_rental", "street_parking"]):
			pool.append(item)
	return pool


## One allegation. `reliability` is the chance the claim is true. Borderline cases
## are real but marginal, and need judgment.
func make_allegation(def: Dictionary, reliability: float, rng: RandomNumberGenerator, force_actual := -1) -> Dictionary:
	var roll := rng.randf()
	var actual := roll < reliability
	if force_actual == 1:
		actual = true
	elif force_actual == 0:
		actual = false
	var borderline := actual and rng.randf() < 0.22
	var complaints: Array = def.get("complaints", ["A complaint was filed."])
	var hints: Array = def.get("false_hints", ["Nothing found."])
	return {
		"id": str(def.id),
		"label": str(def.name),
		"object": _pick_object(def, rng),
		"category": str(def.get("category", "")),
		"severity": int(def.get("severity", 1)),
		"actual": actual,
		"borderline": borderline,
		"documented": false,
		"complaint": str(complaints[rng.randi() % complaints.size()]),
		"hint": str(hints[rng.randi() % hints.size()]),
		"borderline_note": str(def.get("borderline_note", "")),
		"cure_days": int(def.get("cure_days", 2)),
	}


## Some violations have visual variants (a hedge, a branch, bins...). The data lists them.
func _pick_object(def: Dictionary, rng: RandomNumberGenerator) -> String:
	var variants: Array = def.get("objects", [])
	if variants.is_empty():
		return str(def.get("object", ""))
	return str(variants[rng.randi() % variants.size()])


func fine_amount(id: String, repeat_count: int) -> int:
	var def := get_def(id)
	var range_: Array = def.get("fine", [25, 100])
	var base := int(range_[0]) + (int(range_[1]) - int(range_[0])) * mini(repeat_count, 3) / 3
	return base


func source_label(source: String) -> String:
	return str(SOURCES.get(source, SOURCES.resident).label)


func source_reliability(source: String) -> float:
	return float(SOURCES.get(source, SOURCES.resident).reliability)
