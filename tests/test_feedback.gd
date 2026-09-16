extends Node
## 攻击手感系统验证：
## 1) AttackData 资源加载正确（轻/中/重数值，第3段 Heavy 伤害 2）。
## 2) Player._on_hit 链路：顿帧（time_scale 压 0 后恢复）、镜头震动（委托 Player）、伤害（take_damage）。

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	var player: CharacterBody2D = $Player
	var skel: CharacterBody2D = $Skeleton

	# ---- 1) AttackData 资源 ----
	var light = player.ATTACK_DATA[0]
	var medium = player.ATTACK_DATA[1]
	var heavy = player.ATTACK_DATA[2]
	_check(light.hitstop_duration < medium.hitstop_duration and medium.hitstop_duration < heavy.hitstop_duration,
		"顿帧递增（%.2f < %.2f < %.2f）" % [light.hitstop_duration, medium.hitstop_duration, heavy.hitstop_duration])
	_check(heavy.damage == 2 and light.damage == 1, "重击伤害 2、轻击 1（Heavy.damage=%d）" % heavy.damage)
	_check(FeedbackManager != null, "FeedbackManager autoload 已加载")

	# ---- 2) _on_hit 链路（用第 3 段 Heavy 数据）----
	var hp_before: int = skel.生命值
	player.combo_stage = 3
	player._on_hit(skel, player._attack_data_for_stage())
	_check(skel.生命值 == hp_before - 2, "敌人受伤 -2（%d → %d）" % [hp_before, skel.生命值])
	_check(player.shake_timer > 0.0, "镜头震动已触发（shake_timer=%.2f）" % player.shake_timer)
	_check(Engine.time_scale <= 0.001, "顿帧生效（time_scale=%.2f）" % Engine.time_scale)
	# 等顿帧恢复（Heavy 0.14s + 余量）
	var recovered: bool = await _wait_until(func() -> bool:
		return Engine.time_scale >= 0.999, 1.0)
	_check(recovered, "顿帧恢复（time_scale=%.2f）" % Engine.time_scale)

	# 顿帧恢复后震动应实际推动相机偏移（幅度 > 1px，肉眼可见）
	var offset_seen := false
	for i in 6:
		await get_tree().physics_frame
		if player.camera.offset.length() > 1.0:
			offset_seen = true
			break
	_check(offset_seen, "镜头震动实际偏移可见（offset=%.1fpx）" % player.camera.offset.length())

	# ---- 3) 命中帧延迟：攻击起手（前摇）不命中，动画播到命中帧才出判定/反馈 ----
	player.global_position = Vector2(0, 0)
	skel.global_position = Vector2(40, -30)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp2: int = skel.生命值
	player._play_attack(1)
	# 前摇早期（真实时钟短等，物理帧可能刚跑 0~1 帧）：不应命中
	await get_tree().create_timer(0.05).timeout
	_check(skel.生命值 == hp2, "攻击前摇期未命中（%d）" % skel.生命值)
	# 命中帧后应命中（轮询骷髅受伤）
	var hit: bool = await _wait_until(func() -> bool: return skel.生命值 < hp2, 3.0)
	_check(hit, "命中帧后命中（%d → %d）" % [hp2, skel.生命值])

	_finish()


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var start := Time.get_ticks_msec()
	while not cond.call():
		if (Time.get_ticks_msec() - start) / 1000.0 >= timeout_s:
			return false
		await get_tree().process_frame
	return true


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PASS] %s" % what)
	else:
		_failures += 1
		print("[FAIL] %s" % what)


func _finish() -> void:
	print("Feedback test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
