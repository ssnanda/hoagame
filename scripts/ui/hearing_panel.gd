extends Panel
## Board hearing: the homeowner's argument, the file, staff's view. You make the
## recommendation; the board votes.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal decided(recommendation: String, present_evidence: bool)

var data: Dictionary = {}
var _present: CheckButton


func setup(info: Dictionary) -> void:
	data = info


func _ready() -> void:
	var modal := UiKit.modal(Vector2(720, 1100), Vector2(640, 900), "BOARD HEARING")
	var root: Panel = modal.root
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	size = Vector2(720, 1100)
	add_child(root)
	var body: VBoxContainer = modal.body
	var footer: VBoxContainer = modal.footer
	body.add_child(UiKit.label(str(data.get("address", "")), 28, UiKit.INK, true))
	body.add_child(UiKit.section("HOMEOWNER · %s (%s)" % [str(data.get("owner", "")), str(data.get("relationship", ""))]))
	body.add_child(UiKit.label("\"%s\"" % str(data.get("argument", "")), 24, UiKit.INK))
	if str(data.get("twist", "")) != "":
		body.add_child(UiKit.section("SURPRISE AT THE HEARING"))
		body.add_child(UiKit.label(str(data.twist), 21, UiKit.BAD))
	body.add_child(HSeparator.new())
	body.add_child(UiKit.section("THE FILE"))
	var rules: Array = data.get("rules", [])
	var labels: Array = data.get("violations", [])
	for i in labels.size():
		body.add_child(UiKit.label("• %s" % str(labels[i]), 22))
		if i < rules.size() and str(rules[i]) != "":
			body.add_child(UiKit.label("Rule: %s" % str(rules[i]), 15, UiKit.MUTED))
	var quality := int(data.get("quality", 0))
	body.add_child(UiKit.label("Evidence quality %d%%" % quality, 19, UiKit.GOOD if quality >= 60 else UiKit.BAD))
	body.add_child(UiKit.section("STAFF RECOMMENDATION"))
	var rec := str(data.get("recommendation", "warning"))
	body.add_child(UiKit.label({"fine": "Fine ($%d)" % int(data.get("fine_amount", 100)), "warning": "Written warning", "dismiss": "Dismiss the case"}[rec], 24, UiKit.ACCENT))
	body.add_child(UiKit.section("ON THE DAIS"))
	body.add_child(UiKit.label(", ".join(data.get("board", [])), 15, UiKit.MUTED))
	_present = UiKit.check("Present the photographs to the board", 22)
	_present.button_pressed = quality > 0
	body.add_child(_present)
	footer.add_child(UiKit.section("YOUR RECOMMENDATION TO THE BOARD"))
	for choice in [["dismiss", "DISMISS"], ["warning", "WARNING"], ["fine", "FINE"]]:
		var btn := UiKit.button(str(choice[1]) + ("   (staff)" if str(choice[0]) == rec else ""), 26, 66)
		btn.pressed.connect(func(): decided.emit(str(choice[0]), _present.button_pressed))
		footer.add_child(btn)
