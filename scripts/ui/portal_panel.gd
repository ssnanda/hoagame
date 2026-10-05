extends Panel
## Wozig Management Portal: the in-world records screen. Overview, cases,
## property directory and the board.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Board := preload("res://scripts/sim/board.gd")
const Residents := preload("res://scripts/sim/residents.gd")

signal closed

var sim
var street
var _body: VBoxContainer
var _tab := "overview"
var start_tab := "overview"


func setup(simulation, street_node) -> void:
	sim = simulation
	street = street_node


func _ready() -> void:
	_tab = start_tab
	var modal := UiKit.modal(Vector2(720, 1100), Vector2(660, 960), "")
	var root: Panel = modal.root
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	size = Vector2(720, 1100)
	add_child(root)
	_body = modal.body
	var footer: VBoxContainer = modal.footer
	var head := modal.root.get_child(0).get_child(0) as VBoxContainer
	head.add_child(UiKit.label("WOZIG MANAGEMENT PORTAL", 26, UiKit.ACCENT, true))
	head.move_child(head.get_child(head.get_child_count() - 1), 0)
	var tabs := GridContainer.new()
	tabs.columns = 4
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	head.add_child(tabs)
	head.move_child(tabs, 1)
	for t in [["overview", "OVERVIEW"], ["cases", "CASES"], ["board", "BOARD"], ["finance", "FINANCE"],
			["properties", "HISTORY"], ["directory", "DIRECTORY"], ["work", "WORK ORDERS"], ["requests", "REQUESTS"]]:
		var b := UiKit.button(str(t[1]), 15, 46)
		b.pressed.connect(func():
			_tab = str(t[0])
			_render())
		tabs.add_child(b)
	var close := UiKit.button("CLOSE", 26, 66)
	close.pressed.connect(func(): closed.emit())
	footer.add_child(close)
	footer.add_child(UiKit.label("Community management powered by Wozig", 14, UiKit.MUTED, true))
	_render()


func _render() -> void:
	for child in _body.get_children():
		child.queue_free()
	match _tab:
		"overview":
			_overview()
		"cases":
			_cases()
		"properties":
			_properties()
		"board":
			_board()
		"finance":
			_finance()
		"directory":
			_directory()
		"work":
			_work_orders()
		"requests":
			_requests()


func _overview() -> void:
	var stats: Dictionary = GameState.stats
	_body.add_child(UiKit.label("DAY %d · %s · %s" % [GameState.day, GameState.weekday_name(), GameState.season_name()], 22, UiKit.MUTED))
	_body.add_child(UiKit.label("Treasury  $%s" % _money(int(stats.get("budget", 0))), 30))
	_body.add_child(UiKit.label("Community  %d" % int(stats.get("happiness", 0)), 26))
	_body.add_child(UiKit.label("Authority  %d" % int(stats.get("power", 0)), 26))
	_body.add_child(UiKit.label("Board mood  %s    Counsel  %s" % [sim.board.outlook(sim.politics, GameState.stats, GameState.day), sim.board.counsel_mood(sim.politics)], 22, UiKit.ACCENT))
	_body.add_child(UiKit.label("Open cases  %d" % sim.open_case_count(), 24))
	var enforced := 0
	var cases := 0
	for g in sim.politics.enforce:
		enforced += int(sim.politics.enforce[g].enforced)
		cases += int(sim.politics.enforce[g].cases)
	_body.add_child(UiKit.label("Enforced %d of %d valid violations." % [enforced, cases], 20, UiKit.MUTED))
	_body.add_child(HSeparator.new())
	_body.add_child(UiKit.section("ENFORCEMENT BALANCE · %s" % sim.board.fairness_label(sim.politics).to_upper()))
	var names := {"friend": "Friends", "board": "Board insiders", "neutral": "Neutral", "critic": "Critics", "legal": "Litigious"}
	for row in sim.board.group_rates(sim.politics):
		var line := HBoxContainer.new()
		_body.add_child(line)
		var label := UiKit.label("%s  (%d cases)" % [str(names[row.group]), int(row.cases)], 17, UiKit.MUTED)
		label.custom_minimum_size = Vector2(250, 0)
		line.add_child(label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.value = float(row.rate) * 100.0
		bar.custom_minimum_size = Vector2(0, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(bar)
	_body.add_child(UiKit.label("Share of valid violations enforced against each group. Big gaps invite lawsuits.", 15, UiKit.MUTED))
	var warning: String = sim.board.counsel_warning(sim.politics)
	if warning != "":
		_body.add_child(HSeparator.new())
		_body.add_child(UiKit.section("LEGAL COUNSEL"))
		_body.add_child(UiKit.label("\"%s\"" % warning, 22, UiKit.BAD))


## Open cases grouped by what the player has to do next, not as a spreadsheet.
func _cases() -> void:
	var groups := {"ready": [], "cure": [], "hearing": [], "disputed": [], "fined": []}
	for house in sim.cases:
		var record: Dictionary = sim.cases[house]
		var state := str(record.get("state", ""))
		if not state in sim.OPEN_STATES:
			continue
		var h := int(house)
		if sim.assignments.has(h) and str(sim.assignments[h].get("kind", "")) == "reinspect" and not h in sim.completed:
			groups.ready.append([h, "reinspect today"])
		elif state == "hearing":
			groups.hearing.append([h, "hearing day %d" % int(record.get("hearing_day", 0))])
		elif state == "disputed":
			groups.disputed.append([h, "owner disputes"])
		elif state == "fined":
			groups.fined.append([h, "fined · cure by day %d" % int(record.get("cure_due", 0))])
		else:
			var left := maxi(int(record.get("cure_due", 0)) - GameState.day, 0)
			groups.cure.append([h, "%d day%s to cure" % [left, "" if left == 1 else "s"]])
	var total := 0
	for key in [["ready", "READY FOR REINSPECTION"], ["cure", "AWAITING CURE"], ["hearing", "WAITING FOR HEARING"],
			["disputed", "DISPUTED"], ["fined", "FINED"]]:
		var rows: Array = groups[key[0]]
		if rows.is_empty():
			continue
		total += rows.size()
		_body.add_child(UiKit.section("%s · %d" % [str(key[1]), rows.size()]))
		for row in rows:
			_body.add_child(UiKit.label("%s — %s" % [street.lot_address(int(row[0])), str(row[1])], 21))
	if total == 0:
		_body.add_child(UiKit.label("No open cases. Enjoy it while it lasts.", 22, UiKit.MUTED))


func _properties() -> void:
	var list: Array = []
	for house in sim.properties:
		var p: Dictionary = sim.properties[house]
		if int(p.get("repeat_count", 0)) > 0 or (p.get("history", []) as Array).size() > 0:
			list.append(int(house))
	list.sort_custom(func(a, b): return int(sim.properties[a].repeat_count) > int(sim.properties[b].repeat_count))
	if list.is_empty():
		_body.add_child(UiKit.label("No violation history yet.", 22, UiKit.MUTED))
	for house in list.slice(0, 40):
		var p: Dictionary = sim.properties[house]
		_body.add_child(UiKit.label("%s" % street.lot_address(house), 21))
		_body.add_child(UiKit.label("%s · %s · offenses %d" % [str(p.owner), Residents.relationship_label(int(p.relationship)), int(p.repeat_count)], 16, UiKit.MUTED))


func _board() -> void:
	for i in Board.ROLES.size():
		var role: Dictionary = Board.member(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_body.add_child(row)
		var initials := ""
		for part in str(role.name).split(" ").slice(0, 2):
			initials += str(part).left(1)
		row.add_child(UiKit.avatar(role.color, initials, 60.0))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(UiKit.label("%s · %s" % [str(role.name), str(role.role)], 21))
		col.add_child(UiKit.label(str(role.temperament), 16, UiKit.MUTED))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.value = int(sim.politics.board[i].support)
		bar.custom_minimum_size = Vector2(0, 14)
		col.add_child(bar)


static func _money(points: int) -> String:
	var dollars := points * 690
	var s := str(dollars)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


func _finance() -> void:
	_body.add_child(UiKit.label("Insurance premium level  %d / 3" % int(sim.premium), 20, UiKit.MUTED))
	var total := 0
	for entry in sim.ledger:
		total += int(entry.dollars)
	_body.add_child(UiKit.label("Treasury  $%s" % _money(int(GameState.stats.get("budget", 0))), 30))
	_body.add_child(UiKit.label("Net recorded  %s$%s" % ["+" if total >= 0 else "-", _money_abs(total)], 20, UiKit.GOOD if total >= 0 else UiKit.BAD))
	_body.add_child(HSeparator.new())
	if sim.ledger.is_empty():
		_body.add_child(UiKit.label("No transactions yet.", 20, UiKit.MUTED))
	var recent: Array = sim.ledger.duplicate()
	recent.reverse()
	for entry in recent.slice(0, 40):
		var amount := int(entry.dollars)
		_body.add_child(UiKit.label("Day %d · %s   %s$%s" % [int(entry.day), str(entry.label), "+" if amount >= 0 else "-", _money_abs(amount)],
				18, UiKit.GOOD if amount >= 0 else UiKit.BAD))


func _directory() -> void:
	var ids: Array = sim.properties.keys()
	ids.sort_custom(func(a, b): return street.lot_address(int(a)) < street.lot_address(int(b)))
	for house in ids:
		var p: Dictionary = sim.properties[house]
		var traits: Array = p.get("traits", [])
		var blurb := str(Residents.TRAIT_BLURBS.get(traits[0], "")) if not traits.is_empty() else ""
		_body.add_child(UiKit.label("%s · %s" % [street.lot_address(int(house)), str(p.owner)], 19))
		_body.add_child(UiKit.label("%s · %s" % [Residents.relationship_label(int(p.relationship)), blurb], 14, UiKit.MUTED))


func _work_orders() -> void:
	_body.add_child(UiKit.section("VENDORS"))
	for key in sim.vendors:
		var q: int = int(sim.vendors[key])
		_body.add_child(UiKit.label("%s  %s" % [str(key).capitalize(), "★".repeat(q) + "☆".repeat(5 - q)], 20, UiKit.GOOD if q >= 3 else UiKit.BAD))
	_body.add_child(UiKit.section("WORK ORDERS"))
	if sim.projects.is_empty():
		_body.add_child(UiKit.label("No active work orders. Approve a vendor bid or community project to start one.", 20, UiKit.MUTED))
	for project in sim.projects:
		_body.add_child(UiKit.label("%s" % str(project.get("name", "Project")), 22))
		_body.add_child(UiKit.label("%d day(s) remaining" % int(project.get("days", 0)), 16, UiKit.MUTED))


func _requests() -> void:
	if sim.agenda_log.is_empty():
		_body.add_child(UiKit.label("No board agenda decisions yet.", 20, UiKit.MUTED))
	var recent: Array = sim.agenda_log.duplicate()
	recent.reverse()
	for entry in recent:
		_body.add_child(UiKit.label("Day %d · %s" % [int(entry.day), str(entry.who)], 19))
		_body.add_child(UiKit.label("Decision: %s" % str(entry.choice), 15, UiKit.MUTED))


static func _money_abs(dollars: int) -> String:
	var s := str(absi(dollars))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out
