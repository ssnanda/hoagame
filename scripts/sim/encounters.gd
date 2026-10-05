extends RefCounted
## Data-driven cinematic encounters (data/encounters.json). Pure rules: this file picks
## an encounter and applies its outcome; encounter_panel.gd plays it. Adding a scene is
## adding a JSON entry — no code.
##
## Entry fields: id, trigger[], rarity, cooldown_days, tone, pose, props[], lines[],
## choices[], footer, and `when` filters: traits_any[], min_rel, max_rel, season[],
## min_unfair (selective-enforcement pressure from critics vs friends).

const Residents := preload("res://scripts/sim/residents.gd")

const RARITY_WEIGHT := {"common": 60.0, "uncommon": 25.0, "rare": 8.0, "very_rare": 0.5}
const BASE_CHANCE := 0.38       ## chance a ruling produces any encounter at all
const TRIGGER_CHANCE := {"visit": 0.2, "photo": 0.14}   ## approaches trigger less often than rulings
const SHOWCASE_ID := "showcase_first"   ## the scripted first encounter every new player sees

var catalog: Array = []
var last_seen: Dictionary = {}  ## id -> day it last played (persisted by the sim)
var force_next := ""            ## QA / video-capture hook: play this encounter id next (ignored in normal play)
var _seed_rng: RandomNumberGenerator


func load_data() -> void:
	catalog.clear()
	var file := FileAccess.open("res://data/encounters.json", FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		catalog = parsed


## `ctx`: {trigger, day, season, property, fairness_gap}. Returns {} when nothing plays.
func pick(ctx: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	if catalog.is_empty():
		return {}
	if force_next != "":
		for entry: Dictionary in catalog:
			if str(entry.get("id", "")) == force_next:
				force_next = ""
				return entry.duplicate(true)
		force_next = ""
	# The first real ruling always plays the polished showcase; random scenes wait until it has.
	if not last_seen.has(SHOWCASE_ID):
		for entry: Dictionary in catalog:
			if str(entry.get("id", "")) == SHOWCASE_ID and str(ctx.get("trigger", "")) in (entry.get("trigger", []) as Array):
				return entry.duplicate(true)
		return {}
	var chance: float = float(TRIGGER_CHANCE.get(str(ctx.get("trigger", "")), BASE_CHANCE))
	var property: Dictionary = ctx.get("property", {})
	# Hostile or litigious households come outside more often.
	if int(property.get("relationship", 0)) <= -20 or Residents.has_trait(property, "litigious"):
		chance += 0.15
	if rng.randf() > chance:
		return {}
	var pool: Array = []
	var total := 0.0
	for entry: Dictionary in catalog:
		if not _eligible(entry, ctx):
			continue
		var weight: float = float(RARITY_WEIGHT.get(str(entry.get("rarity", "common")), 10.0))
		# Entries whose filters matched specifically are a little more likely than generic ones.
		if entry.has("when"):
			weight *= 1.4
		pool.append([entry, weight])
		total += weight
	if pool.is_empty():
		return {}
	var roll := rng.randf() * total
	for item in pool:
		roll -= float(item[1])
		if roll <= 0.0:
			return (item[0] as Dictionary).duplicate(true)
	return (pool[0][0] as Dictionary).duplicate(true)


func _eligible(entry: Dictionary, ctx: Dictionary) -> bool:
	if bool(entry.get("showcase", false)):
		return false      # only ever played through the scripted path
	if not str(ctx.get("trigger", "")) in (entry.get("trigger", []) as Array):
		return false
	var cooldown := int(entry.get("cooldown_days", 3))
	if last_seen.has(str(entry.id)) and int(ctx.day) - int(last_seen[str(entry.id)]) < cooldown:
		return false
	var when: Dictionary = entry.get("when", {})
	var property: Dictionary = ctx.get("property", {})
	if when.has("traits_any"):
		var ok := false
		for t in when.traits_any:
			ok = ok or Residents.has_trait(property, str(t))
		if not ok:
			return false
	var rel := int(property.get("relationship", 0))
	if when.has("min_rel") and rel < int(when.min_rel):
		return false
	if when.has("max_rel") and rel > int(when.max_rel):
		return false
	if when.has("season") and not int(ctx.get("season", 0)) in (when.season as Array):
		return false
	if when.has("cited_any"):
		var hit := false
		for id in ctx.get("cited", []):
			hit = hit or str(id) in (when.cited_any as Array)
		if not hit:
			return false
	if when.get("needs_favored", false) and str(ctx.get("favored", "")) == "":
		return false
	if when.has("min_unfair"):
		var group := Residents.group(property)
		if not group in ["critic", "legal"] or float(ctx.get("fairness_gap", 0.0)) <= 0.2:
			return false
	return true


func mark_played(id: String, day: int) -> void:
	last_seen[id] = day


## Replaces {owner} / {address} in a line of text.
static func fill(text: String, owner: String, address: String, tokens: Dictionary = {}) -> String:
	var out := text.replace("{owner}", owner).replace("{address}", address)
	for key in tokens:
		out = out.replace("{%s}" % str(key), str(tokens[key]))
	return out
