extends RefCounted
## The HOA simulation: complaints, evidence-backed rulings, the cure/reinspection/
## hearing/fine workflow, residents, the board and legal risk. No UI and no
## drawing. It reads and changes GameState stats and returns text for the UI.

const Violations := preload("res://scripts/sim/violations.gd")
const Residents := preload("res://scripts/sim/residents.gd")
const Board := preload("res://scripts/sim/board.gd")

const ANNUAL_MEETING_EVERY := 10
const ACTIONS := ["dismiss", "warning", "hearing", "fine"]
const OPEN_STATES := ["warning", "extended", "hearing", "fined", "disputed"]

var violations := Violations.new()
var residents := Residents.new()
var board := Board.new()

var properties: Dictionary = {}
var cases: Dictionary = {}
var politics: Dictionary = {}
var projects: Array = []
## Today's work. lot id -> {kind: lawn|card|reinspect, source, violations, false_complaint, text, status}
var assignments: Dictionary = {}
var completed: Array = []
## Real violations visible on lots with no complaint: lot id -> allegations.
var discoverable: Dictionary = {}
var discovered_today := 0
## Money trail and agenda decisions, shown in the Wozig portal.
var ledger: Array = []
var agenda_log: Array = []
const DOLLARS_PER_POINT := 690
var rng := RandomNumberGenerator.new()
var _house_count := 0


func setup(house_count: int) -> void:
	_house_count = house_count
	violations.load_data()
	rng.randomize()


func new_term() -> void:
	properties = residents.create(_house_count)
	cases = {}
	politics = board.create()
	projects = []
	assignments = {}
	completed = []
	discoverable = {}
	ledger = []
	agenda_log = []


func load_world(world: Dictionary) -> void:
	properties = residents.migrate((world.get("properties", {}) as Dictionary).duplicate(true), _house_count)
	cases = (world.get("cases", {}) as Dictionary).duplicate(true)
	politics = board.migrate((world.get("politics", board.create()) as Dictionary).duplicate(true))
	projects = (world.get("projects", []) as Array).duplicate(true)
	assignments = (world.get("complaints", {}) as Dictionary).duplicate(true)
	completed = (world.get("completed", []) as Array).duplicate()
	discoverable = (world.get("discoverable", {}) as Dictionary).duplicate(true)
	discovered_today = int(world.get("discovered_today", 0))
	ledger = (world.get("ledger", []) as Array).duplicate(true)
	agenda_log = (world.get("agenda_log", []) as Array).duplicate(true)


func save_into(world: Dictionary) -> void:
	world.properties = properties.duplicate(true)
	world.cases = cases.duplicate(true)
	world.politics = politics.duplicate(true)
	world.projects = projects.duplicate(true)
	world.complaints = assignments.duplicate(true)
	world.completed = completed.duplicate()
	world.discoverable = discoverable.duplicate(true)
	world.discovered_today = discovered_today
	world.ledger = ledger.duplicate(true)
	world.agenda_log = agenda_log.duplicate(true)


# ---------------------------------------------------------------- money and agenda

## Records any treasury change in `effects` as dollars with a reason.
func record_money(label: String, effects: Dictionary) -> void:
	var points := int(effects.get("budget", 0))
	if points == 0:
		return
	ledger.append({"day": GameState.day, "label": label, "dollars": points * DOLLARS_PER_POINT})
	if ledger.size() > 80:
		ledger.pop_front()


func apply_effects(label: String, effects: Dictionary) -> void:
	record_money(label, effects)
	GameState.apply_effects(effects)


func record_agenda(who: String, choice: String) -> void:
	agenda_log.append({"day": GameState.day, "who": who, "choice": choice})
	if agenda_log.size() > 40:
		agenda_log.pop_front()


# ---------------------------------------------------------------- lookups

func owner_of(house: int) -> String:
	return str(properties.get(house, {}).get("owner", "The Residents"))


func property_of(house: int) -> Dictionary:
	return properties.get(house, {})


func relationship_text(house: int) -> String:
	return Residents.relationship_label(int(property_of(house).get("relationship", 0)))


func open_case_count() -> int:
	var n := 0
	for record in cases.values():
		if str(record.get("state", "")) in OPEN_STATES:
			n += 1
	return n


## State per lot for the world/map markers.
func case_states() -> Dictionary:
	var result := {}
	for house in cases:
		var state := str(cases[house].get("state", ""))
		if state in OPEN_STATES:
			result[int(house)] = {"warning": "warning", "extended": "warning", "hearing": "hearing",
					"fined": "fined", "disputed": "disputed"}.get(state, "warning")
		elif state == "compliant":
			result[int(house)] = "compliant"
	return result


func board_support() -> int:
	return board.support_average(politics)


func legal_risk() -> int:
	return int(politics.get("legal", 0))


# ---------------------------------------------------------------- day setup

## Advances the world to a new morning. Returns {report, hearings, meeting}.
func start_day(day: int, season: int, weekday: int) -> Dictionary:
	var report: Array = []
	var hearings: Array = []
	report.append_array(_process_cases(day, hearings))
	report.append_array(_process_projects())
	report.append_array(_process_politics(day))
	var meeting: Array = []
	if day > 1 and day % ANNUAL_MEETING_EVERY == 0:
		meeting = board.election(politics, int(GameState.stats.get("power", 50)), rng)
	_daily_drift(day)
	_generate_assignments(day, season, weekday)
	return {"report": report, "hearings": hearings, "meeting": meeting}


## Stats settle back toward balance, so good administration can last and neither
## tyranny nor popularity runs away on its own.
func _daily_drift(day: int) -> void:
	if day <= 1:
		return
	var power: int = GameState.stats.get("power", 50)
	var happy: int = GameState.stats.get("happiness", 50)
	var budget: int = GameState.stats.get("budget", 50)
	var delta := {"budget": 1}   # dues
	if budget > 60:
		delta.budget = -ceili(float(budget - 60) / 3.0)   # reserves get spent
	if power > 55:
		delta.power = -ceili(float(power - 55) / 2.0)
	elif power < 45:
		delta.power = 1
	if happy < 45:
		delta.happiness = 2
	elif happy > 65:
		delta.happiness = -1
	apply_effects("HOA dues" if int(delta.get("budget", 0)) >= 0 else "Reserve spending", delta)
	for i in (politics.board as Array).size():
		var support: int = int(politics.board[i].support)
		if support < 50:
			board.shift(politics, 1, i)
		elif support > 70:
			board.shift(politics, -1, i)


func _generate_assignments(day: int, season: int, weekday: int) -> void:
	assignments = {}
	completed = []
	discoverable = {}
	discovered_today = 0
	var weekend := weekday >= 5
	# Cases whose cure period ended need a physical reinspection.
	for house in cases:
		var record: Dictionary = cases[house]
		if str(record.get("state", "")) in ["warning", "extended", "fined"] and int(record.get("cure_due", 9999)) <= day:
			var result := _roll_reinspection(int(house), record)
			record.reinspect_result = result
			cases[house] = record
			var remaining: Array = []
			for v in record.get("violations", []):
				if str(v.id) in record.get("cited", []):
					var item: Dictionary = (v as Dictionary).duplicate(true)
					item.actual = result != "fixed"
					item.borderline = result == "partial"
					remaining.append(item)
			assignments[int(house)] = {"kind": "reinspect", "source": "sweep", "violations": remaining,
					"false_complaint": result == "fixed", "text": "Cure period ended. Check the property.",
					"status": "assigned", "result": result}
	var count := mini(4 + (day - 1) / 3, 8) + (1 if weekend else 0)
	var order: Array = range(_house_count)
	var key := {}
	for h in order:
		var p: Dictionary = properties.get(h, {})
		key[h] = rng.randf() - 0.15 * int(p.get("repeat_count", 0)) - (0.2 if int(p.get("compliance", 60)) < 40 else 0.0)
	order.sort_custom(func(a, b): return key[a] < key[b])
	var picked := 0
	for h in order:
		if picked >= count:
			break
		if assignments.has(h) or str(cases.get(h, {}).get("state", "")) in OPEN_STATES:
			continue
		assignments[h] = _make_complaint(h, day, season, weekend)
		picked += 1
	# A few real violations the inspector can spot on patrol, with no complaint filed.
	var hidden := 0
	for h in order:
		if hidden >= 3:
			break
		if assignments.has(h) or discoverable.has(h) or rng.randf() > 0.12:
			continue
		var pool := violations.available(season, weekend)
		var def: Dictionary = pool[rng.randi() % pool.size()]
		discoverable[h] = [violations.make_allegation(def, 1.0, rng, 1)]
		hidden += 1


func _make_complaint(house: int, day: int, season: int, weekend: bool) -> Dictionary:
	var property: Dictionary = properties.get(house, {})
	var source := _pick_source(house, day)
	var reliability := violations.source_reliability(source)
	if day <= 2:
		reliability = maxf(reliability, 0.88)
	if Residents.has_trait(property, "str_owner") or Residents.has_trait(property, "repeat_offender"):
		reliability = minf(1.0, reliability + 0.1)
	var pool := violations.available(season, weekend)
	var count := 1 if day <= 2 else 1 + (1 if rng.randf() < 0.3 else 0) + (1 if day > 6 and rng.randf() < 0.12 else 0)
	var allegations: Array = []
	var seen: Array = []
	while allegations.size() < count and seen.size() < pool.size():
		var def: Dictionary = pool[rng.randi() % pool.size()]
		if str(def.id) in seen:
			seen.append(str(def.id) + str(seen.size()))
			continue
		seen.append(str(def.id))
		var item := violations.make_allegation(def, reliability, rng)
		if day <= 2:
			item.borderline = false
		allegations.append(item)
	var false_complaint := allegations.all(func(v): return not bool(v.actual))
	var kind := "lawn" if str(allegations[0].id) == "tall_grass" else "card"
	var complainant := violations.source_label(source)
	if source == "resident" or source == "chronic":
		complainant = "%s (neighbor)" % _random_neighbor(house)
	return {"kind": kind, "source": source, "complainant": complainant, "violations": allegations,
			"false_complaint": false_complaint, "text": str(allegations[0].complaint), "status": "assigned"}


func _random_neighbor(house: int) -> String:
	var other := (house + 1 + rng.randi() % maxi(_house_count - 1, 1)) % _house_count
	return owner_of(other)


func _pick_source(house: int, day: int) -> String:
	var roll := rng.randf()
	var seat_owner := Residents.has_trait(properties.get(house, {}), "board_insider")
	if roll < 0.12 and day > 2:
		return "board"
	if roll < 0.28:
		return "management"
	if roll < 0.40 and day > 1:
		return "anonymous"
	if roll < 0.50 and day > 3:
		return "security"
	if roll < 0.58 and day > 3:
		return "arc"
	if roll < 0.66 and day > 4:
		return "sweep"
	if rng.randf() < 0.3 and not seat_owner:
		return "chronic"
	return "resident"


func _roll_reinspection(house: int, record: Dictionary) -> String:
	var property: Dictionary = properties.get(house, {})
	var chance := Residents.compliance_chance(property, 10 if str(record.state) == "fined" else 0)
	var roll := rng.randi_range(0, 99)
	if roll < chance:
		return "fixed"
	if roll < chance + 18:
		return "partial"
	if roll < 96:
		return "unchanged"
	return "worse"


# ---------------------------------------------------------------- rulings

## Which actions the rules allow for this complaint and why not when disabled.
func ruling_options(house: int, cited: Array, evidence: Dictionary) -> Dictionary:
	var options := {"dismiss": {"enabled": true, "reason": ""}}
	var documented: Array = evidence.get("documented", [])
	var quality := int(evidence.get("quality", 0))
	var max_severity := 0
	var has_notice := false
	var record: Dictionary = cases.get(house, {})
	for id in cited:
		max_severity = maxi(max_severity, int(violations.get_def(str(id)).get("severity", 1)))
	for entry in property_of(house).get("history", []):
		if str(entry.get("action", "")) in ["warning", "hearing"] and _ids_overlap(entry.get("ids", []), cited):
			has_notice = true
	var documented_cited := false
	for id in cited:
		if str(id) in documented:
			documented_cited = true
	if cited.is_empty():
		var why := "Tick at least one violation to cite."
		for a in ["warning", "hearing", "fine"]:
			options[a] = {"enabled": false, "reason": why}
		return options
	options.warning = {"enabled": true, "reason": ""}
	var hearing_ok := has_notice or max_severity >= 2
	options.hearing = {"enabled": hearing_ok, "reason": "" if hearing_ok else "A first notice must be a warning (unless the violation is serious)."}
	var fine_reason := ""
	if str(record.get("state", "")) in ["warning", "extended"] and int(record.get("cure_due", 0)) > GameState.day:
		fine_reason = "Cure period still running."
	elif not (has_notice or max_severity >= 3):
		fine_reason = "Needs a prior warning or hearing, unless the violation is severe."
	elif not documented_cited and quality < 40:
		fine_reason = "Needs usable photo evidence of the violation."
	options.fine = {"enabled": fine_reason == "", "reason": fine_reason}
	return options


func _ids_overlap(a, b) -> bool:
	for id in a:
		if id in b:
			return true
	return false


## Applies a ruling from the case file. Returns {effects, points, correct, lines, state}.
func rule_case(house: int, action: String, cited: Array, evidence: Dictionary) -> Dictionary:
	var assignment: Dictionary = assignments[house]
	var allegations: Array = assignment.get("violations", [])
	var property: Dictionary = properties.get(house, {})
	var false_complaint := bool(assignment.get("false_complaint", false))
	var actual_cited := 0
	var false_cited := 0
	var documented_cited := 0
	var max_severity := 1
	var documented: Array = evidence.get("documented", [])
	for v in allegations:
		if str(v.id) in cited:
			max_severity = maxi(max_severity, int(v.severity))
			if bool(v.actual):
				actual_cited += 1
				if str(v.id) in documented:
					documented_cited += 1
			else:
				false_cited += 1
	var quality := int(evidence.get("quality", 0))
	var strength := 0.0
	if actual_cited > 0:
		strength = clampf(0.25 + 0.5 * float(documented_cited) / maxf(cited.size(), 1.0) + 0.25 * quality / 100.0, 0.0, 1.0)
	if str(assignment.get("kind", "")) == "lawn" and actual_cited > 0:
		strength = maxf(strength, 0.7)
	var effects := {}
	var points := 0
	var correct := false
	var lines: Array = []
	var fine_amount := 0
	if action == "dismiss":
		correct = false_complaint
		if correct:
			effects = {"happiness": 3, "power": 1}
			points = 100
			lines.append("Complaint dismissed. The record shows nothing to cite.")
			Residents.shift(property, 6, GameState.day, "complaint dismissed fairly")
		else:
			effects = {"happiness": -2, "power": -3}
			points = -50
			lines.append("A real violation went unaddressed. The neighbors noticed.")
			Residents.shift(property, 4, GameState.day, "violation overlooked")
	else:
		correct = actual_cited > 0 and false_cited == 0
		var worst := ""
		for v in allegations:
			if str(v.id) in cited:
				worst = str(v.id)
		fine_amount = violations.fine_amount(worst, int(property.get("repeat_count", 0)))
		match action:
			"warning":
				effects = {"happiness": -max_severity, "power": 1}
				Residents.shift(property, -3, GameState.day, "warning issued")
			"hearing":
				effects = {"power": 1}
				Residents.shift(property, -6, GameState.day, "hearing scheduled")
			"fine":
				effects = {"budget": clampi(roundi(fine_amount / 60.0), 1, 8), "happiness": -(2 + max_severity), "power": 2}
				Residents.shift(property, -10, GameState.day, "fined")
		points = 100 + 20 * documented_cited if correct else (-25 if cited.is_empty() else -75)
		if not correct:
			effects = {"budget": -6 if action == "fine" else 0, "happiness": -8 if action == "fine" else -4, "power": -5 if action == "fine" else -3}
			Residents.shift(property, -20, GameState.day, "cited wrongly")
			board.add_legal(politics, 8 if action == "fine" else 3)
			lines.append("The citation does not hold up against the facts.")
		elif strength < 0.5:
			lines.append("Thin evidence. Expect pushback.")
	_record_case(house, action, cited, evidence, assignment, strength, false_cited, fine_amount)
	if correct and strength >= 0.85 and action != "dismiss":
		board.shift(politics, 1)   # the board likes a well-documented case
	elif action == "dismiss" and false_complaint:
		board.shift(politics, 1)
	elif not correct and action != "dismiss":
		board.shift(politics, -2)
	var group := Residents.group(property)
	board.record(politics, group, action != "dismiss", not false_complaint)
	if group == "board":
		var seat := int(property.get("seat", house % 5))
		if action != "dismiss":
			board.shift(politics, -12, seat)
			board.shift(politics, -2)
		elif not false_complaint:
			board.shift(politics, 8, seat)
	if action != "dismiss" and group == "legal" and strength < 0.6:
		board.add_legal(politics, 8)
	properties[house] = property
	completed.append(house)
	if OS.get_cmdline_user_args().has("trace"):
		print("    case %s cited=%s actual_cited=%d false_cited=%d false_complaint=%s strength=%.2f -> %s pts %d correct %s" % [action, str(cited), actual_cited, false_cited, str(false_complaint), strength, str(effects), points, str(correct)])
	return {"effects": effects, "points": points, "correct": correct, "lines": lines,
			"state": str(cases[house].state), "strength": strength}


func _record_case(house: int, action: String, cited: Array, evidence: Dictionary, assignment: Dictionary,
		strength: float, false_cited: int, fine_amount: int) -> void:
	var day := GameState.day
	var property: Dictionary = properties.get(house, {})
	var false_complaint := bool(assignment.get("false_complaint", false))
	var state := "cleared"
	var enforcing := action != "dismiss"
	if not enforcing:
		state = "cleared" if false_complaint else "missed_violation"
	else:
		var chance := Residents.dispute_chance(property) + (0.25 if strength < 0.5 else 0.0) + (0.5 if false_complaint or false_cited > 0 else 0.0)
		var disputed := rng.randf() < clampf(chance, 0.0, 0.95)
		state = "disputed" if disputed else {"warning": "warning", "hearing": "hearing", "fine": "fined"}[action]
	var cure := 99
	for v in assignment.get("violations", []):
		if str(v.id) in cited:
			cure = mini(cure, int(v.cure_days))
	if cure == 99:
		cure = 2
	cases[house] = {"property": house, "state": state, "action": action, "cited": cited.duplicate(),
			"violations": (assignment.get("violations", []) as Array).duplicate(true), "strength": strength,
			"opened_day": day, "cure_due": day + cure, "hearing_day": day + 1, "dispute_day": day + 1,
			"fine_amount": fine_amount, "false_complaint": false_complaint, "source": str(assignment.get("source", "")),
			"evidence_quality": int(evidence.get("quality", 0))}
	var history: Array = property.get("history", [])
	history.append({"day": day, "state": state, "action": action, "ids": cited.duplicate()})
	property.history = history
	if enforcing and not false_complaint:
		property.repeat_count = int(property.get("repeat_count", 0)) + 1
	properties[house] = property


# ---------------------------------------------------------------- reinspection

func reinspection_options(house: int) -> Dictionary:
	var record: Dictionary = cases.get(house, {})
	var result := str(record.get("reinspect_result", "unchanged"))
	var cited: Array = record.get("cited", [])
	var evidence := {}
	var options := {}
	options.close = {"enabled": result in ["fixed", "partial"], "reason": "Violation still present." if not result in ["fixed", "partial"] else ""}
	options.extend = {"enabled": result != "fixed" and int(record.get("extensions", 0)) < 2, "reason": "" if result != "fixed" and int(record.get("extensions", 0)) < 2 else "No more extensions."}
	options.hearing = {"enabled": result != "fixed", "reason": "Nothing to take to a hearing." if result == "fixed" else ""}
	var fine_ok := result in ["unchanged", "worse"] or (result == "partial" and int(record.get("extensions", 0)) > 0)
	options.fine = {"enabled": fine_ok, "reason": "" if fine_ok else "Issue a fine only for unresolved violations."}
	if str(record.get("state", "")) == "fined" and result != "fixed":
		options.fine = {"enabled": true, "reason": ""}
	return options


## choice: close | extend | hearing | fine. Returns {effects, points, lines}.
func resolve_reinspection(house: int, choice: String) -> Dictionary:
	var record: Dictionary = cases[house]
	var property: Dictionary = properties.get(house, {})
	var result := str(record.get("reinspect_result", "unchanged"))
	var effects := {}
	var points := 0
	var lines: Array = []
	var day := GameState.day
	match choice:
		"close":
			record.state = "compliant"
			points = 60 if result == "fixed" else 35
			effects = {"happiness": 2, "power": 1}
			Residents.shift(property, 4, day, "case closed fairly")
			lines.append("Case closed. The property is compliant.")
		"extend":
			record.state = "extended"
			record.extensions = int(record.get("extensions", 0)) + 1
			record.cure_due = day + 2
			Residents.shift(property, 3, day, "extension granted")
			effects = {"happiness": 1}
			lines.append("Two more days to cure. The homeowner is relieved.")
		"hearing":
			record.state = "hearing"
			record.hearing_day = day + 1
			Residents.shift(property, -6, day, "hearing scheduled")
			lines.append("Hearing scheduled for tomorrow's board meeting.")
		"fine":
			var amount := int(record.get("fine_amount", 0))
			if amount <= 0:
				amount = 100
			record.state = "fined"
			record.cure_due = day + 2
			effects = {"budget": clampi(roundi(amount / 60.0), 1, 8), "happiness": -3, "power": 2}
			Residents.shift(property, -10, day, "fined after reinspection")
			property.repeat_count = int(property.get("repeat_count", 0)) + 1
			lines.append("Fine issued after reinspection.")
	var history: Array = property.get("history", [])
	history.append({"day": day, "state": str(record.state), "action": "reinspect_" + choice, "ids": record.get("cited", [])})
	property.history = history
	properties[house] = property
	cases[house] = record
	completed.append(house)
	return {"effects": effects, "points": points, "lines": lines}


# ---------------------------------------------------------------- hearings

func build_hearing(house: int) -> Dictionary:
	var record: Dictionary = cases[house]
	var property: Dictionary = properties.get(house, {})
	var strength := float(record.get("strength", 0.0))
	var labels: Array = []
	var rules: Array = []
	for v in record.get("violations", []):
		if str(v.id) in record.get("cited", []):
			labels.append(str(v.label))
			rules.append(str(violations.get_def(str(v.id)).get("description", "")))
	var argument := "I did nothing wrong, and I have a lawyer who agrees."
	if Residents.has_trait(property, "litigious"):
		argument = "My attorney will note for the record that this is a very bad idea."
	elif Residents.has_trait(property, "elderly"):
		argument = "I've lived here forty years. That tree was here first."
	elif Residents.has_trait(property, "new_homeowner"):
		argument = "Nobody told me about this rule. I read the packet. It was 90 pages."
	elif Residents.has_trait(property, "friendly"):
		argument = "I'll fix it, I promise. I'm sorry, honestly."
	elif Residents.has_trait(property, "anti_hoa"):
		argument = "This entire proceeding is an overreach and a scam."
	var recommendation := "fine" if strength >= 0.6 else ("warning" if strength >= 0.3 else "dismiss")
	return {"house": house, "owner": owner_of(house), "violations": labels, "rules": rules, "argument": argument,
			"strength": strength, "quality": int(record.get("evidence_quality", 0)),
			"recommendation": recommendation, "fine_amount": int(record.get("fine_amount", 100)),
			"relationship": relationship_text(house)}


## recommendation: dismiss | warning | fine. `present_evidence` adds weight when the file is strong.
func hold_hearing(house: int, recommendation: String, present_evidence: bool) -> Dictionary:
	var record: Dictionary = cases[house]
	var property: Dictionary = properties.get(house, {})
	var strength := float(record.get("strength", 0.0))
	if present_evidence:
		strength = clampf(strength + (0.12 if int(record.get("evidence_quality", 0)) >= 60 else -0.04), 0.0, 1.0)
	var lines: Array = []
	var effects := {}
	var votes: Array = []
	if recommendation == "dismiss":
		record.state = "overturned"
		lines.append("Dismissed at the hearing. The homeowner thanks the board.")
		Residents.shift(property, 8, GameState.day, "hearing dismissed")
		effects = {"happiness": 2}
	else:
		var seat := int(property.get("seat", -1))
		votes = board.vote_all(politics, {"action": recommendation, "strength": strength,
				"severity": 2, "amount": int(record.get("fine_amount", 0)), "owner_seat": seat,
				"elderly": Residents.has_trait(property, "elderly")}, rng)
		var yes := board.tally(votes)
		var total := votes.size()
		if yes * 2 > total:
			if recommendation == "fine":
				var amount := int(record.get("fine_amount", 100)) + 25 * int(property.get("repeat_count", 0))
				record.state = "fined"
				record.cure_due = GameState.day + 2
				effects = {"budget": clampi(roundi(amount / 60.0), 1, 8), "happiness": -3, "power": 2}
				lines.append("Hearing: %d to %d. Fine upheld ($%d)." % [yes, total - yes, amount])
				Residents.shift(property, -8, GameState.day, "fined at hearing")
			else:
				record.state = "warning"
				record.cure_due = GameState.day + 2
				lines.append("Hearing: %d to %d. Written warning stands." % [yes, total - yes])
				Residents.shift(property, -2, GameState.day, "warned at hearing")
		else:
			record.state = "overturned"
			effects = {"power": -3, "happiness": 2}
			lines.append("Hearing: %d to %d. The board overturned the notice." % [yes, total - yes])
			Residents.shift(property, 6, GameState.day, "board sided with them")
	var history: Array = property.get("history", [])
	history.append({"day": GameState.day, "state": str(record.state), "action": "hearing", "ids": record.get("cited", [])})
	property.history = history
	properties[house] = property
	cases[house] = record
	return {"votes": votes, "lines": lines, "effects": effects, "state": str(record.state)}


# ---------------------------------------------------------------- patrol discovery

## Opens a case from something the inspector spotted. Too much of it annoys the neighbors.
func open_discovered(house: int) -> Dictionary:
	if not discoverable.has(house):
		return {}
	var allegations: Array = discoverable[house]
	discoverable.erase(house)
	discovered_today += 1
	assignments[house] = {"kind": "card", "source": "player", "complainant": "Your own observation",
			"violations": allegations, "false_complaint": false, "text": str((allegations[0] as Dictionary).complaint),
			"status": "assigned", "discovered": true}
	var lines: Array = []
	if discovered_today > 2:
		GameState.apply_effects({"happiness": -3, "power": -1})
		Residents.shift(properties[house], -5, GameState.day, "ticketed on patrol")
		lines.append("Residents are tired of the roaming inspector. Community -3.")
	return {"lines": lines}


# ---------------------------------------------------------------- daily processing

func _process_cases(day: int, hearings: Array) -> Array:
	var lines: Array = []
	for house in cases.keys():
		var record: Dictionary = cases[house]
		var property: Dictionary = properties.get(house, {})
		var address := "lot %d" % int(house)
		match str(record.get("state", "")):
			"disputed":
				if int(record.get("dispute_day", 9999)) > day:
					continue
				var strength := float(record.get("strength", 0.0))
				var win := 0.85 if bool(record.get("false_complaint", false)) else clampf((1.0 - strength) * 0.8, 0.1, 0.8)
				if rng.randf() < win:
					record.state = "overturned"
					apply_effects("Dispute settlement", {"budget": -6, "happiness": 3})
					board.add_legal(politics, 6)
					Residents.shift(property, 8, day, "dispute upheld")
					lines.append("Dispute upheld at %s. Citation withdrawn." % address)
				else:
					record.state = {"warning": "warning", "hearing": "hearing", "fine": "fined"}.get(str(record.action), "warning")
					record.cure_due = day + 2
					record.hearing_day = day + 1
					GameState.apply_effects({"happiness": -2})
					lines.append("Dispute denied at %s. Notice stands." % address)
				cases[house] = record
			"hearing":
				if int(record.get("hearing_day", 9999)) <= day:
					hearings.append(int(house))
		properties[house] = property
	return lines


func _process_projects() -> Array:
	var lines: Array = []
	var remaining: Array = []
	for project in projects:
		var daily: Dictionary = project.get("daily", {})
		apply_political(daily)
		apply_effects(str(project.get("name", "Project")), daily)
		project.days = int(project.get("days", 1)) - 1
		if int(project.days) <= 0:
			var finish: Dictionary = project.get("finish", {})
			apply_political(finish)
			apply_effects(str(project.get("name", "Project")) + " finished", finish)
			lines.append("%s finished." % str(project.get("name", "Project")))
		else:
			lines.append("%s: %d day(s) left." % [str(project.get("name", "Project")), int(project.days)])
			remaining.append(project)
	projects = remaining
	return lines


func _process_politics(day: int) -> Array:
	var lines: Array = []
	if day <= 1:
		return lines
	if board.fairness_gap(politics) > 0.4:
		board.add_legal(politics, 8)
		lines.append("LEGAL COUNSEL: %s" % board.counsel_warning(politics))
	else:
		board.add_legal(politics, -2)
	if legal_risk() >= 100:
		apply_effects("Lawsuit settlement", {"budget": -36, "power": -8})
		politics.legal = 40
		lines.append("A lawsuit settles for $25,000. The board is not pleased.")
	elif legal_risk() >= 70:
		lines.append("LEGAL COUNSEL: Legal risk is high. Documentation and consistent process, please.")
	for i in (politics.board as Array).size():
		if int(politics.board[i].support) < 30:
			lines.append("%s is lobbying to remove you." % str(Board.member(i).name))
			GameState.apply_effects({"power": -2})
			break
	return lines


## Effects may carry the political keys "legal" (risk) and "board" (support).
func apply_political(effects: Dictionary) -> void:
	board.add_legal(politics, int(effects.get("legal", 0)))
	if effects.has("board"):
		board.shift(politics, int(effects.board))
