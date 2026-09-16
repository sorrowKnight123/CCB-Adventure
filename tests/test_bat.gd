extends Node
## 蝙蝠小怪行为测试：
## 1) 玩家在索敌范围外 → 睡觉(sleep)；进入范围 → 惊醒(wakeup) → 追击(chase, run 动画朝玩家移动)。
## 2) 进入攻击范围(X+Y达标) → attack1/attack2（概率随机），攻击开始时冷却计时器被赋值（§13.6）。
## 3) 攻击播完 → 冷却期内不再攻击；冷却结束 → 再次攻击。
## 4) 命中盒随 facing 对称（左右翻转锚点 + 形状偏移）。

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var bat: CharacterBody2D = $Bat
	var anim: AnimatedSprite2D = bat.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var hitbox: Area2D = bat.get_node("AttackHitbox") as Area2D
	var shape: CollisionShape2D = hitbox.get_node("CollisionShape2D") as CollisionShape2D
	var player := $FakePlayer
	# 先放玩家到索敌范围外，再加组（避免玩家初始在蝙蝠身边导致提前惊醒）
	player.global_position = Vector2(300, 0)
	player.add_to_group("player")

	# ---- 1) 范围外睡觉 ----
	var sleeping: bool = await _wait_until(func() -> bool: return anim.animation == "sleep", 3.0)
	_check(sleeping, "索敌范围外 → 睡觉（anim=%s）" % anim.animation)
	_check(anim.animation == "sleep", "睡觉状态稳定（anim=%s）" % anim.animation)

	# ---- 2) 进入范围 → 惊醒 → 追击 ----
	player.global_position = Vector2(150, 0)
	var chased: bool = await _wait_until(func() -> bool: return anim.animation == "run", 4.0)
	_check(chased, "进入索敌范围 → 惊醒后追击（anim=%s）" % anim.animation)
	# 追击朝玩家靠近（距离缩小）
	await get_tree().create_timer(0.5).timeout
	var d0: float = absf(player.global_position.x - bat.global_position.x)
	await get_tree().create_timer(0.8).timeout
	var d1: float = absf(player.global_position.x - bat.global_position.x)
	_check(d1 < d0 - 5.0, "追击向玩家靠近（%.0f → %.0f）" % [d0, d1])

	# ---- 3) 进入攻击范围 → 攻击 + 冷却赋值 ----
	player.global_position = Vector2(60, 0)
	var attacking: bool = await _wait_until(func() -> bool:
		return anim.animation == "attack1" or anim.animation == "attack2", 4.0)
	_check(attacking, "进入攻击范围 → 攻击（anim=%s）" % anim.animation)
	_check(bat.attack_cooldown_timer > 0.0, "攻击开始时冷却已赋值（%.2f）" % bat.attack_cooldown_timer)

	# ---- 4) 攻击播完 → 冷却期内不攻击 ----
	var done: bool = await _wait_until(func() -> bool:
		return anim.animation != "attack1" and anim.animation != "attack2", 4.0)
	_check(done, "攻击播完（anim=%s）" % anim.animation)
	_check(bat.attack_cooldown_timer > 0.0, "冷却中（剩余 %.2f）" % bat.attack_cooldown_timer)
	var no_attack: bool = true
	for i in 10:
		await get_tree().physics_frame
		if anim.animation == "attack1" or anim.animation == "attack2":
			no_attack = false
			break
	_check(no_attack, "冷却期内（0.16s）未再次攻击")

	# ---- 5) 冷却结束 → 再次攻击 ----
	var second: bool = await _wait_until(func() -> bool:
		return anim.animation == "attack1" or anim.animation == "attack2", bat.攻击冷却 + 3.0)
	_check(second, "冷却结束后再次攻击（anim=%s）" % anim.animation)

	# ---- 6) 命中盒随 facing 对称 ----
	player.global_position = Vector2(120, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var r_hit := hitbox.position.x
	var r_shape := shape.position.x
	player.global_position = Vector2(-120, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(r_hit > 0.0 and hitbox.position.x < 0.0, "命中盒锚点随朝向翻转（右 %.0f / 左 %.0f）" % [r_hit, hitbox.position.x])
	_check(is_equal_approx(r_shape, -shape.position.x), "形状偏移对称（%.1f / %.1f）" % [r_shape, shape.position.x])

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
	print("Bat test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
