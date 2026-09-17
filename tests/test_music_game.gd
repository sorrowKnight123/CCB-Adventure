extends Node2D
## 音乐小游戏流程自检（headless，场景模式 —— `--script` 不会加载 autoload）。
## 运行：godot --headless --path . res://tests/test_music_game.tscn --quit-after 4000
##
## 覆盖：进区 → ARMED、开始演示 → 演示期间软冻结 → PLAY、
##       打错 → 进度归零 + 自动重播、按顺序打对 → DONE + 发货币 + 写触发 ID，
##       以及"史莱姆 0 点接触伤害不让玩家受伤"。
##
## 会写真实存档，所以开头备份、结尾还原（跟 test_music_sheet.gd 一样）。

const MUSIC_GAME_SCENE: PackedScene = preload("res://scenes/minigame/MusicGame.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")
const CONFIG_SCRIPT := preload("res://scripts/minigame/MusicGameConfig.gd")

const TRIGGER_ID := "test_music_game"
const REWARD := 7

var _pass: int = 0
var _fail: int = 0
var _player: CharacterBody2D
var _game: Node2D
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
	print("\n===== 音乐小游戏流程自检结果：通过 %d / 失败 %d =====" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _run() -> void:
	GameState.reset()
	_add_floor()
	_player = PLAYER_SCENE.instantiate()
	_player.position = Vector2(-900, 0)   # 故意站在触发区外，进区由测试手动触发
	add_child(_player)

	# ── 搭一个小游戏：砍掉两只史莱姆，只用 3 只，顺序故意乱序（E4 → C4 → D4）──
	_game = MUSIC_GAME_SCENE.instantiate()
	var slimes_root: Node2D = _game.get_node("Slimes")
	slimes_root.get_node("Slime3").free()
	slimes_root.get_node("Slime4").free()
	var config = CONFIG_SCRIPT.new()
	config.演奏顺序 = PackedInt32Array([2, 0, 1])
	config.通关奖励 = REWARD
	config.演示间隔 = 0.05
	_game.配置 = config
	_game.触发ID = TRIGGER_ID
	_game.演示前停顿 = 0.02
	_game.演示后停顿 = 0.02
	_game.打错后重播延迟 = 0.05
	add_child(_game)
	await _settle()

	# 1. 初始：隐藏且打不到
	_check(_state() == 0, "初始状态 IDLE")
	_check(_slime(0).collision_layer == 0, "初始史莱姆碰撞层 = 0（打不到）")
	_check(not _game.get_node("Pedestal").visible, "初始谱台隐藏")

	# 2. 进区
	_game._on_trigger_entered(_player)
	await _settle()
	_check(_state() == 1, "进区后 ARMED")
	_check(_slime(0).collision_layer == 4, "进区后史莱姆可被近战命中（enemy 层）")
	_check(_game.get_node("Pedestal").visible, "进区后谱台可见")

	# 3. 无碰撞伤害：contact_damage = 0 不该让玩家掉血 / 进无敌 / 被击退
	var hp_before: int = _player.hp
	_player.take_damage(_slime(0).contact_damage, _slime(0).global_position)
	_check(_player.hp == hp_before, "0 点接触伤害不掉血")
	_check(_player.invincible_timer <= 0.0, "0 点伤害不进无敌帧")
	_check(_slime(0).contact_damage == 0, "史莱姆 contact_damage 恒为 0")

	# 4. 演示：软冻结 → PLAY
	_game._start_demo()
	_check(_state() == 2, "开始演示 → DEMO")
	_check(_player.输入软冻结, "演示期间玩家被软冻结")
	_check(await _wait_for_state(3, 6.0), "演示结束 → PLAY")
	_check(not _player.输入软冻结, "PLAY 阶段玩家解锁")

	# 5. 打错顺序（该打 2 号，先打 0 号）→ 归零 + 重播
	_hit(0)
	await _settle()
	_check(_game._progress == 0, "打错后进度归零")
	_check(_state() == 2, "打错后回到 DEMO 重播")
	_check(await _wait_for_state(3, 6.0), "重播结束 → 再次 PLAY")

	# 6. 按顺序打对 → DONE + 奖励 + 永久完成
	var notes_before: int = GameState.notes
	for slot in [2, 0, 1]:
		_hit(slot)
		await _settle()
	_check(_state() == 4, "全对 → DONE")
	_check(GameState.notes == notes_before + REWARD,
		"通关奖励 +%d（实际 +%d）" % [REWARD, GameState.notes - notes_before])
	_check(GameState.has_trigger(TRIGGER_ID), "通关写入触发 ID（永久完成）")
	_check(_slime(0).collision_layer == 0, "通关后史莱姆收起")
	_check(not _player.输入软冻结, "通关后玩家未被冻住")


# ──────────────────────────── 工具 ────────────────────────────


func _add_floor() -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 40)
	shape.shape = rect
	body.add_child(shape)
	body.position = Vector2(0, 200)
	add_child(body)


func _state() -> int:
	return int(_game._state)


func _slime(slot: int) -> Node2D:
	return _game.get_node("Slimes").get_child(slot) as Node2D


func _hit(slot: int) -> void:
	## 走真实链路：史莱姆 take_damage → 被击中信号 → 控制器仲裁。
	_slime(slot).take_damage(1, _player.global_position)


func _settle() -> void:
	## 等两帧：让 deferred 的命中仲裁跑完。
	await get_tree().physics_frame
	await get_tree().physics_frame


func _wait_for_state(target: int, timeout: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		if _state() == target:
			return true
		await get_tree().process_frame
		elapsed += maxf(get_process_delta_time(), 0.0)
	return _state() == target


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
