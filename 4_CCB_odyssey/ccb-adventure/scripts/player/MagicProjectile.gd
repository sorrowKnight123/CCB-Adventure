extends Area2D
## 魔法弹（Day 2）：朝发射方向直线飞行，命中敌人造成伤害，撞地形/超时销毁。


var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 0.0
var damage: int = 1

const MAX_LIFETIME: float = 1.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(direction: Vector2, speed: float) -> void:
	velocity = direction.normalized() * speed


func _physics_process(delta: float) -> void:
	position += velocity * delta
	lifetime += delta
	if lifetime >= MAX_LIFETIME:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		body.take_damage(damage, global_position, true)  # true = 魔法攻击，不增加音乐灵感
	queue_free()
