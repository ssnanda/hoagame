extends Node
## Autoload: stats, deck, and win/lose rules. No UI here.

signal stats_changed
signal game_over(reason: String)

const SAVE_PATH := "user://hoagame.cfg"

const STAT_KEYS := ["budget", "happiness", "power"]
const START_VALUE := 50
const END_MESSAGES := {
	"budget_low": "The treasury is empty. The board voted to 'restructure' you.",
	"budget_high": "You hoarded so much cash the IRS wants a word.",
	"happiness_low": "Residents stormed the clubhouse with pool noodles.",
	"happiness_high": "Everyone loves you. You've been elected mayor and must leave the HOA.",
	"power_low": "Impeached at the annual meeting. Minutes were not kept.",
	"power_high": "Tyrant! The neighbors formed a rival HOA.",
}

var stats: Dictionary = {}
var day := 1
var score := 0
var best := 0
var streak := 0
var cards: Array = []
var deck: Array = []
var has_saved_run := false
var _saved_world: Dictionary = {}


func _ready() -> void:
	_load_cards()
	_load_save()
	if not has_saved_run:
		new_game()


func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("score", "best", 0))
		has_saved_run = bool(cfg.get_value("run", "active", false))
		if has_saved_run:
			day = int(cfg.get_value("run", "day", 1))
			score = int(cfg.get_value("run", "score", 0))
			streak = int(cfg.get_value("run", "streak", 0))
			stats = cfg.get_value("run", "stats", {}).duplicate(true)
			deck = cfg.get_value("run", "deck", []).duplicate(true)
			_saved_world = cfg.get_value("run", "world", {}).duplicate(true)
			if stats.is_empty():
				has_saved_run = false


func new_game() -> void:
	for key in STAT_KEYS:
		stats[key] = START_VALUE
	day = 1
	score = 0
	streak = 0
	_refill_deck()
	stats_changed.emit()


func save_run(world: Dictionary) -> void:
	_save_best()
	has_saved_run = true
	_saved_world = world.duplicate(true)
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("score", "best", best)
	cfg.set_value("run", "active", true)
	cfg.set_value("run", "day", day)
	cfg.set_value("run", "score", score)
	cfg.set_value("run", "streak", streak)
	cfg.set_value("run", "stats", stats.duplicate(true))
	cfg.set_value("run", "deck", deck.duplicate(true))
	cfg.set_value("run", "world", _saved_world)
	cfg.save(SAVE_PATH)


func saved_world() -> Dictionary:
	return _saved_world.duplicate(true)


func clear_run() -> void:
	has_saved_run = false
	_saved_world = {}
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("score", "best", best)
	cfg.set_value("run", "active", false)
	cfg.save(SAVE_PATH)


func next_card() -> Dictionary:
	if deck.is_empty():
		_refill_deck()
	return deck.pop_back()


## Card decision: side is "left" or "right". Scores a flat 25.
func choose(card: Dictionary, side: String) -> void:
	add_score(25)
	apply_effects(card.get(side, {}).get("effects", {}))


func apply_effects(effects: Dictionary) -> void:
	for key in effects:
		if stats.has(key):
			stats[key] += int(effects[key])
	stats_changed.emit()
	var reason := _check_end()
	if reason != "":
		_save_best()
		clear_run()
		game_over.emit(reason)


## `correct`: true extends the streak (and multiplies points), false resets it.
## Returns the points actually awarded.
func add_score(points: int, correct = null) -> int:
	var gained := points
	if correct == true:
		streak += 1
		gained = roundi(points * (1.0 + 0.25 * mini(streak - 1, 4)))
	elif correct == false:
		streak = 0
	score = maxi(0, score + gained)
	stats_changed.emit()
	return gained


## Bonuses for finishing a day. Does not advance the day.
func end_day() -> Dictionary:
	var balanced := 0
	for key in STAT_KEYS:
		if stats[key] >= 30 and stats[key] <= 70:
			balanced += 1
	var result := {"day_bonus": 50 + 10 * day, "balance_bonus": 15 * balanced}
	add_score(result.day_bonus + result.balance_bonus)
	_save_best()
	return result


func next_day() -> void:
	day += 1
	stats_changed.emit()


## Ends the run from outside the stat rules (e.g. a lost election).
func force_end(reason: String) -> void:
	_save_best()
	clear_run()
	game_over.emit(reason)


## 0 spring, 1 summer, 2 fall, 3 winter; two weeks each.
func season() -> int:
	return ((day - 1) / 14) % 4


func season_name() -> String:
	return ["SPRING", "SUMMER", "FALL", "WINTER"][season()]


## 0 = Monday … 6 = Sunday.
func weekday() -> int:
	return (day - 1) % 7


func weekday_name() -> String:
	return ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][weekday()]


func is_weekend() -> bool:
	return weekday() >= 5


func _save_best() -> void:
	if score <= best:
		return
	best = score
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best)
	cfg.save(SAVE_PATH)


func _check_end() -> String:
	for key in STAT_KEYS:
		if stats[key] <= 0:
			return END_MESSAGES[key + "_low"]
		if stats[key] >= 100:
			return END_MESSAGES[key + "_high"]
	return ""


func _refill_deck() -> void:
	deck = cards.duplicate()
	deck.shuffle()


func _load_cards() -> void:
	var file := FileAccess.open("res://data/cards.json", FileAccess.READ)
	if file == null:
		push_error("Missing res://data/cards.json")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		cards = parsed
	else:
		push_error("cards.json must be a JSON array")
