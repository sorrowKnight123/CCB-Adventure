extends StaticBody2D
## Day 5：魔法屏障。默认阻挡玩家（玩家 collision_mask 含屏障层）；
## 魔法冲刺期间玩家临时移除屏障层位 → 穿过。轻微呼吸微光提示特殊。

@export var height: float = 240.0

var _t: float = 0.0


func _ready() -> void:
	add_to_group("barriers")
	# 按 height 重建碰撞形状与视觉（避免共享 sub_resource 被其他实例影响）
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16.0, height)
	$CollisionShape2D.shape = shape
	if has_node("Visual"):
		var half := height * 0.5
		$Visual.polygon = PackedVector2Array([Vector2(-8, -half), Vector2(8, -half), Vector2(8, half), Vector2(-8, half)])


func _process(delta: float) -> void:
	_t += delta
	var a := 0.55 + 0.15 * sin(_t * 3.0)
	if has_node("Visual"):
		$Visual.self_modulate = Color(1, 1, 1, a)
