extends Node2D
## 隐藏房间"真·关卡取景"工具（**必须非 headless**）。
## 运行：godot --path . res://tests/shot_hidden_room.tscn
##
## 为什么要单独一个工具：`test_hidden_room.gd` 是在**自建的合成场景**里跑逻辑，
## 它造的地面和真实关卡不一样 —— 交互区放太高这种问题会被合成场景的几何掩盖掉。
## 这里直接加载真实关卡 `3_1.tscn`，把玩家挪进隐藏房间，等镜头锁好以后截图，
## 顺便把房间 / 钢琴 / 玩家的世界矩形打出来，用肉眼和数字双确认摆位。
##
## 产物：`user://hidden_room.png`（路径会打印出来）

const LEVEL: PackedScene = preload("res://scenes/levels/3_moss/3_1.tscn")

## 与 3_1.tscn 里 RoomCameraLock 的 `房间矩形` 保持一致
const 房间 := Rect2(4352, 1178, 819, 358)
## 玩家落点：房间地面（顶面 y=1536）上方一点，落下去就站住了
const 落点 := Vector2(5000, 1400)


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var level := LEVEL.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		push_error("关卡里没找到玩家")
		get_tree().quit(1)
		return
	player.global_position = 落点

	# 等落地 + 等镜头插值收敛（RoomCameraLock 是插值过去的，别提前截）
	await get_tree().create_timer(2.5).timeout

	var piano := level.get_node_or_null("HiddenRoom/MossPiano") as Node2D
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	print("\n──── 隐藏房间取景 ────")
	print("房间矩形(内部)  %s" % 房间)
	if piano != null:
		print("钢琴节点位置     %s   根缩放 %s" % [piano.global_position, piano.scale])
		var sprite := piano.get_node_or_null("Sprite") as Sprite2D
		if sprite != null:
			var size := sprite.texture.get_size() * sprite.global_scale
			var center := sprite.global_position
			print("钢琴画布世界矩形 x[%.0f, %.0f]  y[%.0f, %.0f]  (%.0f x %.0f)" % [
				center.x - size.x * 0.5, center.x + size.x * 0.5,
				center.y - size.y * 0.5, center.y + size.y * 0.5, size.x, size.y])
		var bubble := piano.get_node_or_null("Bubble") as Control
		if bubble != null:
			# Control 的 offset 是"父节点局部"的，跟摄像机缩放叠加后才是屏上位置。
			# 根 Control 是 0 尺寸的，真正看得见的框是它的 Panel 子节点，所以两个都打。
			print("气泡 根局部偏移  %s  (尺寸 %s)" % [bubble.position, bubble.size])
			var panel := bubble.get_node_or_null("Panel") as Control
			if panel != null:
				var box := Rect2(panel.global_position, panel.size)
				print("气泡 可见框世界  x[%.0f, %.0f]  y[%.0f, %.0f]" % [
					box.position.x, box.end.x, box.position.y, box.end.y])
	print("玩家世界位置     %s" % player.global_position)
	if cam != null:
		print("镜头 位置 %s  缩放 %s  top_level=%s" % [
			cam.global_position, cam.zoom, cam.top_level])
		var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom
		print("镜头可见世界区域 x[%.0f, %.0f]  y[%.0f, %.0f]" % [
			cam.global_position.x - half.x, cam.global_position.x + half.x,
			cam.global_position.y - half.y, cam.global_position.y + half.y])

	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "user://hidden_room.png"
	img.save_png(out)
	print("截图已存         %s" % ProjectSettings.globalize_path(out))
	print("──────────────────────\n")
	get_tree().quit()
