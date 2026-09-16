extends SceneTree
## Build SpriteFrames for the full-screen player/Boss violin-pull sequence.

func _init() -> void:
	var sprite_frames := SpriteFrames.new()
	_add_animation(sprite_frames, "pull_loop", 24.0, true, 0, 9)
	_add_animation(sprite_frames, "pull_once", 24.0, false, 0, 48)
	if sprite_frames.get_frame_count("pull_loop") != 10 or sprite_frames.get_frame_count("pull_once") != 49:
		push_error("Finisher pull frames are missing or not imported; resource was not saved.")
		quit(1)
		return
	var error := ResourceSaver.save(sprite_frames, "res://art/character/animations/finisher_pull_frames.tres")
	print("finisher pull frames saved: ", error,
		" loop=", sprite_frames.get_frame_count("pull_loop"),
		" once=", sprite_frames.get_frame_count("pull_once"))
	quit()


func _add_animation(sprite_frames: SpriteFrames, name: String, fps: float, loop: bool, first: int, last: int) -> void:
	sprite_frames.add_animation(name)
	sprite_frames.set_animation_speed(name, fps)
	sprite_frames.set_animation_loop(name, loop)
	for index in range(first, last + 1):
		var texture := load("res://art/character/animations/finisher_pull/%03d.png" % index) as Texture2D
		if texture:
			sprite_frames.add_frame(name, texture)
