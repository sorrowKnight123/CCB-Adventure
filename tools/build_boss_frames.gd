extends SceneTree
## 工具：把 art/enemies/boss 下的 PNG 序列生成 SpriteFrames。
## idle 循环动画：24fps；其余 Boss 动画为单次动画：24fps。
## 用法：godot --headless --path ccb-adventure --script res://tools/build_boss_frames.gd


func _init() -> void:
	var sf := SpriteFrames.new()
	_add_anim(sf, "idle", "res://art/enemies/boss/idle", 24.0, true)
	_add_anim(sf, "phase_change", "res://art/enemies/boss/phase_change", 24.0, false)
	_add_anim(sf, "jump", "res://art/enemies/boss/jump", 24.0, false)
	_add_anim(sf, "note_cast", "res://art/enemies/boss/note_cast", 24.0, false)
	_add_anim(sf, "slam_right", "res://art/enemies/boss/slam_right", 24.0, false)
	_add_anim(sf, "slam_left", "res://art/enemies/boss/slam_left", 24.0, false)
	_add_anim(sf, "finisher_fall", "res://art/enemies/boss/finisher_fall", 24.0, false)
	var err := ResourceSaver.save(sf, "res://art/enemies/boss/moss_boss_frames.tres")
	print("保存 err=", err, "  idle帧=", sf.get_frame_count("idle"))
	quit()


func _add_anim(sf: SpriteFrames, name: String, dir_path: String, fps: float, loop: bool) -> void:
	sf.add_animation(name)
	sf.set_animation_speed(name, fps)
	sf.set_animation_loop(name, loop)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		print("[ERR] 打不开 ", dir_path)
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".png") and not f.ends_with(".import"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	for file in files:
		var tex := load(dir_path + "/" + file) as Texture2D
		if tex:
			sf.add_frame(name, tex)
	print(name, ": ", files.size(), " 帧")
