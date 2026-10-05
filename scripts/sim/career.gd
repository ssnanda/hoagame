extends RefCounted
## Career profile: communities, unlocks and achievements. Kept in its own file
## (user://career.cfg) so it survives game resets and save-format changes.
## Progress is about surviving harder communities, not XP.

const PATH := "user://career.cfg"
const TERM_MEETINGS := 3          ## annual meetings survived = one completed term

var communities: Array = []
var achievements: Array = []
var terms_completed := 0
var reputation := 0
var selected := "oak_meadow"
var earned: Dictionary = {}       ## achievement id -> true
var stats: Dictionary = {"photos": 0, "fines": 0}


func load_all() -> void:
	communities = _read("res://data/communities.json")
	achievements = _read("res://data/achievements.json")
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	terms_completed = int(cfg.get_value("career", "terms", 0))
	reputation = int(cfg.get_value("career", "reputation", 0))
	selected = str(cfg.get_value("career", "selected", "oak_meadow"))
	earned = (cfg.get_value("career", "earned", {}) as Dictionary).duplicate()
	stats = (cfg.get_value("career", "stats", stats) as Dictionary).duplicate()
	if not is_unlocked(selected):
		selected = "oak_meadow"


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("career", "terms", terms_completed)
	cfg.set_value("career", "reputation", reputation)
	cfg.set_value("career", "selected", selected)
	cfg.set_value("career", "earned", earned)
	cfg.set_value("career", "stats", stats)
	cfg.save(PATH)


func _read(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func community(id: String) -> Dictionary:
	for c: Dictionary in communities:
		if str(c.id) == id:
			return c
	return communities[0] if not communities.is_empty() else {}


func is_unlocked(id: String) -> bool:
	return terms_completed >= int(community(id).get("unlock", {}).get("terms", 0))


func current() -> Dictionary:
	return community(selected)


## Rating 0-100 for a finished term from the end-of-term stats.
func record_term(power: int, happiness: int, budget: int, support: int, legal: int) -> int:
	var rating := clampi(int((power + happiness + budget + support) / 4.0 - legal * 0.2), 0, 100)
	terms_completed += 1
	reputation += rating
	save()
	return rating


## Returns true the first time an achievement is earned.
func award(id: String) -> bool:
	if earned.has(id):
		return false
	earned[id] = true
	save()
	return true


func achievement_name(id: String) -> String:
	for a: Dictionary in achievements:
		if str(a.id) == id:
			return str(a.name)
	return id


func bump(stat: String, by := 1) -> int:
	stats[stat] = int(stats.get(stat, 0)) + by
	return int(stats[stat])
