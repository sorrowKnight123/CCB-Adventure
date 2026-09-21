extends Node2D
## 临时探针（非 headless）：看二阶段的开场视觉 —— 视口锁定 + 两层背景 + 跳跳乐消失。
##
## 运行：godot --path . res://tests/_tmp_phase2_shot.tscn
## 截图存 user://phase2_shot.png

const LEVEL := preload("res://scenes/levels/music_hall/4_1.tscn")
const 区域中心 := Vector2(1340.0, 565.0)

var _lvl: Node2D = null
var _player: CharacterBody2D = null
var _chase: Node = null


func _ready() -> void:
	_lvl = LEVEL.instantiate()
	add_child(_lvl)
	_player = _lvl.get_node_or_null("Player")
	_chase = _lvl.get_node_or_null("追逐段")
	if _player == null or _chase == null:
		print("[拍图] 缺节点，退出")
		get_tree().quit(1)
		return

	# 进二阶段：视口锁到 phase_2_area、跳跳乐全消失、两层背景显示
	_chase.call("开始追逐")
	await _等帧(20)
	_chase.call("进入二阶段")
	await _等帧(150)          # 等镜头滑入收敛

	var 背景 := _lvl.get_node_or_null("二阶段背景") as Sprite2D
	if 背景 == null:
		print("[拍图] !! 找不到 二阶段背景 节点，退出")
		get_tree().quit(1)
		return
	print("[拍图] 二阶段背景 visible=%s  z=%d" % [str(背景.visible), 背景.z_index])
	print("[拍图] 区域矩形 = %s" % str(_chase.call("区域矩形")))
	var 相机 := _player.get_node_or_null("Camera2D") as Camera2D
	print("[拍图] 相机 global=%s top_level=%s" % [str(相机.global_position), str(相机.top_level)])

	# 树序：背景应排在 背景压暗遮罩 之后、跳跳乐 之前（在玩法层之下）
	var 根 := _lvl
	var 序 := {}
	for i in 根.get_child_count():
		序[根.get_child(i).name] = i
	print("[拍图] 树序 遮罩=%d 二阶段背景=%d 跳跳乐=%d Player=%d UI=%d"
		% [序.get("背景压暗遮罩", -1), 序.get("二阶段背景", -1),
		   序.get("跳跳乐", -1), 序.get("Player", -1), 序.get("UI", -1)])

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://phase2_shot.png")
	print("[拍图] 截图1（未压暗）已存 user://phase2_shot.png  (%dx%d)"
		% [img.get_width(), img.get_height()])

	# 真正的二阶段观感还要开压暗遮罩（环境暗化是二阶段设定的一部分）
	var 遮罩 := _lvl.get_node_or_null("背景压暗遮罩")
	if 遮罩 != null:
		遮罩.call("设置变暗", true, true)
		await _等帧(20)
		await RenderingServer.frame_post_draw
		var img2 := get_viewport().get_texture().get_image()
		img2.save_png("user://phase2_shot_dim.png")
		print("[拍图] 截图2（压暗后）已存 user://phase2_shot_dim.png")
	get_tree().quit(0)


func _等帧(n: int) -> void:
	for _i in n:
		if _player != null and is_instance_valid(_player):
			_player.global_position = 区域中心
			_player.velocity = Vector2.ZERO
		await get_tree().physics_frame
