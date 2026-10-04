extends Node
## Autoload: stats, deck, and win/lose rules. No UI here.

signal stats_changed
signal game_over(reason: String)

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
var cards: Array = []
var deck: Array = []


func _ready() -> void:
	_load_cards()
	new_game()


func new_game() -> void:
	for key in STAT_KEYS:
		stats[key] = START_VALUE
	day = 1
	_refill_deck()
	stats_changed.emit()


func next_card() -> Dictionary:
	if deck.is_empty():
		_refill_deck()
	return deck.pop_back()


## side is "left" or "right".
func choose(card: Dictionary, side: String) -> void:
	var effects: Dictionary = card.get(side, {}).get("effects", {})
	for key in effects:
		if stats.has(key):
			stats[key] += int(effects[key])
	day += 1
	stats_changed.emit()
	var reason := _check_end()
	if reason != "":
		game_over.emit(reason)


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
