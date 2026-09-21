extends Node2D
## 工具（非 headless）：88 一阶段美术的**视觉验收**截图。
##
## 为什么必须是独立工具：headless 不渲染，体型与拖尾这类视觉改动它一个字都验不出来；
## 而自检只能断言数字（可视高、画布尺寸），"看起来对不对"只能靠眼睛看渲染结果。
## 换完 `art/enemies/boss88/<动画名>/` 里的 PNG 就跑一次这个。
##
## 运行：godot --path ccb-adventure res://tools/shot_88.tscn
##
## 出两类图（都存 user://）：
##   · 88_side_<动画>_f<帧>.png  —— 77 与 88 并排、暗背景、镜头拉近：看**体型是否等高**、看拖尾形状
##   · 88_lv_<动画>_f<帧>.png    —— 真实音乐厅关卡里：看拖尾在**真正的场景背景**上是否看得见
##
## ⚠️ 两处要点（踩过）：
##   1. 关卡里的 `Camera2D` 有 limit，**硬挪 global_position 会被夹回来** —— 只能改 zoom，
##      并且把 88 摆到玩家跟前（相机跟着玩家，所以这样一定框得到）。
##   2. 必须冻住双方的 `set_physics_process(false)` / `set_process(false)`，否则 AI 会自己
##      换动画、自己走位，拍到的不一定是设计里的命中帧。

const BOSS := preload("res://scenes/enemies/boss/Boss88Phase1.tscn")
const PLAYER := preload("res://scenes/player/Player.tscn")
const LEVEL := preload("res://scenes/levels/music_hall/4_1.tscn")

## 动画名 → 要拍的帧号。命中帧来自《技术实现与美术资源清单》§5：claw_1/2 = 10、claw_3 = 16。
const 要拍的 := {
	"idle": [0],
	"claw_1": [8, 10, 12, 16],
	"claw_2": [8, 10, 12, 16],
	"claw_3": [12, 16, 18, 22],
}

## 关卡内只拍命中帧附近，够看拖尾了
const 关卡内要拍的 := {
	"claw_1": [10, 12],
	"claw_2": [10, 12],
	"claw_3": [16, 18],
}


func _ready() -> void:
	await _拍并排()
	await _拍关卡内()
	print("[拍图] 全部完成")
	get_tree().quit(0)


# ──────────────────────────── ① 并排对比（暗背景，看体型与拖尾形状）────────────────────────────


func _拍并排() -> void:
	RenderingServer.set_default_clear_color(Color(0.07, 0.06, 0.09))
	var 台 := Node2D.new()
	add_child(台)

	# 77 与 88 的可视底边都在各自原点 +31.8（见 §5.5），所以 y 都摆 0 就是同一条地平线
	var 玩家 := PLAYER.instantiate() as Node2D
	玩家.position = Vector2(-120.0, 0.0)
	台.add_child(玩家)
	await get_tree().physics_frame

	var boss := BOSS.instantiate() as Node2D
	boss.position = Vector2(140.0, 0.0)
	台.add_child(boss)
	await get_tree().physics_frame

	var 精灵 := boss.get_node_or_null("BossSprite") as AnimatedSprite2D
	if 精灵 == null:
		print("[拍图] !! 找不到 BossSprite，跳过并排")
		台.queue_free()
		return
	_冻住(boss)
	_冻住(玩家)
	print("[拍图] 77 scale=%s  88 scale=%s offset=%s"
		% [str((玩家.get_node("Sprite2D") as Sprite2D).scale), str(精灵.scale), str(精灵.offset)])

	var 相机 := Camera2D.new()
	相机.position = Vector2(14.0, -58.0)
	相机.zoom = Vector2(2.6, 2.6)
	台.add_child(相机)
	相机.make_current()

	await _逐帧拍(精灵, 要拍的, "88_side_%s_f%02d.png")
	台.queue_free()
	await get_tree().process_frame


# ──────────────────────────── ② 关卡内（真背景，看拖尾看不看得见）────────────────────────────


func _拍关卡内() -> void:
	var 关 := LEVEL.instantiate() as Node2D
	add_child(关)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var boss := 关.get_node_or_null("Boss88") as Node2D
	if boss == null:
		for n in 关.find_children("*", "Node2D", true, false):
			if n.get_node_or_null("BossSprite") != null:
				boss = n
				break
	var 玩家 := 关.get_node_or_null("Player") as Node2D
	if boss == null or 玩家 == null:
		print("[拍图] !! 关卡里缺 88 或 Player，跳过关卡内")
		关.queue_free()
		return
	var 精灵 := boss.get_node_or_null("BossSprite") as AnimatedSprite2D
	_冻住(boss)
	_冻住(玩家)

	# 相机不动位置（limit 会夹），把 88 摆到玩家跟前
	boss.global_position = 玩家.global_position + Vector2(110.0, 0.0)
	var 相机 := 关.get_node_or_null("Player/Camera2D") as Camera2D
	if 相机 != null:
		相机.zoom = Vector2(2.8, 2.8)
	print("[拍图] 关卡内：玩家 %s → 88 摆到 %s，相机 zoom=%s"
		% [str(玩家.global_position), str(boss.global_position), str(相机.zoom if 相机 else "无")])

	for 名 in ["UI", "DialogueUI", "对话层", "CanvasLayer"]:
		var u := 关.get_node_or_null(名)
		if u is CanvasItem:
			(u as CanvasItem).visible = false

	await _逐帧拍(精灵, 关卡内要拍的, "88_lv_%s_f%02d.png")
	关.queue_free()


# ──────────────────────────── 公共 ────────────────────────────


## 冻住一个角色：AI 会自己换动画/走位，不冻住就拍不到指定帧
func _冻住(节点: Node2D) -> void:
	节点.set_physics_process(false)
	节点.set_process(false)
	for c in 节点.get_children():
		if c is AnimatedSprite2D or c is Sprite2D:
			(c as Node).set_process(false)


func _逐帧拍(精灵: AnimatedSprite2D, 表: Dictionary, 模板: String) -> void:
	for 名 in 表:
		if not 精灵.sprite_frames.has_animation(名):
			print("[拍图] !! 没有动画 %s，跳过" % 名)
			continue
		for 帧 in 表[名]:
			if 帧 >= 精灵.sprite_frames.get_frame_count(名):
				print("[拍图] !! %s 只有 %d 帧，跳过第 %d 帧"
					% [名, 精灵.sprite_frames.get_frame_count(名), 帧])
				continue
			精灵.play(名)
			精灵.stop()
			精灵.animation = 名
			精灵.frame = 帧
			for _i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var 图 := get_viewport().get_texture().get_image()
			var 路 := "user://" + (模板 % [名, 帧])
			图.save_png(路)
			print("[拍图] %s 第 %d 帧 → %s" % [名, 帧, 路])
