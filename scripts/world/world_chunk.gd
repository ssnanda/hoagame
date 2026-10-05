extends Node2D
## One cached piece of the static world. Its commands are recorded once and then
## replayed by the renderer for free; `stale` chunks are redrawn lazily when they
## come near the camera (see world_view.gd).

var painter
var kind := ""
var arg = 0


func _draw() -> void:
	painter.draw_chunk(self, kind, arg)
