extends SceneTree
## 一次性工具：生成蝙蝠 SpriteFrames（bat_frames.tres）。
## 帧格 64×64 单行切帧；动画 fps/循环在下面配置，可在编辑器再调。
## 用法：godot --headless --path ccb-adventure --script res://tools/build_bat_frames.gd


func _init() -> void:
	var dir := "res://art/enemy/level 1/Bat with VFX/"
	var anims := {
		"idle_fly": {"file": "Bat-IdleFly.png", "frames": 9, "fps": 10, "loop": true},
		"run": {"file": "Bat-Run.png", "frames": 8, "fps": 10, "loop": true},
		"sleep": {"file": "Bat-Sleep.png", "frames": 3, "fps": 3, "loop": true},
		"wakeup": {"file": "Bat-WakeUp.png", "frames": 16, "fps": 12, "loop": false},
		"attack1": {"file": "Bat-Attack1.png", "frames": 8, "fps": 12, "loop": false},
		"attack2": {"file": "Bat-Attack2.png", "frames": 11, "fps": 12, "loop": false},
		"hurt": {"file": "Bat-Hurt.png", "frames": 5, "fps": 12, "loop": false},
		"die": {"file": "Bat-Die.png", "frames": 12, "fps": 10, "loop": false},
	}
	var sf := SpriteFrames.new()
	for name in anims:
		var cfg: Dictionary = anims[name]
		var tex: Texture2D = load(dir + str(cfg["file"]))
		if tex == null:
			print("[ERR] 无法加载 ", cfg["file"])
			quit(1)
			return
		sf.add_animation(name)
		sf.set_animation_loop(name, cfg["loop"])
		sf.set_animation_speed(name, cfg["fps"])
		for i in int(cfg["frames"]):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 64, 0, 64, 64)
			sf.add_frame(name, at)
	var err := ResourceSaver.save(sf, dir + "bat_frames.tres")
	print("bat_frames.tres 保存 err=", err)
	quit(0 if err == OK else 1)
