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

## 名 / 设计帧数 / 是否循环 / [挥击帧 / 挥击倍速 / 后摇倍速]。帧数与帧表严格对应，改帧表要同步改这里。
##
## **挥击帧 / 挥击倍速 / 后摇倍速**（2026-09-21 加）：按**每帧 duration** 给一段动画内部
## 分两档速度，**不动帧数、不动命中帧序号、不动位移**：
##   · `挥击帧` = 命中帧序号（含这一帧）；`0..挥击帧` 走 `挥击倍速`，其余走 `后摇倍速`
##   · 倍速是**速度**倍速：1.5 = 那一段快 1.5 倍（每帧 duration = 1/1.5，时长 = 原/1.5）
##     ⚠️ 作者说的"后摇缩短到 0.5 倍"是**时长**倍速 → 这里填速度倍速 **2.0**
##     （填 0.5 会得到 duration 2.0 = 后摇反而慢一倍，实测踩过）
## 为什么要它：作者实测"挥爪有点慢，挥击 1.5 倍速、后摇缩短到 0.5 倍"。
## 用 duration 而不是砍帧数，是因为**命中帧序号被设计钉死**（10 / 10 / 16），
## 而 `_等到帧()` 按帧号等、`_等动画结束()` 等 `animation_finished` —— 两者都自动跟着走。
const 动画表: Array[Dictionary] = [
	{"名": "idle",       "帧": 24, "循环": true},
	{"名": "walk",       "帧": 16, "循环": true},
	{"名": "intro",      "帧": 36, "循环": false},
	# ⚠️ 爪击三段的**后摇**（命中帧之后的帧数）2026-09-21 两次收紧：
	#    ① 帧数减半 16 → 8 帧（0.67s → 0.33s）。作者原话："有问题的是后摇，所以三连击
	#       每段间隔特别大。后摇减半。"
	#    ② 帧数不动，**duration 再减半** + 挥击段 duration × 1/1.5。作者原话："挥击
	#       1.5 倍速，然后后摇也缩短到 0.5 倍。实测手感，后摇还是有点点长。"
	#    现在 claw_1/2 挥击 0.31s、后摇 0.15s；claw_3 挥击 0.47s、后摇 0.15s。
	{"名": "claw_1",     "帧": 18, "循环": false, "挥击帧": 10, "挥击倍速": 1.5, "后摇倍速": 2.0},
	{"名": "claw_2",     "帧": 18, "循环": false, "挥击帧": 10, "挥击倍速": 1.5, "后摇倍速": 2.0},
	{"名": "claw_3",     "帧": 24, "循环": false, "挥击帧": 16, "挥击倍速": 1.5, "后摇倍速": 2.0},
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

		# 每帧 duration 分两档（挥击段 / 后摇段）。帧数没变，变的只是"每帧停多久"。
		# ⚠️ duration 是 `add_frame()` 的参数（Godot 4 的 SpriteFrames **没有**
		#    `set_frame_duration()` —— 实测调用会报 "Nonexistent function"）。
		var 挥击帧: int = int(条.get("挥击帧", -1))
		var 挥击倍速: float = float(条.get("挥击倍速", 1.0))
		var 后摇倍速: float = float(条.get("后摇倍速", 1.0))

		var 真帧 := _扫目录(贴图根 + "/" + 名)
		if 真帧.is_empty():
			for i in 帧数:
				sf.add_frame(名, 占位, _帧时长(i, 挥击帧, 挥击倍速, 后摇倍速))
			print("  %-11s 骨架版 %2d 帧（占位）  循环=%s" % [名, 帧数, str(循环)])
		else:
			有真帧 += 1
			for i in 真帧.size():
				sf.add_frame(名, 真帧[i], _帧时长(i, 挥击帧, 挥击倍速, 后摇倍速))
			var 备注 := "" if 真帧.size() == 帧数 else "  ⚠️ 与设计帧数 %d 不一致" % 帧数
			print("  %-11s 成品版 %2d 帧（真帧）  循环=%s%s" % [名, 真帧.size(), str(循环), 备注])

		if 挥击帧 >= 0:
			var 挥击秒 := float(挥击帧 + 1) / 挥击倍速 / FPS
			var 后摇秒 := float(sf.get_frame_count(名) - 挥击帧 - 1) / 后摇倍速 / FPS
			print("             挥击 %d 帧 ÷%.1f = %.2fs，后摇 %d 帧 ÷%.1f = %.2fs"
				% [挥击帧 + 1, 挥击倍速, 挥击秒,
				   sf.get_frame_count(名) - 挥击帧 - 1, 后摇倍速, 后摇秒])

	var err := ResourceSaver.save(sf, 输出)
	print("保存 err=", err, "  → ", 输出)
	print("共 %d 个动画，其中 %d 个已用真帧，其余为占位。" % [动画表.size(), 有真帧])
	quit(0)


## 第 i 帧的 duration（1.0 = 按 FPS 正常速度）。挥击段与后摇段分两档。
## 倍速是**速度**倍速：1.5 → duration = 1/1.5（那一帧停得短 → 整段更快）。
func _帧时长(i: int, 挥击帧: int, 挥击倍速: float, 后摇倍速: float) -> float:
	if 挥击帧 < 0:
		return 1.0
	return 1.0 / (挥击倍速 if i <= 挥击帧 else 后摇倍速)


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
