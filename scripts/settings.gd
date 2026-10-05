extends Node
## Autoload: player preferences. Stored apart from the run so resetting a game
## never wipes them, and vice versa.

const PATH := "user://settings.cfg"

var sound := true
var music := true
var haptics := true
var music_volume := 0.8
var sfx_volume := 0.8
var text_scale := 1.0        ## multiplier for panel text (accessibility)
var sensitivity := 1.0       ## stick range multiplier: lower = needs less thumb travel
var reduce_motion := false
var zoom_out_walking := true  ## ease the camera out a little while walking
var tutorial_done := false
var pending_action := ""     ## "new" or "continue": survives one scene reload (community layout change)
var difficulty := 1          ## 0 relaxed, 1 standard, 2 hard (applies to new terms)


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sound = bool(cfg.get_value("audio", "sound", true))
	music = bool(cfg.get_value("audio", "music", true))
	haptics = bool(cfg.get_value("controls", "haptics", true))
	music_volume = float(cfg.get_value("audio", "music_volume", 0.8))
	sfx_volume = float(cfg.get_value("audio", "sfx_volume", 0.8))
	text_scale = float(cfg.get_value("display", "text_scale", 1.0))
	sensitivity = float(cfg.get_value("controls", "sensitivity", 1.0))
	reduce_motion = bool(cfg.get_value("display", "reduce_motion", false))
	zoom_out_walking = bool(cfg.get_value("display", "zoom_out_walking", true))
	tutorial_done = bool(cfg.get_value("progress", "tutorial_done", false))
	difficulty = int(cfg.get_value("progress", "difficulty", 1))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sound", sound)
	cfg.set_value("audio", "music", music)
	cfg.set_value("controls", "haptics", haptics)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("display", "text_scale", text_scale)
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("display", "reduce_motion", reduce_motion)
	cfg.set_value("display", "zoom_out_walking", zoom_out_walking)
	cfg.set_value("progress", "tutorial_done", tutorial_done)
	cfg.set_value("progress", "difficulty", difficulty)
	cfg.save(PATH)


## Subtle phone haptic. A no-op when disabled or unsupported.
func haptic(ms: int = 20) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
