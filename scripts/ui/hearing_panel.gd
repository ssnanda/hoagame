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
	body.add_child(HSeparator.new())
	body.add_child(UiKit.section("THE FILE"))
	for label in data.get("violations", []):
		body.add_child(UiKit.label("• %s" % str(label), 22))
	var quality := int(data.get("quality", 0))
	body.add_child(UiKit.label("Evidence quality %d%%" % quality, 19, UiKit.GOOD if quality >= 60 else UiKit.BAD))
	body.add_child(UiKit.section("STAFF RECOMMENDATION"))
	var rec := str(data.get("recommendation", "warning"))
	body.add_child(UiKit.label({"fine": "Fine ($%d)" % int(data.get("fine_amount", 100)), "warning": "Written warning", "dismiss": "Dismiss the case"}[rec], 24, UiKit.ACCENT))
	_present = UiKit.check("Present the photographs to the board", 22)
	_present.button_pressed = quality > 0
	body.add_child(_present)
	footer.add_child(UiKit.section("YOUR RECOMMENDATION TO THE BOARD"))
	for choice in [["dismiss", "DISMISS"], ["warning", "WARNING"], ["fine", "FINE"]]:
		var btn := UiKit.button(str(choice[1]) + ("   (staff)" if str(choice[0]) == rec else ""), 26, 66)
		btn.pressed.connect(func(): decided.emit(str(choice[0]), _present.button_pressed))
		footer.add_child(btn)
