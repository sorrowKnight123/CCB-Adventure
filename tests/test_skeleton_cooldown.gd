extends Node
## 骷髅攻击冷却回归测试：
## 回归：_start_attack() 漏了 attack_cooldown_timer = 攻击冷却，计时器恒 0 →
## 攻击条件恒满足 → 动画播完立即再攻击（设置 5.0 冷却也几乎 1s 连击）。
## 验证：攻击开始后冷却计时器被赋值；冷却期内不再攻击；冷却结束才再次攻击。

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	var skel: CharacterBody2D = $SkeletonWhite
	var anim: AnimatedSprite2D = skel.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var player := $FakePlayer
	player.add_to_group("player")

	# 玩家放进攻击范围内（攻击范围 40 / 攻击Y范围 60），且保持同 Y
	player.global_position = skel.global_position + Vector2(30, 0)
	var cd_value: float = skel.攻击冷却

	# ---- 1) 第一次攻击开始，冷却计时器被赋值 ----
	var first: bool = await _wait_until(func() -> bool:
		return anim.animation == "attack1" or anim.animation == "attack2", 4.0)
	_check(first, "首次攻击开始（anim=%s）" % anim.animation)
	_check(skel.attack_cooldown_timer > 0.0, "攻击开始时冷却计时器已赋值（%.2f，配置 %s）" % [skel.attack_cooldown_timer, cd_value])
	_check(is_equal_approx(skel.attack_cooldown_timer, cd_value), "冷却计时器 == 攻击冷却（%.2f）" % cd_value)

	# ---- 2) 攻击播完 → CHASE，冷却期内不再攻击，且不逼近玩家 ----
	var done: bool = await _wait_until(func() -> bool:
		return anim.animation != "attack1" and anim.animation != "attack2", 4.0)
	_check(done, "首次攻击结束（anim=%s，冷却剩余 %.2fs）" % [anim.animation, skel.attack_cooldown_timer])
	_check(skel.attack_cooldown_timer > 0.0, "攻击结束后冷却仍在倒计时")
	var d0: float = absf(player.global_position.x - skel.global_position.x)

	# 冷却期内观察 0.8s：不应再次攻击，也不应逼近玩家（回归：冷却期间持续逼近 → 走到脸上才攻击）
	var no_attack: bool = true
	for i in 12:
		await get_tree().physics_frame
		if anim.animation == "attack1" or anim.animation == "attack2":
			no_attack = false
			break
	_check(no_attack, "冷却期内（0.8s）未再次攻击")
	var d1: float = absf(player.global_position.x - skel.global_position.x)
	_check(absf(d1 - d0) < 5.0, "冷却期内未逼近玩家（距离 %.1f → %.1f）" % [d0, d1])
	_check(anim.animation == "idle", "冷却期内玩家在攻击范围内 → idle（anim=%s）" % anim.animation)

	# 冷却期内玩家移到范围外（100px）→ 骷髅必须继续追击（不能因冷却而完全停住）
	# 注意：headless 物理帧率低，只验证"骷髅确实朝玩家移动"（不要求追到）
	player.global_position = skel.global_position + Vector2(100, 0)
	var start_x := skel.global_position.x
	var chased: bool = await _wait_until(func() -> bool:
		return skel.global_position.x > start_x + 2.0, 4.0)
	_check(chased, "冷却期内玩家在范围外 → 仍追击（骷髅移动 %.1fpx）" % (skel.global_position.x - start_x))
	player.global_position = skel.global_position + Vector2(30, 0)

	# ---- 3) 冷却结束 → 再次攻击 ----
	var second: bool = await _wait_until(func() -> bool:
		return anim.animation == "attack1" or anim.animation == "attack2", cd_value + 3.0)
	_check(second, "冷却结束后再次攻击（anim=%s）" % anim.animation)

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
	print("SkeletonCooldown test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
