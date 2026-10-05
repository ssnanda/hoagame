extends "res://tools/video/video_lib.gd"
## VIDEO 07: cinematic comedy back to back with the CURRENT art. The first scene is the real guaranteed first
## encounter. The others are queued with the QA hook (Encounters.force_next) and play through the real
## main._play_encounter() path (camera push, HUD fade, panel, outcome, return). Between scenes the screen dips
## to black while the player is moved to another house (disclosed: this clip uses setup teleports between
## scenes; it is a visual showcase, not a navigation test). Seed 7077.

const SCENES := [
	["showcase_first", "Explain the complaint"],     # door, argument, sprinklers
	["filming", "Stay professional"],                # side entrance, phone
	["dog_clipboard", "Offer a treat"],              # garage, dog
	["eccentric_gnomes", "Ask for a plan"],          # side entrance, gnome wizard
	["slapstick_chase", "Get up with dignity"],      # rare: dog + mud
	["police_misunderstanding", "Explain calmly"],   # rare: police
	["ambulance_misread", "Offer a ride to the clubhouse"],  # very rare: ambulance + blanket
	["slapstick_car_bump", "Insist you're fine"],    # very rare: car, blanket, dog
]
var houses: Array = []


func _setup() -> void:
	var spawn: Vector2 = street.spawn_point()
	var lots: Array = []
	for lot in hood.lots:
		if lot.kind == "standard" and lot.side != 0:
			lots.append([lot.id, spawn.distance_to(lot.inspect_anchor())])
	lots.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	for k in SCENES.size():
		houses.append(int(lots[k][0]))
	place_player(hood.lots[houses[0]].inspect_anchor())


func _scene(k: int) -> void:
	var id: String = SCENES[k][0]
	var house: int = houses[k]
	if k > 0:
		var fade := await fade_black(0.5)
		place_player(hood.lots[house].inspect_anchor())
		await wait(0.5)
		await unfade(fade, 0.5)
	await wait(1.6)
	if id != "showcase_first":
		main.sim.encounters.force_next = id
	main.call_deferred("_play_encounter", house, "warning")     # the real transition; finishes when the panel does
	await play_panel(str(SCENES[k][1]), 1.4)
	await wait(1.0)


func _ready() -> void:
	await boot_hidden(7077, false, "VIDEO 07", "CINEMATIC COMEDY SHOWCASE", _setup)
	await wait(1.5)
	for k in SCENES.size():
		await _scene(k)
	await finish()
