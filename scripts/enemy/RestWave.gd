extends Area2D
## 休止符波纹：无伤害，命中玩家后使其僵直 1.5 秒，然后消失。

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 0.0

const MAX_LIFETIME: float = 4.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(direction: Vector2, speed: float) -> void:
	velocity = direction.normalized() * speed


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
		body.stagger(1.5)
	queue_free()
