extends Node
## 落地 + 按住 S → 直接进入下蹲（不播 land 动画）回归测试：
## 需求：玩家落地时按着 S，不触发 land（0.5s 下蹲→站起），立即进入持续下蹲 crouch。
## 断言：1) 按住 S 落地 → state=CROUCH、_landing_timer=0、动画=crouch（非 land）；
##        2) 松开 S → 站起恢复 IDLE。

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var player: CharacterBody2D = $Player

	# 玩家置于空中，按住 S，自由下落
	player.global_position = Vector2(0, 100)
	Input.action_press("crouch")

	# 等落地（落地瞬间应直接进入 CROUCH，_landing_timer 保持 0）
	var landed: bool = await _wait_until(func() -> bool:
		return player.is_on_floor() and player.state == player.State.CROUCH and player._landing_timer <= 0.0, 4.0)
	_check(landed, "按住 S 落地 → 直接进入 CROUCH（state=%d, y=%.0f）" % [player.state, player.global_position.y])
	_check(player._landing_timer <= 0.0, "未触发 land 计时器（_landing_timer=%.2f，应 0）" % player._landing_timer)
	_check(player._current_action == "crouch", "动画为 crouch（实际=%s，应为 crouch 而非 land）" % player._current_action)
	_check(player._is_collision_shrunk, "下蹲碰撞盒已缩小")

	# 松开 S → 站起
	Input.action_release("crouch")
	var stood: bool = await _wait_until(func() -> bool: return player.state == player.State.IDLE, 2.0)
	_check(stood, "松开 S 后站起（state=%d）" % player.state)
	_check(not player._is_collision_shrunk, "碰撞盒已恢复")

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
	print("LandCrouch test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
