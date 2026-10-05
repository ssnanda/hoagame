extends Panel
## Reinspection: what you found when the cure period ended, and what to do about it.

const UiKit := preload("res://scripts/ui/ui_kit.gd")

signal chose(choice: String)
signal closed

const RESULT_TEXT := {
	"fixed": ["FIXED", "Everything checks out. The homeowner did the work."],
	"partial": ["PARTLY FIXED", "Some progress, but part of the problem is still there."],
	"unchanged": ["UNCHANGED", "Nothing has been done. The notice was ignored."],
	"worse": ["WORSE", "It has deteriorated since the notice. Impressive, in a way."],
}
const CHOICES := [["close", "CLOSE CASE"], ["extend", "EXTEND 2 DAYS"], ["hearing", "SCHEDULE HEARING"], ["fine", "ISSUE FINE"]]

var data: Dictionary = {}


func setup(info: Dictionary) -> void:
	data = info


func _ready() -> void:
	var modal := UiKit.modal(Vector2(720, 1100), Vector2(620, 860), "REINSPECTION")
	var root: Panel = modal.root
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	size = Vector2(720, 1100)
	add_child(root)
	var body: VBoxContainer = modal.body
	var footer: VBoxContainer = modal.footer
	var result := str(data.get("result", "unchanged"))
	var text: Array = RESULT_TEXT[result]
	body.add_child(UiKit.label(str(data.get("address", "")), 30, UiKit.INK, true))
	body.add_child(UiKit.label("%s · %s" % [str(data.get("owner", "")), str(data.get("relationship", ""))], 20, UiKit.ACCENT, true))
	body.add_child(UiKit.section("CITED"))
	for label in data.get("labels", []):
		body.add_child(UiKit.label("• %s" % str(label), 22))
	body.add_child(HSeparator.new())
	body.add_child(UiKit.label(str(text[0]), 44, UiKit.GOOD if result == "fixed" else (UiKit.BAD if result in ["unchanged", "worse"] else UiKit.ACCENT), true))
	body.add_child(UiKit.label(str(text[1]), 24, UiKit.INK, true))
	var options: Dictionary = data.get("options", {})
	var reasons: Array = []
	for choice in CHOICES:
		var option: Dictionary = options.get(choice[0], {"enabled": true, "reason": ""})
		var btn := UiKit.button(str(choice[1]), 26, 70)
		btn.disabled = not bool(option.enabled)
		btn.pressed.connect(func(): chose.emit(str(choice[0])))
		footer.add_child(btn)
		if not bool(option.enabled) and str(option.reason) != "":
			reasons.append(str(option.reason))
	if not reasons.is_empty():
		footer.add_child(UiKit.label("\n".join(reasons), 16, UiKit.BAD))
	var back := UiKit.button("< BACK", 22, 64)
	back.pressed.connect(func(): closed.emit())
	footer.add_child(back)
