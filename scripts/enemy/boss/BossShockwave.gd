extends Area2D
## Boss 冲击波：沿水平方向移动，命中玩家一次后继续飞行并自动销毁。

@export var speed: float = 360.0
@export var damage: int = 1
@export var lifetime: float = 2.0

var direction: int = 1
var _elapsed: float = 0.0
var _hit_player: bool = false
var effect_kind: String = "slam"
var _active_visual: Sprite2D = null
var _target_visual_scale: float = 0.55

@onready var jump_visual: Sprite2D = $JumpVisual
@onready var slam_visual: Sprite2D = $SlamVisual
@onready var impact_visual: Sprite2D = $ImpactVisual


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func setup(move_direction: int, move_speed: float, hit_damage: int, life: float, kind: String = "slam", target_visual_scale: float = 0.55, intro_duration: float = 0.3, initial_visual_scale: float = 0.05) -> void:
	direction = 1 if move_direction >= 0 else -1
	speed = move_speed
	damage = hit_damage
	lifetime = life
	effect_kind = kind
	scale = Vector2(direction, 1.0)
	jump_visual.visible = effect_kind == "jump"
	slam_visual.visible = effect_kind == "slam"
	impact_visual.visible = effect_kind == "impact"
	_active_visual = impact_visual if effect_kind == "impact" else jump_visual if effect_kind == "jump" else slam_visual
	_target_visual_scale = maxf(target_visual_scale, 0.0)
	_active_visual.scale = Vector2(maxf(initial_visual_scale, 0.0), maxf(initial_visual_scale, 0.0))
	var intro_tween := create_tween()
	intro_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	intro_tween.tween_property(_active_visual, "scale", Vector2(_target_visual_scale, _target_visual_scale), maxf(intro_duration, 0.01))
	if effect_kind == "impact":
		monitoring = false
		collision_mask = 0
		lifetime = minf(lifetime, 0.3)


func _physics_process(delta: float) -> void:
	if effect_kind != "impact":
		position.x += direction * speed * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _hit_player or not body.is_in_group("player"):
		return
	_hit_player = true
	body.take_damage(damage, global_position)
