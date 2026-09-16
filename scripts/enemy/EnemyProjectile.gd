extends Area2D
## 敌人子弹（Day 3）：直线飞行，命中玩家造成伤害，撞地形/超时销毁。


var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 0.0
var damage: int = 1

const MAX_LIFETIME: float = 2.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(direction: Vector2, speed: float) -> void:
	velocity = direction.normalized() * speed


func _physics_process(delta: float) -> void:
	# Day 4：对话期间子弹冻结，避免对话中被流弹打死
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
