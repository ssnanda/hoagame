extends Node
## Autoload: player preferences. Stored apart from the run so resetting a game
## never wipes them, and vice versa.

const PATH := "user://settings.cfg"

var sound := true
var music := true
var haptics := true
var sensitivity := 1.0       ## stick range multiplier: lower = needs less thumb travel
var reduce_motion := false
var tutorial_done := false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sound = bool(cfg.get_value("audio", "sound", true))
	music = bool(cfg.get_value("audio", "music", true))
	haptics = bool(cfg.get_value("controls", "haptics", true))
	sensitivity = float(cfg.get_value("controls", "sensitivity", 1.0))
	reduce_motion = bool(cfg.get_value("display", "reduce_motion", false))
	tutorial_done = bool(cfg.get_value("progress", "tutorial_done", false))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sound", sound)
	cfg.set_value("audio", "music", music)
	cfg.set_value("controls", "haptics", haptics)
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("display", "reduce_motion", reduce_motion)
	cfg.set_value("progress", "tutorial_done", tutorial_done)
	cfg.save(PATH)


## Subtle phone haptic. A no-op when disabled or unsupported.
func haptic(ms: int = 20) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
