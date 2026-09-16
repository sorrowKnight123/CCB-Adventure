extends SceneTree
## 工具：把 art/level/3/Plant Animations 的序列帧生成 SpriteFrames .tres（每类一个）。
## 特殊：PlantJump（jump 动画）+ PlantJump2（idle 动画）合并为弹跳植物双动画 frames；
##       其余类生成单一动画（动画名 "anim"，循环）。
## fps 按帧数估算（动画总时长约 2.5-3s；弹跳 jump 用 30fps 快动作）。
## 用法：godot --headless --path ccb-adventure --script res://tools/build_plant_frames.gd

const BASE := "res://art/level/3/Plant Animations/"

# 目录名 → 输出名、动画配置（name, fps, loop）
var CONFIGS := {
	"BlueFlower1": {"out": "BlueFlower1", "fps": 24.0},
	"BlueFlower2": {"out": "BlueFlower2", "fps": 24.0},
	"Plant 1": {"out": "Plant1", "fps": 30.0},
	"Plant 2": {"out": "Plant2", "fps": 30.0},
	"Plant 3": {"out": "Plant3", "fps": 30.0},
	"Plant 4": {"out": "Plant4", "fps": 24.0},
	"Plant 5": {"out": "Plant5", "fps": 24.0},
	"Plant 6": {"out": "Plant6", "fps": 24.0},
	"Plant 7": {"out": "Plant7", "fps": 24.0},
	"Plant 8 Poison": {"out": "Plant8_Poison", "fps": 12.0},
	"Plant Wind 1": {"out": "PlantWind1", "fps": 12.0},
}


func _init() -> void:
	# 1) 单动画类
	for dir_name in CONFIGS:
		var cfg: Dictionary = CONFIGS[dir_name]
		var frames := _build_frames_from_dir(dir_name, [{"name": "anim", "fps": cfg["fps"], "loop": true}])
		if frames == null:
			continue
		_save(frames, BASE + dir_name + "/" + cfg["out"] + "_frames.tres")

	# 2) 弹跳植物：PlantJump2 目录 = idle；PlantJump 目录 = jump
	var jump_frames := _build_frames_from_dir("PlantJump", [{"name": "jump", "fps": 30.0, "loop": false}])
	var idle_frames := _build_frames_from_dir("PlantJump2", [{"name": "idle", "fps": 8.0, "loop": true}])
	if jump_frames != null and idle_frames != null:
		var sf := SpriteFrames.new()
		sf.add_animation("idle")
		sf.add_animation("jump")
		sf.set_animation_speed("idle", 8.0)
		sf.set_animation_loop("idle", true)
		sf.set_animation_speed("jump", 30.0)
		sf.set_animation_loop("jump", false)
		for i in idle_frames.get_frame_count("idle"):
			sf.add_frame("idle", idle_frames.get_frame_texture("idle", i))
		for i in jump_frames.get_frame_count("jump"):
			sf.add_frame("jump", jump_frames.get_frame_texture("jump", i))
		_save(sf, BASE + "PlantJump2/JumpPlant_frames.tres")
	print("植物 SpriteFrames 生成完成")
	quit()


func _build_frames_from_dir(dir_name: String, anims: Array) -> SpriteFrames:
	var dir := DirAccess.open(BASE + dir_name)
	if dir == null:
		print("[ERR] 打不开目录 ", dir_name)
		return null
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".png") and not f.ends_with(".import"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	if files.is_empty():
		print("[ERR] ", dir_name, " 无 png")
		return null
	var sf := SpriteFrames.new()
	for a in anims:
		sf.add_animation(a["name"])
		sf.set_animation_speed(a["name"], a["fps"])
		sf.set_animation_loop(a["name"], a["loop"])
	for file in files:
		var tex := load(BASE + dir_name + "/" + file) as Texture2D
		if tex == null:
			print("[ERR] 加载失败 ", file)
			continue
		sf.add_frame(anims[0]["name"], tex)
	print("  ", dir_name, ": ", files.size(), " 帧 → ", anims[0]["name"])
	return sf


func _save(sf: SpriteFrames, path: String) -> void:
	var err := ResourceSaver.save(sf, path)
	print("  ", path, " err=", err)
