extends RefCounted
class_name EnemyDrop

## 统一的敌人死亡掉落。掉落物只存在于当前场景，不记录掉落实例。
const NOTE_PICKUP_SCENE: PackedScene = preload("res://scenes/items/NotePickup.tscn")

static func spawn_regular(enemy: Node2D, count: int) -> void:
	if count <= 0:
		return
	_spawn(enemy, 1, count, false)


static func spawn_elite(enemy: Node2D, count: int = 1) -> void:
	if count <= 0:
		return
	_spawn(enemy, 25, count, true)


static func _spawn(enemy: Node2D, amount: int, count: int, is_large: bool) -> void:
	if not is_instance_valid(enemy) or enemy.get_parent() == null:
		return
	var parent := enemy.get_parent()
	var spread := 34.0 if is_large else 24.0
	for index in count:
		var pickup := NOTE_PICKUP_SCENE.instantiate()
		parent.add_child(pickup)
		var angle := TAU * float(index) / float(maxi(count, 1)) + randf_range(-0.18, 0.18)
		var distance := randf_range(spread * 0.65, spread)
		var offset := Vector2(cos(angle) * distance, -randf_range(18.0, 34.0))
		pickup.global_position = enemy.global_position
		if pickup.has_method("setup_drop"):
			pickup.setup_drop(amount, is_large, offset)
		else:
			pickup.amount = amount
