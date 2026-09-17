extends Node2D
## 音乐小游戏流程自检（headless，场景模式 —— `--script` 不会加载 autoload）。
## 运行：godot --headless --path . res://tests/test_music_game.tscn --quit-after 8000
##
## 覆盖：
##   基线  —— 玩家的近战挥砍本身能打中 layer 3 的普通敌人（跟史莱姆无关的对照）
##   流程  —— 进区只锁相机 → 站谱台按 W 才出史莱姆并演示 → 演示期间软冻结 → PLAY
##   判定  —— 打错归零 + 自动重播；真实挥砍命中史莱姆 → 进度推进
##   结算  —— 全对 → DONE + 发货币 + 写触发 ID；0 点接触伤害不让玩家受伤
##
## 会写真实存档，所以开头备份、结尾还原（跟 test_music_sheet.gd 一样）。

const MUSIC_GAME_SCENE: PackedScene = preload("res://scenes/minigame/MusicGame.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")
const CONFIG_SCRIPT := preload("res://scripts/minigame/MusicGameConfig.gd")
const MusicNotesScript := preload("res://scripts/game/MusicNotes.gd")

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

	# 基线：先确认玩家的近战挥砍本身是好的。它不过就说明问题在近战，不在这小游戏。
	await _baseline_melee_check()

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
	_game.相机滑入时长 = 0.05
	_game.相机垂直偏移 = 150.0
	_game.position = Vector2(0, 180)   # 让史莱姆站在测试地面(顶面 180)上，跟真实关卡一致
	add_child(_game)
	await _settle()

	# 1. 初始：史莱姆隐藏，谱台常驻可见
	_check(_state() == 0, "初始状态 IDLE")
	_check(not slimes_root.visible, "初始史莱姆隐藏（还没跟谱台交互）")
	_check(_game.get_node("Pedestal").visible, "谱台一开始就可见（不依赖进区）")

	# 谱台的上下浮动动画
	var pedestal_visual := _game.get_node("Pedestal/Visual") as Sprite2D
	var bob_before := pedestal_visual.position.y
	await get_tree().create_timer(0.5).timeout
	_check(not is_equal_approx(pedestal_visual.position.y, bob_before), "谱台有上下浮动动画")

	# 染色：每只史莱姆必须用**独立材质**、且色相/饱和度等于自己那个音的颜色。
	# 共享材质会让一排史莱姆全体串色；参数不对则会出现"不是红橙黄绿青蓝紫"。
	var mats := {}
	var report := ""
	for i in _game.get_node("Slimes").get_child_count():
		var sprite := _slime(i).get_node("Sprite") as AnimatedSprite2D
		var mat := sprite.material as ShaderMaterial
		var note: String = _slime(i).get_note()
		var want := MusicNotesScript.get_color(note)
		var got_h: float = float(mat.get_shader_parameter("target_hue"))
		var got_s: float = float(mat.get_shader_parameter("target_saturation"))
		var got_v: float = float(mat.get_shader_parameter("value_scale"))
		mats[mat.get_instance_id()] = true
		report += "%s(h%.3f/s%.2f/v%.2f) " % [note, got_h, got_s, got_v]
		_check(absf(got_h - want.h) < 0.001 and absf(got_s - want.s) < 0.001,
			"%s 的材质色相/饱和度 = 该音的颜色" % note)
	print("[染色] 各史莱姆材质参数：%s" % report)
	_check(mats.size() == _game.get_node("Slimes").get_child_count(),
		"每只史莱姆用独立材质（没有串色）")

	# 2. 进区：只锁相机，史莱姆仍然不出现
	_game._on_trigger_entered(_player)
	await _settle()
	_check(_state() == 1, "进区后 ARMED")
	_check(not slimes_root.visible, "进区只锁相机，史莱姆仍隐藏")
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	_check(cam != null and cam.top_level, "进区后相机脱离跟随（锁定）")
	await get_tree().create_timer(0.25).timeout
	_game.get_node("Trigger").monitoring = false   # 免得玩家移动误触发"走远取消"干扰判定

	# 镜头：玩家在滑动范围内时镜头完全固定，停在他上方 150px（垂直偏移生效）
	# ⚠️ 期望值按"玩家 y - 偏移"算，不是"史莱姆中心 y - 偏移"：
	# 玩家站地上天然比史莱姆根节点高十几像素，相对中心算会差一点点。
	_player.global_position = _game._slimes_center()
	await _settle()
	_check(absf(cam.global_position.y - (_player.global_position.y - 150.0)) < 8.0,
		"玩家在范围内时镜头停在他上方 150px（相机y=%.0f 玩家y=%.0f）"
			% [cam.global_position.y, _player.global_position.y])

	# 玩家跑到场地两端时，镜头只会让一点点，**玩家必须仍在画面内**
	# （用户报过"镜头跳转了、玩家却不在画面里"）
	for spot in [_game.get_node("Pedestal").global_position,
			_slime(2).global_position + Vector2(420.0, 0.0)]:
		_player.global_position = spot
		await _settle()
		_check(_player_in_camera_view(),
			"镜头让位后玩家仍在画面内（玩家x=%d 镜头x=%d）"
				% [int(_player.global_position.x), int(cam.global_position.x)])

	# 3. 无碰撞伤害：contact_damage = 0 不该让玩家掉血 / 进无敌 / 被击退
	var hp_before: int = _player.hp
	_player.take_damage(_slime(0).contact_damage, _slime(0).global_position)
	_check(_player.hp == hp_before, "0 点接触伤害不掉血")
	_check(_player.invincible_timer <= 0.0, "0 点伤害不进无敌帧")
	_check(_slime(0).contact_damage == 0, "史莱姆 contact_damage 恒为 0")

	# 4. 与谱台交互（按 W）→ 史莱姆出现 + 软冻结 + 演示 → PLAY
	_game._start_demo()
	_check(_state() == 2, "与谱台交互 → DEMO")
	_check(slimes_root.visible, "交互后史莱姆出现")
	_check(_player.输入软冻结, "演示期间玩家被软冻结")
	_check(await _wait_for_state(3, 6.0), "演示结束 → PLAY")
	_check(not _player.输入软冻结, "PLAY 阶段玩家解锁")

	# 非 headless 跑时存一张截图，方便肉眼核对染色（headless 没有渲染器，跳过）。
	# 用途：颜色/布局这类事 headless 断言只能验"参数对不对"，看不出实际画面。
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://music_game_shot.png")
		print("[截图] 已保存 user://music_game_shot.png")

	# 4b. 受击表现真的会发生（用户报过"打史莱姆没反应"）：
	#     闪白靠 self_modulate、变暗靠 modulate —— 如果染色 shader 覆盖 COLOR 把它们吞掉，
	#     史莱姆就会毫无反应。这条守住"机制至少被触发"。
	# 先等演示残留的受击动画播完，否则抓到的"基准大小"是形变中间值。
	await get_tree().create_timer(0.35).timeout
	var sprite := _slime(0).get_node("Sprite") as AnimatedSprite2D
	var scale_before := sprite.scale
	_slime(0).play_hurt()
	_check(sprite.self_modulate.r > 1.0, "受击立刻闪白（self_modulate 提亮）")
	await get_tree().create_timer(0.03).timeout
	_check(sprite.scale != scale_before, "受击有缩放形变（压扁→回弹）")
	await get_tree().create_timer(0.4).timeout
	_check(sprite.scale.is_equal_approx(scale_before), "形变会回弹到原大小")
	_check(sprite.self_modulate.is_equal_approx(Color.WHITE), "闪白会恢复")

	# 5. 打错顺序（该打 2 号，先打 0 号）→ 归零 + 重播
	_hit(0)
	await _settle()
	_check(_game._progress == 0, "打错后进度归零")
	_check(_state() == 2, "打错后回到 DEMO 重播")
	_check(await _wait_for_state(3, 6.0), "重播结束 → 再次 PLAY")

	# 6. 真实挥砍命中史莱姆（走物理命中判定，不直接调 take_damage）→ 进度推进
	var diag := await _real_attack_on(2)
	_check(bool(diag["推进"]), "真实挥砍能打中史莱姆并推进进度（诊断：%s）" % str(diag))

	# 6b. 同一次挥砍同时罩到"目标 + 相邻一只" → 应当算对（不能因为蹭到旁边就判错）
	#     序列是 [2,0,1]，此时该打 0 号；同时报 2 号和 0 号。
	var progress_before: int = _game._progress
	_game._on_slime_hit(Vector2.ZERO, 2)
	_game._on_slime_hit(Vector2.ZERO, 0)
	await _settle()
	_check(_game._progress == progress_before + 1,
		"同时命中目标与相邻一只时判对（进度 %d→%d）" % [progress_before, _game._progress])

	# 7. 打完最后一个 → DONE；奖励**散落一地让玩家自己捡**（不直接入账、不弹文字提示）
	var notes_before: int = GameState.notes
	var pickups_before: int = _count_reward_pickups()
	_hit(1)
	await _settle()
	_check(_state() == 4, "全对 → DONE")
	var spawned: int = _count_reward_pickups() - pickups_before
	_check(spawned == REWARD, "通关撒出 %d 个音符拾取物（实际 %d）" % [REWARD, spawned])
	_check(GameState.notes == notes_before, "奖励不直接入账，要玩家自己捡")
	var no_toast := true
	for node in _reward_pickups():
		if bool(node.get("显示提示")):
			no_toast = false
	_check(no_toast, "奖励拾取物不弹「+N」文字提示（看左上角计数）")
	# 真捡一个：应该 +1
	var target = _reward_pickups()[0] if _count_reward_pickups() > 0 else null
	if target != null:
		target._on_body_entered(_player)
		await _settle()
		_check(GameState.notes == notes_before + 1, "捡起一个音符 +1")
	# 等散落物飞完，确认落点都在场地范围内（不会飞出场外或悬在天上）
	await get_tree().create_timer(0.6).timeout
	var mid: Vector2 = _game._slimes_center()
	var out_of_bounds := 0
	for node in _reward_pickups():
		var p: Vector2 = node.global_position
		if absf(p.x - mid.x) > float(_game.奖励散落横向范围) + 60.0 \
				or p.y < mid.y - float(_game.奖励散落纵向范围) - 80.0 \
				or p.y > mid.y + 40.0:
			out_of_bounds += 1
	_check(out_of_bounds == 0, "奖励散落物全部落在场地范围内")
	_check(GameState.has_trigger(TRIGGER_ID), "通关写入触发 ID（永久完成）")
	# 通关后整排变暗，但保留在场景里（不隐藏、不删除）
	_check(slimes_root.visible, "通关后史莱姆仍显示（不移除）")
	var all_dimmed := true
	for i in slimes_root.get_child_count():
		if (_slime(i).get_node("Sprite") as AnimatedSprite2D).modulate.r >= 0.9:
			all_dimmed = false
	_check(all_dimmed, "通关后整排史莱姆变暗")
	_check(not _player.输入软冻结, "通关后玩家未被冻住")


# ──────────────────────────── 对照与工具 ────────────────────────────


func _baseline_melee_check() -> void:
	## 用一个最小的假敌人（CharacterBody2D + 只记次数的 take_damage）验证
	## "玩家的近战挥砍能打中 layer 3 的敌人"。它跟史莱姆无关；这条不过就说明近战本身坏了。
	var dummy_script := GDScript.new()
	dummy_script.source_code = "extends CharacterBody2D\nvar hits: int = 0\nvar contact_damage: int = 0\n\nfunc take_damage(_amount: int, _from_pos: Vector2, _from_magic := false) -> void:\n\thits += 1\n"
	dummy_script.reload()

	var dummy := CharacterBody2D.new()
	dummy.set_script(dummy_script)
	dummy.collision_layer = 4
	dummy.collision_mask = 0
	dummy.add_to_group("enemies")
	var dummy_shape := CollisionShape2D.new()
	var dummy_rect := RectangleShape2D.new()
	dummy_rect.size = Vector2(90.0, 100.0)
	dummy_shape.shape = dummy_rect
	dummy.add_child(dummy_shape)
	add_child(dummy)
	dummy.global_position = Vector2(-70.0, 165.0)

	var probe_player := PLAYER_SCENE.instantiate()
	probe_player.position = Vector2(-70.0, 165.0)
	add_child(probe_player)
	probe_player.facing = 1.0
	probe_player.melee_hitbox.position.x = 24.0

	var elapsed := 0.0
	var overlaps := 0
	await _wait_on_floor(probe_player)
	Input.action_press("attack")
	while elapsed < 3.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if probe_player.melee_hitbox.monitoring:
			overlaps = maxi(overlaps, probe_player.melee_hitbox.get_overlapping_bodies().size())
		if int(dummy.get("hits")) > 0:
			break
	Input.action_release("attack")

	var hits: int = int(dummy.get("hits"))
	print("[基线] 假敌人被真实挥砍命中=%d 次，命中盒最大重叠=%d" % [hits, overlaps])
	_check(hits > 0, "基线：玩家的近战挥砍能打中 layer 3 的普通敌人")

	dummy.queue_free()
	probe_player.queue_free()
	await get_tree().physics_frame


func _real_attack_on(slot: int) -> Dictionary:
	## 把玩家挪到该史莱姆左侧、面向它，模拟一次真实攻击（按住 attack 键不放），轮询等进度推进。
	## ⚠️ 不能"按下后等固定帧数再松开"：无头模式 process 帧 ≠ 物理帧，玩家在 _physics_process
	## 消费输入，按 2 帧就松会正好错开（agent.md §5 第 8 条）。
	var slime := _slime(slot)
	_player.global_position = slime.global_position + Vector2(-70.0, 0.0)
	_player.velocity = Vector2.ZERO
	_player.facing = 1.0
	_player.melee_hitbox.position.x = 24.0
	var before: int = _game._progress
	var max_overlaps := 0
	var hits_seen := [0]
	var counter := func(_from: Vector2) -> void: hits_seen[0] += 1
	slime.被击中.connect(counter)

	await _wait_on_floor(_player)
	# 传送（直接改 global_position）之后补一次"真实移动"：玩家在真实游戏里是走过去而不是瞬移的，
	# 而瞬移不一定会把子节点 Area2D 的物理变换同步给服务器 —— 实测传送后命中盒的重叠表是空的。
	Input.action_press("move_right")
	for i in 3:
		await get_tree().physics_frame
	Input.action_release("move_right")
	Input.action_press("attack")
	var elapsed := 0.0
	var monitoring_seen := false
	while elapsed < 3.0:
		# ⚠️ get_overlapping_bodies() 要在物理处理期间读才准（process 帧读会拿到空结果）
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if _player.melee_hitbox.monitoring:
			monitoring_seen = true
			max_overlaps = maxi(max_overlaps, _player.melee_hitbox.get_overlapping_bodies().size())
		if _game._progress != before:
			break
	Input.action_release("attack")
	slime.被击中.disconnect(counter)

	return {
		"推进": _game._progress > before,
		"状态": _state(),
		"进度": "%d→%d" % [before, _game._progress],
		"命中盒最大重叠": max_overlaps,
		"史莱姆收到被击中": hits_seen[0],
		"监控见过true": monitoring_seen,
	}


func _wait_on_floor(body: CharacterBody2D) -> void:
	var settle := 0.0
	while not body.is_on_floor() and settle < 2.0:
		await get_tree().physics_frame
		settle += 1.0 / 60.0


func _player_in_camera_view() -> bool:
	## 玩家是否落在镜头视野内。视口尺寸按实际值算（headless 下视口尺寸不稳定，别硬编码）。
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return false
	var half := get_viewport().get_visible_rect().size * 0.5 / cam.zoom
	var rel := _player.global_position - cam.global_position
	return absf(rel.x) <= half.x and absf(rel.y) <= half.y


func _reward_pickups() -> Array:
	## 通关奖励的拾取物被挂在小游戏节点的父级（关卡层），跟 EnemyDrop 的做法一致。
	var out := []
	for child in get_children():
		if child.has_method("setup_drop") and child.has_method("_on_body_entered"):
			out.append(child)
	return out


func _count_reward_pickups() -> int:
	return _reward_pickups().size()


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
