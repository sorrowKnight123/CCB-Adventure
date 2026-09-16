extends Node
## 敌人碰撞伤害测试：
## A) 直接调用 _on_hurtbox_body_entered 验证伤害/无敌/冲刺链路；
## B) body_entered 信号链路（预热重叠→稳定→移回触发进入）。

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var player: CharacterBody2D = $Player
	var skel: CharacterBody2D = $Skeleton
	skel.get_node("AttackHitbox").monitoring = false  # 隔离骷髅攻击

	player.global_position = Vector2(0, 86)
	skel.global_position = Vector2(40, 83)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 测试场景初始两者都在原点重叠受过伤（无敌 0.5s），等无敌结束再开始
	await get_tree().create_timer(0.7).timeout
	player.invincible_timer = 0.0
	var hp0: int = player.hp

	# ---- A) 直接调用链路 ----
	player._on_hurtbox_body_entered(skel)
	_check(player.hp == hp0 - 1, "碰撞掉 1 血（%d → %d）" % [hp0, player.hp])
	player._on_hurtbox_body_entered(skel)
	_check(player.hp == hp0 - 1, "受击无敌 0.5s 内再碰不掉血（hp=%d）" % player.hp)
	await get_tree().create_timer(0.7).timeout
	player._on_hurtbox_body_entered(skel)
	_check(player.hp == hp0 - 2, "无敌结束再碰掉血（%d）" % player.hp)
	player._is_dash_intangible = true
	player._on_hurtbox_body_entered(skel)
	_check(player.hp == hp0 - 2, "冲刺无敌不掉血（hp=%d）" % player.hp)

	# ---- B) body_entered 信号链路（真实重叠进入）----
	player._is_dash_intangible = false
	player.invincible_timer = 0.0
	player.global_position = Vector2(30, 86)  # 预热重叠（正常掉 1 血）
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.global_position = Vector2(0, 86)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout  # 等预热受伤的无敌结束
	var hp_before_b: int = player.hp
	player.global_position = Vector2(30, 86)   # 移回 → body_entered
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(player.hp == hp_before_b - 1, "信号触发碰撞掉血（%d → %d）" % [hp_before_b, player.hp])

	_finish()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PASS] %s" % what)
	else:
		_failures += 1
		print("[FAIL] %s" % what)


func _finish() -> void:
	print("EnemyCollision test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
