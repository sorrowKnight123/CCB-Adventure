extends Node
## 下穿单向平台回归测试（大复位距离：碰撞箱高 + 平台厚 32px）：
## 平台用 TileSet one_way 碰撞 + 玩家下穿复位距离保证碰撞体完全脱离平台 → 不弹回。
## 场景：平台A(顶392) → 平台B(顶600，间距208) → 实心Ground(顶800)。
## 断言：1) 从上方自由下落被A接住；2) 下穿穿一层被B接住（不弹回、不穿到底）；3) 再下穿到Ground。

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	($PlatformA as TileMapLayer).set_cell(Vector2i(0, 0), 0, Vector2i(14, 18))
	($PlatformB as TileMapLayer).set_cell(Vector2i(0, 0), 0, Vector2i(14, 18))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: CharacterBody2D = $Player

	# ---- 0) 从上方自由下落 → 被A接住（one_way 从上方阻挡）----
	player.global_position = Vector2(0, 300)
	var on_a: bool = await _wait_until(func() -> bool:
		return player.is_on_floor() and player._landing_timer <= 0.0, 3.0)
	_check(on_a, "从上方下落被平台A接住（y=%.0f，期望 ≈378）" % player.global_position.y)
	_check(player.global_position.y < 400.0, "停在A上（%.0f）未穿透" % player.global_position.y)

	# ---- 1) 下穿 → 穿一层被B接住（大复位距离，不弹回）----
	player._is_drop_through = true
	player._drop_origin_y = player.global_position.y
	var cs := player.player_collision.shape as CapsuleShape2D
	player._drop_reset_distance = (cs.height + cs.radius * 2.0) + player.DROP_PLATFORM_THICKNESS
	player.velocity.y = 80.0
	var on_b: bool = await _wait_until(func() -> bool:
		return player.is_on_floor() and player.global_position.y > 450.0, 4.0)
	_check(on_b, "下穿后落在平台B上（y=%.0f，期望 ≈586）" % player.global_position.y)
	var y1: float = player.global_position.y
	_check(y1 > 520.0 and y1 < 620.0, "位置在B层（%.0f）而非Ground（786）" % y1)
	_check(not player._is_drop_through, "下穿标志已复位")

	# ---- 2) 再下穿 → 落到实心Ground ----
	var settled: bool = await _wait_until(func() -> bool: return player._landing_timer <= 0.0, 2.0)
	_check(settled, "平台B上落地动画结束")
	player._is_drop_through = true
	player._drop_origin_y = player.global_position.y
	player.velocity.y = 80.0
	var on_ground: bool = await _wait_until(func() -> bool:
		return player.is_on_floor() and player.global_position.y > 700.0, 4.0)
	_check(on_ground, "再次下穿后落到实心Ground（y=%.0f）" % player.global_position.y)

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
	print("DropThrough test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
