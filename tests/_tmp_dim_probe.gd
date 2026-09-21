extends Node2D
## 临时探针（非 headless）：量"背景压暗遮罩"到底有没有生效、以及按键路径可不可达。
##
## 亮度分两带量，因为背景是两层：
##   上带 = Back/back（远景墙）      下带 = Back/plat（地板美术层）
## 玩家固定在画面左侧，下带只取右半边，避免把玩家自己拍进去。
##
## 运行：godot --path . res://tests/_tmp_dim_probe.tscn      （必须非 headless）

const LEVEL := preload("res://scenes/levels/music_hall/4_1.tscn")
const 固定点 := Vector2(200.0, 3369.0)

var _lvl: Node2D = null
var _player: CharacterBody2D = null
var _mask: ColorRect = null
var _原始z: int = -1


func _ready() -> void:
	_lvl = LEVEL.instantiate()
	add_child(_lvl)
	_player = _lvl.get_node_or_null("Player")
	_mask = _lvl.get_node_or_null("背景压暗遮罩")
	if _player == null or _mask == null:
		print("[探针] 玩家或遮罩找不到，退出")
		get_tree().quit(1)
		return
	_原始z = _mask.z_index
	print("[探针] 遮罩 z_index=%d 变暗程度=%.2f color=%s process_mode=%d"
		% [_原始z, float(_mask.get("变暗程度")), str(_mask.color), _mask.process_mode])

	await _等帧(150)        # 等镜头收敛
	var 上0 := await _量("A 基线")
	_mask.call("设置变暗", true, true)
	await _等帧(10)
	var 上1 := await _量("B 压暗 · 立即=true · z=%d" % _mask.z_index)
	print("[探针] color 现在是 %s" % str(_mask.color))

	_mask.z_index = 100
	await _等帧(10)
	var 上2 := await _量("C 压暗 · z=+100（排除遮挡）")
	_mask.z_index = _原始z

	_mask.call("设置变暗", false, true)
	await _等帧(10)
	_mask.call("设置变暗", true)          # 默认走补间
	await _等帧(90)
	var 上3 := await _量("D 压暗 · 补间路径")
	print("[探针] 补间后 color = %s" % str(_mask.color))
	print("[探针] 截图已存 user://dimprobe_A.png / _B.png（基线 / 压暗后）")

	print("\n===== 结论（亮度，上带=远景墙 下带=地板美术） =====")
	for 行 in [上0, 上1, 上2, 上3]:
		print("%-32s 上带 %6.2f   下带 %6.2f" % [行[0], 行[1], 行[2]])
	print("A→B 变化：上带 %+.2f，下带 %+.2f" % [上0[1] - 上1[1], 上0[2] - 上1[2]])
	print("A→C 变化：上带 %+.2f，下带 %+.2f（与 B 相同 = 不是遮挡问题）"
		% [上0[1] - 上2[1], 上0[2] - 上2[2]])
	print("A→D 变化：上带 %+.2f，下带 %+.2f（补间也生效）"
		% [上0[1] - 上3[1], 上0[2] - 上3[2]])

	print("\n===== 结论（按键 E：正常游玩） =====")
	_mask.call("设置变暗", false, true)
	await _等帧(6)
	var 前 := bool(_mask.call("是否变暗"))
	await _模拟按B()
	var 后 := bool(_mask.call("是否变暗"))
	print("按 B 之前=%s 之后=%s → %s"
		% [str(前), str(后), "按键有效" if 后 != 前 else "按键没有生效"])

	print("\n===== 结论（按键 F：暂停菜单开着） =====")
	_mask.call("设置变暗", false, true)
	await _等帧(6)
	get_tree().paused = true
	await _等帧(4)
	var 前2 := bool(_mask.call("是否变暗"))
	await _模拟按B()
	var 后2 := bool(_mask.call("是否变暗"))
	get_tree().paused = false
	print("暂停中 按 B 之前=%s 之后=%s → %s"
		% [str(前2), str(后2), "按键有效" if 后2 != 前2 else "按键失效（process_mode 可暂停）"])

	get_tree().quit(0)


## 每物理帧把玩家按回固定点，等 N 帧
func _等帧(n: int) -> void:
	for _i in n:
		if _player != null and is_instance_valid(_player):
			_player.global_position = 固定点
			_player.velocity = Vector2.ZERO
		await get_tree().physics_frame


## 截一帧，量两带的平均亮度（0~255）
func _量(标签: String) -> Array:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var vw := img.get_width()
	var vh := img.get_height()
	var 上 := _带均值(img, 0, int(vw * 1.0), int(vh * 0.10), int(vh * 0.45))
	var 下 := _带均值(img, int(vw * 0.50), vw, int(vh * 0.62), int(vh * 0.92))
	print("[探针] %-32s 上带 %6.2f   下带 %6.2f" % [标签, 上, 下])
	img.save_png("user://dimprobe_%s.png" % 标签.substr(0, 1))
	return [标签, 上, 下]


func _带均值(img: Image, x0: int, x1: int, y0: int, y1: int) -> float:
	var 和 := 0.0
	var 数 := 0
	for y in range(y0, y1, 3):
		for x in range(x0, x1, 3):
			var c := img.get_pixel(x, y)
			和 += (c.r + c.g + c.b) / 3.0
			数 += 1
	return 和 / maxf(float(数), 1.0) * 255.0


## 模拟敲一下 B 键（会更新 is_physical_key_pressed 的状态）
func _模拟按B() -> void:
	var 下 := InputEventKey.new()
	下.physical_keycode = KEY_B
	下.pressed = true
	Input.parse_input_event(下)
	await get_tree().process_frame
	await get_tree().process_frame
	var 上 := InputEventKey.new()
	上.physical_keycode = KEY_B
	上.pressed = false
	Input.parse_input_event(上)
	await get_tree().process_frame
	await get_tree().process_frame
