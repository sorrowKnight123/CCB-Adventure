extends Node
## 骷髅攻击判定盒朝向对称性测试：
## 骷髅换朝向（facing 左/右）时，命中盒整体锚点（AttackHitbox.position.x）
## 与形状自身偏移（AttackHitbox/CollisionShape2D.position.x）都必须随朝向对称翻转，
## 保证朝左/朝右的攻击判定距离一致（回归：曾因形状偏移不翻转，朝右伸 76px、朝左只伸 45px）。
## 两种皮肤（白/黄）形状偏移不同（15.5 / 49.75），共用脚本，都要测。

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	await get_tree().process_frame
	var player := $FakePlayer
	player.add_to_group("player")

	for skel_name in ["SkeletonWhite", "SkeletonYellow"]:
		var skel: Node2D = get_node(skel_name)
		var hitbox: Area2D = skel.get_node("AttackHitbox") as Area2D
		var shape: CollisionShape2D = hitbox.get_node("CollisionShape2D") as CollisionShape2D
		var half_w: float = (shape.shape as RectangleShape2D).size.x / 2.0

		# 玩家在右侧 → facing = 1
		player.global_position = skel.global_position + Vector2(120, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var r_hit := hitbox.position.x
		var r_shape := shape.position.x
		var r_reach: float = r_hit + r_shape + half_w  # 朝右最远覆盖

		# 玩家在左侧 → facing = -1
		player.global_position = skel.global_position + Vector2(-120, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var l_hit := hitbox.position.x
		var l_shape := shape.position.x
		var l_reach: float = absf(l_hit + l_shape) + half_w  # 朝左最远覆盖

		var tag: String = skel_name
		_check(r_hit > 0.0 and l_hit < 0.0, "%s: 命中盒锚点随朝向翻转（右 %.1f / 左 %.1f）" % [tag, r_hit, l_hit])
		_check(r_shape > 0.0 and l_shape < 0.0, "%s: 形状偏移随朝向翻转（右 %.1f / 左 %.1f）" % [tag, r_shape, l_shape])
		_check(is_equal_approx(r_hit, -l_hit), "%s: 锚点距离对称（%.1f / %.1f）" % [tag, r_hit, l_hit])
		_check(is_equal_approx(r_shape, -l_shape), "%s: 形状偏移对称（%.1f / %.1f）" % [tag, r_shape, l_shape])
		_check(is_equal_approx(r_reach, l_reach), "%s: 攻击判定距离左右一致（%.1f / %.1f）" % [tag, r_reach, l_reach])

	_finish()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PASS] %s" % what)
	else:
		_failures += 1
		print("[FAIL] %s" % what)


func _finish() -> void:
	print("SkeletonHitbox test: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
