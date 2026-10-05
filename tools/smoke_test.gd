extends Node
## Plays several terms headlessly through the real main scene: walks to every assignment,
## photographs it, rules (all four actions, reinspections, hearings) and advances days.
## Run in a throwaway copy of the project (it writes the player's save slot):
##   godot --headless --path . res://tools/smoke_test.tscn

const MainScene := preload("res://scenes/main.tscn")
const TERMS := 6
const DAYS := 24

## Strategy (pass after "--"): bot=random | smart | fine_all | dismiss_all
var bot := "random"

var _main: Node
var _errors := 0
var _total_days := 0
var _cases := 0
var _best_score := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("bot="):
			bot = arg.substr(4)
	_main = MainScene.instantiate()
	add_child(_main)
	for i in 8:
		await get_tree().process_frame
	_main._street.preview_enabled = false     # bots save photos immediately: no preview screen to tap
	for term in TERMS:
		GameState.clear_run()
		_main._begin(false)
		await _drain()
		for day in DAYS:
			if _main._is_over:
				print("SMOKE[%s]: term %d ended day %d score %d: %s" % [bot, term + 1, GameState.day, GameState.score, _main._over_label.text.split("\n")[0]])
				break
			await _play_day()
			_total_days += 1
		_best_score = maxi(_best_score, GameState.score)
		_main._over_panel.hide()
	print("SMOKE[%s]: finished. days=%d (avg %.1f/term) best_score=%d cases=%d errors=%d" % [bot, _total_days,
			float(_total_days) / TERMS, _best_score, _cases, _errors])
	get_tree().quit()


func _first_button(node: Node) -> Button:
	if node is Button and not (node as Button).disabled:
		return node
	for child in node.get_children():
		var found := _first_button(child)
		if found != null:
			return found
	return null


## Clears whatever modal is up (reports, hearings, votes, events) like a player tapping through.
func _drain() -> void:
	for i in 14:
		await get_tree().process_frame
		var overlay: Control = _main._overlay
		if not overlay.visible or _main._is_over:
			return
		if _main._card != null:
			_main._on_event_swiped("left")
			continue
		var handled := false
		for child in overlay.get_children():
			if child.has_signal("decided"):
				var rec := str(child.data.get("recommendation", "warning")) if bot != "random" else "warning"
				child.decided.emit(rec, true)
				handled = true
			elif child.has_signal("closed"):
				child.closed.emit()
				handled = true
			else:
				var btn := _first_button(child)
				if btn != null:
					btn.pressed.emit()
					handled = true
			break
		if not handled:
			return


func _play_day() -> void:
	var street = _main._street
	var sim = _main.sim
	if OS.get_cmdline_user_args().has("trace"):
		print("  day %d  B%d H%d P%d  board%d legal%d  score %d" % [GameState.day, GameState.stats.budget, GameState.stats.happiness,
				GameState.stats.power, sim.board_support(), sim.legal_risk(), GameState.score])
	var guard := 0
	while sim.completed.size() < sim.assignments.size() and guard < 40 and not _main._is_over:
		guard += 1
		var house := -1
		for h in sim.assignments.keys():
			if not h in sim.completed:
				house = int(h)
				break
		var lot = street.hood.lots[house]
		street.player.position = lot.inspect_anchor()
		for i in 3:
			await get_tree().process_frame
		if street.near != house:
			print("SMOKE: WARNING near=%d expected %d" % [street.near, house])
			_errors += 1
		street.open_camera()
		# Like a player: let the viewfinder settle, then try a few zoom levels until
		# the camera says there is something worth recording.
		for zoom in [1.4, 1.0, 1.8, 2.2]:
			street.camera_ev.zoom = zoom
			for i in 18:
				await get_tree().process_frame
			if bool(street.frame_info.get("potential", false)):
				break
		await street.take_photo()
		_main._close_overlay()
		_main._on_visit(house)
		await get_tree().process_frame
		var a: Dictionary = sim.assignments[house]
		_cases += 1
		if str(a.kind) == "reinspect":
			var options: Dictionary = sim.reinspection_options(house)
			var pick := "close"
			for choice in _reinspect_order():
				if bool(options[choice].enabled):
					pick = choice
					break
			_main._close_property_card()
			_main._on_reinspection_choice(pick)
		else:
			if str(a.kind) == "lawn" and not _main._measurements.has(house):
				_main._on_lawn_measured(float(a.violations[0].get("actual", false)) * 3.0 + 4.0, true)
			var evidence: Dictionary = _main._evidence_for(house)
			var cited: Array = []
			for v in a.violations:
				match bot:
					"smart":
						if str(v.id) in evidence.get("documented", []):
							cited.append(str(v.id))
					"fine_all", "random":
						if bot == "fine_all" or randf() < 0.85:
							cited.append(str(v.id))
			var options: Dictionary = sim.ruling_options(house, cited, evidence)
			var action := "dismiss"
			match bot:
				"dismiss_all":
					action = "dismiss"
				"smart":
					action = "warning" if not cited.is_empty() else "dismiss"
					if not cited.is_empty() and bool(options.hearing.enabled) and randf() < 0.3:
						action = "hearing"
				"fine_all":
					for choice in ["fine", "hearing", "warning"]:
						if bool(options[choice].enabled):
							action = choice
							break
				_:
					var enabled: Array = []
					for choice in ["dismiss", "warning", "hearing", "fine"]:
						if bool(options[choice].enabled):
							enabled.append(choice)
					action = enabled[randi() % enabled.size()]
			_main._close_property_card()
			_main._on_case_ruled(action, cited if action != "dismiss" else [])
		await get_tree().process_frame
		await _drain_nonevening()
	if not _main._is_over and _main._phase == "evening":
		_main._close_overlay()
		GameState.next_day()
		_main._new_day()
		await _drain()


func _drain_nonevening() -> void:
	if _main._phase != "evening":
		_main._close_overlay()


func _reinspect_order() -> Array:
	match bot:
		"fine_all":
			return ["fine", "hearing", "extend", "close"]
		"dismiss_all":
			return ["close", "extend", "hearing", "fine"]
		"smart":
			return ["close", "extend", "hearing", "fine"]
	return ["close", "extend", "hearing", "fine"]
