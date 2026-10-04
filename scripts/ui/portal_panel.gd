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


func setup(simulation, street_node) -> void:
	sim = simulation
	street = street_node


func _ready() -> void:
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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	head.add_child(tabs)
	head.move_child(tabs, 1)
	for t in [["overview", "OVERVIEW"], ["cases", "CASES"], ["properties", "HOMES"], ["board", "BOARD"]]:
		var b := UiKit.button(str(t[1]), 18, 52)
		b.pressed.connect(func():
			_tab = str(t[0])
			_render())
		tabs.add_child(b)
	var close := UiKit.button("CLOSE", 26, 66)
	close.pressed.connect(func(): closed.emit())
	footer.add_child(close)
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


func _overview() -> void:
	var stats: Dictionary = GameState.stats
	_body.add_child(UiKit.label("DAY %d · %s · %s" % [GameState.day, GameState.weekday_name(), GameState.season_name()], 22, UiKit.MUTED))
	_body.add_child(UiKit.label("Treasury  $%s" % _money(int(stats.get("budget", 0))), 30))
	_body.add_child(UiKit.label("Community  %d" % int(stats.get("happiness", 0)), 26))
	_body.add_child(UiKit.label("Authority  %d" % int(stats.get("power", 0)), 26))
	_body.add_child(UiKit.label("Board support  %d%%    Legal risk  %d%%" % [sim.board_support(), sim.legal_risk()], 24, UiKit.ACCENT))
	_body.add_child(UiKit.label("Open cases  %d" % sim.open_case_count(), 24))
	var enforced := 0
	var cases := 0
	for g in sim.politics.enforce:
		enforced += int(sim.politics.enforce[g].enforced)
		cases += int(sim.politics.enforce[g].cases)
	_body.add_child(UiKit.label("Enforced %d of %d valid violations." % [enforced, cases], 20, UiKit.MUTED))
	var warning: String = sim.board.counsel_warning(sim.politics)
	if warning != "":
		_body.add_child(HSeparator.new())
		_body.add_child(UiKit.section("LEGAL COUNSEL"))
		_body.add_child(UiKit.label("\"%s\"" % warning, 22, UiKit.BAD))


func _cases() -> void:
	var rows := 0
	for house in sim.cases:
		var record: Dictionary = sim.cases[house]
		var state := str(record.get("state", ""))
		if not state in sim.OPEN_STATES:
			continue
		rows += 1
		var due := ""
		if state in ["warning", "extended", "fined"]:
			due = " · due day %d" % int(record.get("cure_due", 0))
		elif state == "hearing":
			due = " · hearing day %d" % int(record.get("hearing_day", 0))
		_body.add_child(UiKit.label("%s — %s%s" % [street.lot_address(int(house)), state.to_upper(), due], 21))
	if rows == 0:
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
