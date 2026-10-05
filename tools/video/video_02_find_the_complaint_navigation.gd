extends "res://tools/video/video_lib.gd"
## VIDEO 02: finding a complaint. The selected complaint starts off screen; the viewer sees the Next chip,
## edge arrow, distance, minimap, the player walking there, the marker, the arrival cue, then a second
## assignment selected with the Next chip (chip, arrow, minimap and marker all change together).
## Seed 2024. Setup (hidden behind the title card): pick two far complaints. No teleport while recording.

var far1 := -1
var far2 := -1


func _setup() -> void:
	var spawn: Vector2 = street.spawn_point()
	var cands: Array = []
	for h in main.sim.assignments:
		if str(main.sim.assignments[h].kind) == "reinspect":
			continue
		var d: float = spawn.distance_to(hood.lots[int(h)].inspect_anchor())
		cands.append([int(h), d])
	cands.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	# A complaint roughly 1000-1800 px away, off screen at the start.
	for c in cands:
		if float(c[1]) > 1000.0:
			far1 = int(c[0])          # the nearest complaint that starts off screen
			break
	if far1 < 0:
		far1 = int(cands[cands.size() - 1][0])
	for c in cands:
		if int(c[0]) != far1 and hood.lots[far1].inspect_anchor().distance_to(hood.lots[int(c[0])].inspect_anchor()) > 450.0:
			far2 = int(c[0])
			break
	street.select_objective(far1)
	print("VIDEO02 far1=", far1, " far2=", far2, " dist=", spawn.distance_to(hood.lots[far1].inspect_anchor()))


func _ready() -> void:
	await boot_hidden(2024, true, "VIDEO 02", "FIND THE COMPLAINT", _setup)
	await wait(3.5)                       # Next chip, address, complaint badge, minimap, edge arrow with distance
	await tap_hud(street.hud_view.minimap_rect())
	await wait(4.0)                       # full map: the selected complaint
	await tap_hud(street.hud_view._map_close_rect())
	await wait(1.5)
	# Walk toward it. The arrow keeps pointing, the distance counts down, the minimap marker closes in.
	var lot1 = hood.lots[far1]
	var ok: bool = await walk_to(lot1.inspect_anchor(), 40.0, 120.0, false, 0.75)
	await wait(3.0)                       # arrival cue, address, COMPLAINT badge (no verdict)
	# Hop to the next assignment with the Next chip: everything must change together.
	await tap_hud(street.hud_view.next_rect)
	await wait(3.5)
	var before := int(street.objective)
	await tap_hud(street.hud_view.next_rect)
	await wait(3.0)
	if far2 >= 0 and int(street.objective) != far2:
		# Cycle until the chosen second case is selected (still only the real chip).
		for i in 6:
			if int(street.objective) == far2:
				break
			await tap_hud(street.hud_view.next_rect)
			await wait(1.5)
	await wait(2.0)
	var lot2 = hood.lots[int(street.objective)]
	await walk_to(lot2.inspect_anchor(), 40.0, 25.0, false, 0.75)   # head toward it; arrow and distance update
	await wait(2.5)
	await finish()
