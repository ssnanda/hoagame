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


func _ready() -> void:
	_load_cards()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("score", "best", 0))
	new_game()


func new_game() -> void:
	for key in STAT_KEYS:
		stats[key] = START_VALUE
	day = 1
	score = 0
	streak = 0
	_refill_deck()
	stats_changed.emit()


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
