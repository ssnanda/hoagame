extends "res://tools/video/video_lib.gd"

func _ready() -> void:
	await boot(7771, false, "VIDEO 00", "PIPELINE TEST")
	var p0 := 0
	for i in 600:
		await get_tree().process_frame
		p0 += 1
	print("PROCESS FRAMES ", p0, " DRAWN ", Engine.get_frames_drawn())
	get_tree().quit()
