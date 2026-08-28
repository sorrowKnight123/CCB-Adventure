extends Area2D
## 钢琴精英招式的下坠音符块：直线下落，命中玩家造成伤害后消失。

var velocity: Vector2 = Vector2(0, 260.0)
var damage: int = 1
var lifetime: float = 0.0

const MAX_LIFETIME: float = 3.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		return
	position += velocity * delta
	lifetime += delta
	if lifetime >= MAX_LIFETIME:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.take_damage(damage, global_position)
	queue_free()
