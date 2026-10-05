extends RefCounted
## The board as characters: priorities, votes, elections, legal risk and the
## selective-enforcement tracker. State is a plain dictionary so it saves cleanly.

const ROLES := [
	{"name": "Pat Whitmore", "role": "Treasurer", "priority": "budget", "color": Color("5b8c5a"),
		"temperament": "Counts everything twice, including the pencils."},
	{"name": "Lorraine Cho", "role": "Community advocate", "priority": "happiness", "color": Color("d98a4a"),
		"temperament": "Believes every problem can be fixed with a potluck."},
	{"name": "Ben Aldridge", "role": "Longtime resident", "priority": "tradition", "color": Color("8a6f56"),
		"temperament": "Remembers when this was a cornfield and says so."},
	{"name": "Dana Ruiz", "role": "Counsel", "priority": "legal", "color": Color("5b6f8f"),
		"temperament": "Speaks only in disclaimers."},
	{"name": "Walt Pruitt", "role": "Compliance hawk", "priority": "enforcement", "color": Color("b3473e"),
		"temperament": "Measures things for fun."},
]


func create() -> Dictionary:
	var board: Array = []
	for i in ROLES.size():
		board.append({"support": 48 + (i * 7) % 17})
	return {"board": board, "legal": 10, "enforce": {}}


## Adds fields older saves lack and normalizes board shape.
func migrate(state: Dictionary) -> Dictionary:
	var fresh := create()
	if not state.has("board") or (state.board as Array).size() != ROLES.size():
		state.board = fresh.board
	for i in ROLES.size():
		var m: Dictionary = state.board[i]
		m.erase("name")   # names and roles now come from ROLES
		state.board[i] = m
	if not state.has("legal"):
		state.legal = 10
	if not state.has("enforce"):
		state.enforce = {}
	# Older saves tracked these groups; keep them compatible.
	var map := {"friend": "friend", "board_member": "board", "critic": "critic", "legal_threat": "legal", "neutral": "neutral"}
	var fixed := {}
	for key in state.enforce:
		fixed[map.get(str(key), str(key))] = state.enforce[key]
	state.enforce = fixed
	return state


static func member(index: int) -> Dictionary:
	return ROLES[index]


func support_average(state: Dictionary) -> int:
	var total := 0
	for m in state.board:
		total += int(m.support)
	return total / maxi((state.board as Array).size(), 1)


func shift(state: Dictionary, delta: int, who := -1) -> void:
	for i in (state.board as Array).size():
		if who < 0 or who == i:
			state.board[i].support = clampi(int(state.board[i].support) + delta, 0, 100)


func add_legal(state: Dictionary, delta: int) -> void:
	state.legal = clampi(int(state.get("legal", 0)) + delta, 0, 120)


func record(state: Dictionary, group: String, enforced: bool, real_violation: bool) -> void:
	if not real_violation:
		return
	var tally: Dictionary = state.enforce.get(group, {"cases": 0, "enforced": 0, "missed": 0})
	tally.cases = int(tally.cases) + 1
	if enforced:
		tally.enforced = int(tally.enforced) + 1
	else:
		tally.missed = int(tally.missed) + 1
	state.enforce[group] = tally


func _rate(state: Dictionary, groups: Array) -> Array:
	var cases := 0
	var enforced := 0
	for g in groups:
		var t: Dictionary = state.enforce.get(g, {})
		cases += int(t.get("cases", 0))
		enforced += int(t.get("enforced", 0))
	return [cases, float(enforced) / maxf(float(cases), 1.0)]


## 0..1: how much harder critics are enforced against than friends and insiders.
func fairness_gap(state: Dictionary) -> float:
	var favored := _rate(state, ["friend", "board"])
	var critics := _rate(state, ["critic", "legal"])
	if int(favored[0]) < 3 or int(critics[0]) < 3:
		return 0.0
	return clampf(float(critics[1]) - float(favored[1]), 0.0, 1.0)


## Enforcement rate per political group among valid violations, for the dashboard.
func group_rates(state: Dictionary) -> Array:
	var rows: Array = []
	for g in ["friend", "board", "neutral", "critic", "legal"]:
		var t: Dictionary = state.enforce.get(g, {})
		var cases := int(t.get("cases", 0))
		rows.append({"group": g, "cases": cases, "rate": float(t.get("enforced", 0)) / maxf(float(cases), 1.0)})
	return rows


func fairness_label(state: Dictionary) -> String:
	var gap := fairness_gap(state)
	if gap > 0.4:
		return "Targeted"
	if gap > 0.2:
		return "Leaning"
	return "Even-handed"


func counsel_warning(state: Dictionary) -> String:
	if fairness_gap(state) > 0.35:
		return "Recent enforcement appears disproportionately focused on critics of the board."
	if int(state.legal) >= 70:
		return "Legal risk is high. Documentation and consistent process, please."
	return ""


# ---------------------------------------------------------------- votes

## proposal: {action, strength 0..1, severity, group, amount, owner_seat, repeat, elderly}
func vote_all(state: Dictionary, proposal: Dictionary, rng: RandomNumberGenerator) -> Array:
	var votes: Array = []
	for i in ROLES.size():
		votes.append(_vote(state, i, proposal, rng))
	return votes


func _vote(state: Dictionary, i: int, p: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var role: Dictionary = ROLES[i]
	var prob := 0.3 + float(p.get("strength", 0.0)) * 0.45 + (float(state.board[i].support) - 50.0) / 250.0
	var reason := ""
	match str(role.priority):
		"budget":
			prob += 0.12 if int(p.get("amount", 0)) > 0 else 0.0
			reason = "The numbers say yes." if prob > 0.5 else "The collection costs more than it brings in."
		"happiness":
			prob -= 0.15 if int(p.get("severity", 1)) <= 1 else 0.0
			reason = "A warning and a cookie basket, please." if prob < 0.5 else "Fine. But gently."
		"tradition":
			prob += 0.1 if bool(p.get("elderly", false)) else -0.04
			reason = "That's not how it was done in 1994." if prob < 0.5 else "Rules are rules, even new ones."
		"legal":
			prob += (float(p.get("strength", 0.0)) - 0.5) * 0.4 - float(state.legal) * 0.002
			reason = "The record is thin. I advise caution." if prob < 0.5 else "The record is sufficient. Barely."
		"enforcement":
			prob += 0.25
			reason = "If we don't enforce it, why have it?" if prob > 0.5 else "Even I have limits. Fewer than you'd think."
	var seat: int = int(p.get("owner_seat", -1))
	if seat == i:
		prob -= 0.35
		reason = "I'd like to recuse myself and vote no."
	elif seat >= 0:
		prob -= 0.08
	return {"index": i, "name": role.name, "role": role.role, "yes": rng.randf() < clampf(prob, 0.03, 0.97), "line": reason}


func tally(votes: Array) -> int:
	var yes := 0
	for v in votes:
		if bool(v.yes):
			yes += 1
	return yes


## Annual meeting: each member votes to retain you or not.
func election(state: Dictionary, power: int, rng: RandomNumberGenerator) -> Array:
	var votes: Array = []
	for i in ROLES.size():
		var score := float(state.board[i].support) + rng.randf_range(-10.0, 10.0) + (power - 50) * 0.3 - float(state.legal) * 0.15
		var role: Dictionary = ROLES[i]
		var yes := score >= 45.0
		var line := "Another term. I've seen worse." if yes else "I'm going in a different direction."
		if str(role.priority) == "legal" and int(state.legal) >= 60:
			line = "The legal exposure is my concern." if not yes else "Cautiously, yes."
		votes.append({"index": i, "name": role.name, "role": role.role, "yes": yes, "line": line})
	return votes


## Fuzzy read on the next election. Deliberately imprecise: a day-seeded wobble keeps the
## player guessing, and it blends fairness, mood, treasury, legal trouble and board support.
func outlook(state: Dictionary, stats: Dictionary, day: int) -> String:
	var score := float(support_average(state)) + (int(stats.get("power", 50)) - 50) * 0.3 \
			+ (int(stats.get("happiness", 50)) - 50) * 0.25 + (int(stats.get("budget", 50)) - 50) * 0.08 \
			- float(state.get("legal", 0)) * 0.15 - fairness_gap(state) * 20.0
	score += sin(float(day) * 12.9898) * 7.0
	if score >= 62.0:
		return "Residents seem content"
	if score >= 50.0:
		return "Mixed signals"
	if score >= 40.0:
		return "Restless"
	return "Trouble brewing"


func counsel_mood(state: Dictionary) -> String:
	var legal := int(state.get("legal", 0))
	if legal >= 60:
		return "Alarmed"
	if legal >= 30:
		return "Concerned"
	return "Calm"
