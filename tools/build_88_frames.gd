extends SceneTree
## 工具：生成 88 一阶段的 SpriteFrames（`art/enemies/boss88/88_frames.tres`）。
##
## 两种模式，**脚本不用改**：
##   ① 骨架版 —— `art/enemies/boss88/<动画名>/` 里还没有 PNG 时，
##      用占位贴图 `88_placeholder.png` 铺满**设计帧数**，循环与否也按设计来。
##      这样动画时长、命中帧序号、手感全都能先跑通。
##   ② 成品版 —— 把真帧按序号命名（`000.png`…）丢进同名目录，重跑本工具即可覆盖。
##
## 帧数来自《88_Boss_技术实现与美术资源清单.md》§5 的四招逐段帧表与 §11 的动画清单。
##
## 用法：godot --headless --path ccb-adventure --script res://tools/build_88_frames.gd

const 贴图根 := "res://art/enemies/boss88"
const 占位贴图 := "res://art/enemies/boss88/88_placeholder.png"
const 输出 := "res://art/enemies/boss88/88_frames.tres"
const FPS := 24.0

## 名 / 设计帧数 / 是否循环。帧数与帧表严格对应，改帧表要同步改这里。
const 动画表: Array[Dictionary] = [
	{"名": "idle",       "帧": 24, "循环": true},
	{"名": "walk",       "帧": 16, "循环": true},
	{"名": "intro",      "帧": 36, "循环": false},
	{"名": "claw_1",     "帧": 26, "循环": false},   # 7 前摇 + 2 悬停 + 3 出手 + 后摇
	{"名": "claw_2",     "帧": 26, "循环": false},
	{"名": "claw_3",     "帧": 32, "循环": false},   # 8 + 4 + 2 + 14 后摇
	{"名": "thrust",     "帧": 26, "循环": false},   # 11 + 3 + 4 + 12 后摇
	{"名": "blink_out",  "帧": 10, "循环": false},
	{"名": "blink_in",   "帧": 12, "循环": false},
	{"名": "staff_cast", "帧": 18, "循环": false},   # 举指挥棒 17 帧 + 1
	{"名": "hurt",       "帧": 6,  "循环": false},
	{"名": "knocked",    "帧": 12, "循环": false},
	{"名": "weakened",   "帧": 32, "循环": true},
]


func _init() -> void:
	var sf := SpriteFrames.new()
	# SpriteFrames 自带一个 "default"，清掉免得留垃圾
	if sf.has_animation("default"):
		sf.remove_animation("default")

	var 占位 := load(占位贴图) as Texture2D
	if 占位 == null:
		print("[ERR] 找不到占位贴图 ", 占位贴图)
		quit(1)
		return

	var 有真帧 := 0
	for 条 in 动画表:
		var 名: String = 条["名"]
		var 帧数: int = 条["帧"]
		var 循环: bool = 条["循环"]
		sf.add_animation(名)
		sf.set_animation_speed(名, FPS)
		sf.set_animation_loop(名, 循环)

		var 真帧 := _扫目录(贴图根 + "/" + 名)
		if 真帧.is_empty():
			for _i in 帧数:
				sf.add_frame(名, 占位)
			print("  %-11s 骨架版 %2d 帧（占位）  循环=%s" % [名, 帧数, str(循环)])
		else:
			有真帧 += 1
			for t in 真帧:
				sf.add_frame(名, t)
			var 备注 := "" if 真帧.size() == 帧数 else "  ⚠️ 与设计帧数 %d 不一致" % 帧数
			print("  %-11s 成品版 %2d 帧（真帧）  循环=%s%s" % [名, 真帧.size(), str(循环), 备注])

	var err := ResourceSaver.save(sf, 输出)
	print("保存 err=", err, "  → ", 输出)
	print("共 %d 个动画，其中 %d 个已用真帧，其余为占位。" % [动画表.size(), 有真帧])
	quit(0)


## 扫一个目录里的 PNG，按文件名排序（000.png, 001.png …）
func _扫目录(路径: String) -> Array[Texture2D]:
	var 出: Array[Texture2D] = []
	var d := DirAccess.open(路径)
	if d == null:
		return 出
	var 文件: Array[String] = []
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".png") and not f.ends_with(".import"):
			文件.append(f)
		f = d.get_next()
	文件.sort()
	for 名 in 文件:
		var t := load(路径 + "/" + 名) as Texture2D
		if t != null:
			出.append(t)
	return 出
