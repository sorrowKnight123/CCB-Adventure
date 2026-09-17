extends Node2D
## 隐藏房间那套东西的自检（headless，场景模式 —— `--script` 不加载 autoload）。
## 运行：godot --headless --path . res://tests/test_hidden_room.tscn --quit-after 8000
##
## 覆盖：
##   门禁   —— JumpPlant 的 `需要通关ID` 认 **boss 通关**（defeated_boss_ids），达标后才出现且可踩
##   锁镜头 —— RoomCameraLock 进出房间时锁定/还原，且**全程不碰** position_smoothing_enabled / offset
##   气泡   —— InteractBubble 渐显渐隐，重复调用不重开 tween
##   钢琴   —— 前 4 次只播普通旁白；第 5 次给「狂喜之诗 其一」+ 播过场；之后再交互不再给
##
## 会写真实存档，所以开头备份、结尾还原（跟 test_music_game.gd 一样）。

const JUMP_PLANT_SCENE: PackedScene = preload("res://scenes/props/level3/JumpPlant.tscn")
const CAMERA_LOCK_SCRIPT := preload("res://scripts/game/RoomCameraLock.gd")
const PIANO_SCENE: PackedScene = preload("res://scenes/props/level3/MossPiano.tscn")
const BUBBLE_SCENE: PackedScene = preload("res://scenes/ui/InteractBubble.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")

const 测试BossID := "test_hidden_room_boss"
const 收集品 := "ecstasy_1"

var _pass: int = 0
var _fail: int = 0
var _player: CharacterBody2D
var _had_save: bool = false
var _backup: String = ""


func _ready() -> void:
	_had_save = FileAccess.file_exists("user://save.json")
	if _had_save:
		var f := FileAccess.open("user://save.json", FileAccess.READ)
		_backup = f.get_as_text()
		f.close()
	await _run()
	_restore_save()
	print("\n===== 隐藏房间自检结果：通过 %d / 失败 %d =====" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	GameState.reset()
	_add_floor()
	_player = PLAYER_SCENE.instantiate()
	_player.position = Vector2(-600, 0)
	add_child(_player)
	await _settle()

	await _check_gate()
	await _check_interact_bubble()
	await _check_room_camera_lock()
	await _check_piano()


# ──────────────────────────── 门禁 ────────────────────────────


func _check_gate() -> void:
	var plant := JUMP_PLANT_SCENE.instantiate()
	plant.需要通关ID = 测试BossID
	add_child(plant)
	plant.global_position = Vector2(-600, 100)
	await _settle()

	_check(not plant.visible, "门禁：Boss 未击败时植物隐藏")
	_check(not (plant.get_node("Trigger") as Area2D).monitoring, "门禁：隐藏时触发区关闭（踩不到）")

	# 关键：门禁要认 defeated_boss_ids（boss 通关写的是这个字段，不是 triggered_ids）
	GameState.mark_boss_defeated(测试BossID)
	await get_tree().create_timer(0.3).timeout     # 等它轮询到
	_check(plant.visible, "门禁：Boss 击败后植物出现")
	_check((plant.get_node("Trigger") as Area2D).monitoring, "门禁：出现后触发区恢复（可踩）")
	await get_tree().create_timer(0.6).timeout
	_check(plant.scale.is_equal_approx(Vector2(0.3, 0.3)),
		"门禁：弹出动画结束后回到原大小（实际 %s）" % plant.scale)

	plant.queue_free()
	await _settle()


# ──────────────────────────── 气泡 ────────────────────────────


func _check_interact_bubble() -> void:
	var bubble: InteractBubble = BUBBLE_SCENE.instantiate()
	bubble.按键文本 = "W"
	add_child(bubble)
	await _settle()

	_check(bubble.get_node("Panel/Key").text == "W", "气泡：按键文本生效")
	_check(is_zero_approx(bubble.modulate.a), "气泡：初始是透明的")

	bubble.显示()
	await get_tree().create_timer(0.3).timeout
	_check(is_equal_approx(bubble.modulate.a, 1.0), "气泡：显示() 后渐显到不透明")

	# 逐帧反复调用不应重开 tween（否则永远到不了 1）—— 这里连续调 20 帧
	for i in 20:
		bubble.显示()
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	_check(is_equal_approx(bubble.modulate.a, 1.0), "气泡：重复调用不会把渐显动画顶回去")

	bubble.隐藏()
	await get_tree().create_timer(0.35).timeout
	_check(is_zero_approx(bubble.modulate.a), "气泡：隐藏() 后渐隐到透明")

	bubble.queue_free()
	await _settle()


# ──────────────────────────── 进房间锁镜头 ────────────────────────────


func _check_room_camera_lock() -> void:
	var 房间 := Rect2(1000, -200, 800, 400)
	var lock := Node2D.new()
	lock.set_script(CAMERA_LOCK_SCRIPT)
	lock.set("房间矩形", 房间)          # ⚠️ 必须在 add_child 之前设：_ready 里会按矩形建检测区
	lock.set("相机滑入时长", 0.15)
	add_child(lock)
	await _settle()

	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	# 记下"不许碰"的两个属性（agent.md §20 铁律 1、2）
	var smoothing_before := cam.position_smoothing_enabled
	var offset_before := cam.offset

	# 进房间
	_player.global_position = 房间.get_center() + Vector2(0, 100)
	await get_tree().create_timer(0.9).timeout
	_check(cam.top_level, "锁镜头：进房间后相机脱离玩家跟随")
	_check(cam.global_position.distance_to(房间.get_center()) < 6.0,
		"锁镜头：相机对到房间中心（实际 %s / 目标 %s）" % [cam.global_position, 房间.get_center()])

	# 出房间
	_player.global_position = Vector2(-600, 0)
	await get_tree().create_timer(1.2).timeout
	_check(not cam.top_level, "锁镜头：离开后相机恢复跟随玩家")

	# 全程不许碰这两个（这是"偶尔跳变"的根因）
	_check(cam.position_smoothing_enabled == smoothing_before,
		"锁镜头：全程没动 position_smoothing_enabled（否则会出现瞬时跳变）")
	_check(cam.offset.is_equal_approx(offset_before),
		"锁镜头：全程没动 offset（那个归镜头震动管）")

	lock.queue_free()
	await _settle()


# ──────────────────────────── 钢琴 ────────────────────────────


func _check_piano() -> void:
	var piano := PIANO_SCENE.instantiate()
	add_child(piano)
	piano.global_position = Vector2(-600, 100)
	await _settle()

	# 几何检查：按真实摆法（钢琴坐在地面上）时，站在地板上的玩家必须进得了交互范围。
	# ⚠️ 交互区一旦放得太高，玩家在地上就完全够不到 —— 有人在编辑器里会漏掉这点。
	piano.global_position = Vector2(-600, 6)      # 让钢琴底边落在测试地面(顶面 180)上
	_player.global_position = Vector2(-600, 180)
	await _settle()
	_check(bool(piano.get("_player_in_range")), "钢琴：站在地板上的玩家能进交互范围")

	# 前 4 次：只播普通旁白，不给东西
	for i in 4:
		piano._查看钢琴()
	_check(int(piano.get("_查看次数")) == 4, "钢琴：前 4 次交互都只是看看")
	_check(not GameState.has_collectible(收集品), "钢琴：前 4 次不给东西")

	# 第 5 次：发现羊皮纸
	piano._查看钢琴()
	_check(int(piano.get("_查看次数")) == 5, "钢琴：第 5 次触发发现")
	_check(not GameState.has_collectible(收集品), "钢琴：发现旁白播完之前还没给东西")

	# 模拟"发现旁白播过了" + "对话结束"（headless 里不方便驱动真实对话推进）
	piano._on_dialogue_passed_cue("piano_found")
	piano._on_dialogue_ended(null)
	await _settle()
	_check(GameState.has_collectible(收集品), "钢琴：拿到「狂喜之诗 其一」")
	_check(GameState.collected_ids.size() >= 1, "钢琴：收集品进了存档列表")

	# 过场动画应当被实例化并暂停游戏
	var cutscene := get_tree().get_first_node_in_group("ability_cutscene")
	_check(cutscene != null, "钢琴：播放了能力获取过场")
	_check(get_tree().paused, "钢琴：过场期间游戏被暂停")
	if cutscene != null:
		cutscene.queue_free()
	await get_tree().process_frame
	get_tree().paused = false

	# 之后再交互只播普通旁白，不再给
	piano._查看钢琴()
	await _settle()
	_check(not bool(piano.get("_发现旁白已播")), "钢琴：已拿到后不再触发发现分支")

	# 清理：把可能开着的对话框关掉，免得干扰后面的断言
	DialogueBridge.interrupt()
	piano.queue_free()
	await _settle()


# ──────────────────────────── 工具 ────────────────────────────


func _add_floor() -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6000, 40)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(0, 200)
	add_child(body)


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _restore_save() -> void:
	if _had_save:
		var r := FileAccess.open("user://save.json", FileAccess.WRITE)
		r.store_string(_backup)
		r.close()
	else:
		var dir := DirAccess.open("user://")
		if dir:
			dir.remove("save.json")


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("[PASS] " + name)
	else:
		_fail += 1
		print("[FAIL] " + name)
