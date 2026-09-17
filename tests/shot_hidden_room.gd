extends Node2D
## 隐藏房间"真·关卡取景"工具（**必须非 headless**）。
## 运行：godot --path . res://tests/shot_hidden_room.tscn
##
## 为什么要单独一个工具：`test_hidden_room.gd` 是在**自建的合成场景**里跑逻辑，
## 它造的地面和真实关卡不一样 —— 交互区放太高这种问题会被合成场景的几何掩盖掉。
## 这里直接加载真实关卡 `3_1.tscn`，把玩家挪进隐藏房间，等镜头锁好以后截图，
## 顺便把房间 / 钢琴 / 气泡 / 玩家的世界矩形打出来，用肉眼和数字双确认摆位。
##
## ⚠️ 房间矩形和钢琴都是**运行时从场景里找的**，不写死：你在编辑器里拖动过它们，
##    写死的话这里会静默失效（找不到就整段不打印，看着像"没问题"）。
##
## 产物：`user://hidden_room.png`（路径会打印出来）

const LEVEL: PackedScene = preload("res://scenes/levels/3_moss/3_1.tscn")

## 找不到 RoomCameraLock 时的兜底（正常情况下用不上）
const 兜底房间 := Rect2(4352, 1178, 819, 358)


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var level := LEVEL.instantiate()
	add_child(level)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var 房间 := _find_room_rect(level)
	var piano := _find_first(level, "MossPiano") as Node2D
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		push_error("关卡里没找到玩家")
		get_tree().quit(1)
		return
	# 落点：房间中上部，落下去就站在房间地面上（不写死坐标，房间挪了也跟着走）
	player.global_position = 房间.get_center() + Vector2(0.0, 房间.size.y * 0.35)

	# 等落地 + 等镜头插值收敛（RoomCameraLock 是插值过去的，别提前截）
	await get_tree().create_timer(2.5).timeout

	var cam := player.get_node_or_null("Camera2D") as Camera2D
	print("\n──── 隐藏房间取景 ────")
	print("房间矩形(内部)  %s" % 房间)
	if piano == null:
		print("⚠️ 场景里没找到 MossPiano（被改名/删了？）")
	else:
		print("钢琴节点         %s   根缩放 %s" % [piano.get_path(), piano.scale])
		var sprite := piano.get_node_or_null("Sprite") as Sprite2D
		if sprite != null:
			var tex := sprite.global_scale
			var canvas := sprite.texture.get_size() * tex
			var center := sprite.global_position
			print("钢琴画布世界矩形 x[%.0f, %.0f]  y[%.0f, %.0f]  (%.0f x %.0f)" % [
				center.x - canvas.x * 0.5, center.x + canvas.x * 0.5,
				center.y - canvas.y * 0.5, center.y + canvas.y * 0.5, canvas.x, canvas.y])
			# 主体 = 贴图里真正不透明的部分（Sprite2D 居中对齐画布，不是对齐主体！）
			var used := sprite.texture.get_image().get_used_rect()
			var origin := center - sprite.texture.get_size() * tex * 0.5
			var sub_tl := origin + Vector2(used.position) * tex
			var sub_br := origin + Vector2(used.end) * tex
			print("钢琴主体世界矩形 x[%.0f, %.0f]  y[%.0f, %.0f]  (%.0f x %.0f)" % [
				sub_tl.x, sub_br.x, sub_tl.y, sub_br.y, sub_br.x - sub_tl.x, sub_br.y - sub_tl.y])
			print("  ↳ 主体底边 %.0f vs 房间地面顶边 %.0f → %s %.0f px" % [
				sub_br.y, 房间.end.y,
				"陷进地里" if sub_br.y > 房间.end.y else "悬空",
				absf(sub_br.y - 房间.end.y)])
			print("  ↳ 水平：主体左 %.0f 右 %.0f；房间内壁 左 %.0f 右 %.0f（%s）" % [
				sub_tl.x, sub_br.x, 房间.position.x, 房间.end.x,
				"越界" if sub_tl.x < 房间.position.x or sub_br.x > 房间.end.x else "在墙内"])
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


func _find_room_rect(root: Node) -> Rect2:
	## RoomCameraLock 上那个 `房间矩形`（不依赖它的节点路径）。
	for node in root.find_children("*", "", true, false):
		var value = node.get("房间矩形")
		if value is Rect2:
			return value
	push_warning("关卡里没找到带 `房间矩形` 的节点，用兜底值")
	return 兜底房间


func _find_first(root: Node, node_name: String) -> Node:
	for node in root.find_children(node_name, "", true, false):
		return node
	return null
