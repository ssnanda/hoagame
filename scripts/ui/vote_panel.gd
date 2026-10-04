extends Panel
## Board votes, member by member: hearings and the annual meeting.

const UiKit := preload("res://scripts/ui/ui_kit.gd")
const Board := preload("res://scripts/sim/board.gd")

signal closed

var title := ""
var summary: Array = []
var votes: Array = []
var button_text := "CONTINUE"


func setup(heading: String, summary_lines: Array, vote_list: Array, button := "CONTINUE") -> void:
	title = heading
	summary = summary_lines
	votes = vote_list
	button_text = button


func _ready() -> void:
	var modal := UiKit.modal(Vector2(720, 1100), Vector2(640, 880), title)
	var root: Panel = modal.root
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	size = Vector2(720, 1100)
	add_child(root)
	var body: VBoxContainer = modal.body
	for line in summary:
		body.add_child(UiKit.label(str(line), 24, UiKit.INK, true))
	body.add_child(HSeparator.new())
	for v in votes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var role: Dictionary = Board.member(int(v.index))
		var initials := ""
		for part in str(v.name).split(" ").slice(0, 2):
			initials += str(part).left(1)
		row.add_child(UiKit.avatar(role.color, initials))
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(UiKit.label("%s · %s — %s" % [str(v.name), str(v.role), "YES" if bool(v.yes) else "NO"], 20,
				UiKit.GOOD if bool(v.yes) else UiKit.BAD))
		text.add_child(UiKit.label("\"%s\"" % str(v.line), 17, UiKit.MUTED))
	var btn := UiKit.button(button_text, 30, 78)
	btn.pressed.connect(func(): closed.emit())
	modal.footer.add_child(btn)
