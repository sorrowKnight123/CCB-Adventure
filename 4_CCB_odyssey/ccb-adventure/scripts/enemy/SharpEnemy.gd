extends CharacterBody2D
## 升号：近战突进刺客。招式 A「横划」直线高速冲刺；招式 B「竖劈」跳向玩家斜向砸下。
## 占位美术：Polygon2D 色块，后续替换正式图。

enum State { IDLE, CHASE, DASH_ATTACK, JUMP_ATTACK, HURT, DEAD }

@export var hp: int = 5
@export var speed: float = 90.0
@export var gravity: float = 1200.0
@export var detect_range: float = 220.0
@export var attack_range: float = 60.0
@export var damage: int = 1
@export var attack_cooldown: float = 1.2
@export var dash_speed: float = 420.0
@export var dash_duration: float = 0.3
@export var jump_velocity: float = -420.0
@export var hurt_duration: float = 0.2
@export var knockback: float = 160.0

@onready var visual: Polygon2D = $Visual
@onready var attack_hitbox: Area2D = $AttackHitbox

var state: State = State.IDLE
var player: CharacterBody2D = null
var facing: int = -1
var _attack_parity: int = 0  # 0=横划，1=竖劈

var attack_cooldown_timer: float = 0.0
var attack_timer: float = 0.0
var hurt_timer: float = 0.0
var _hit_this_attack: bool = false


func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	attack_hitbox.monitoring = false
	_update_facing()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		return

	attack_cooldown_timer = maxf(attack_cooldown_timer - delta, 0.0)

	if not is_on_floor() and state != State.JUMP_ATTACK:
		velocity.y += gravity * delta

	match state:
		State.HURT:
			_process_hurt(delta)
		State.DASH_ATTACK:
			_process_dash_attack(delta)
		State.JUMP_ATTACK:
			_process_jump_attack(delta)
		_:
			_process_idle_chase(delta)

	move_and_slide()


func _process_idle_chase(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		return

	var dist_x := absf(player.global_position.x - global_position.x)

	if state == State.IDLE:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if dist_x <= detect_range:
			state = State.CHASE
		return

	var dir := 1.0 if player.global_position.x > global_position.x else -1.0
	facing = int(dir)
	_update_facing()

	if dist_x <= attack_range and attack_cooldown_timer <= 0.0:
		_start_attack()
	elif dist_x > detect_range * 1.5:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	else:
		velocity.x = move_toward(velocity.x, dir * speed, speed * delta)


func _start_attack() -> void:
	attack_cooldown_timer = attack_cooldown
	_hit_this_attack = false
	attack_hitbox.monitoring = true
	if _attack_parity == 0:
		state = State.DASH_ATTACK
		attack_timer = dash_duration
	else:
		state = State.JUMP_ATTACK
		attack_timer = 0.6
		velocity.y = jump_velocity
		velocity.x = facing * speed * 1.5
	_attack_parity = 1 - _attack_parity


func _process_dash_attack(delta: float) -> void:
	attack_timer -= delta
	velocity.x = facing * dash_speed
	if not is_on_floor():
		velocity.y += gravity * delta
	_check_hit()
	if attack_timer <= 0.0:
		_end_attack()


func _process_jump_attack(delta: float) -> void:
	attack_timer -= delta
	if not is_on_floor():
		velocity.y += gravity * delta
	if is_on_floor() or attack_timer <= 0.0:
		_end_attack()
	_check_hit()


func _check_hit() -> void:
	if _hit_this_attack:
		return
	for body in attack_hitbox.get_overlapping_bodies():
		if body.is_in_group("player"):
			body.take_damage(damage, global_position)
			_hit_this_attack = true
			break


func _end_attack() -> void:
	attack_hitbox.monitoring = false
	_hit_this_attack = false
	state = State.CHASE


func _process_hurt(delta: float) -> void:
	hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	if hurt_timer <= 0.0:
		state = State.CHASE


func take_damage(amount: int, from_pos: Vector2, from_magic := false) -> void:
	if state == State.DEAD:
		return
	if not from_magic:
		GameState.add_music_inspiration(GameState.MUSIC_INSPIRATION_PER_HIT)
	hp -= amount
	if hp <= 0:
		_die()
		return
	state = State.HURT
	hurt_timer = hurt_duration
	attack_hitbox.monitoring = false
	var kb_dir := 1.0 if global_position.x >= from_pos.x else -1.0
	velocity.x = kb_dir * knockback
	_flash()


func _die() -> void:
	state = State.DEAD
	attack_hitbox.monitoring = false
	$CollisionShape2D.set_deferred("disabled", true)
	_flash()
	await get_tree().create_timer(0.12).timeout
	queue_free()


func _flash() -> void:
	visual.self_modulate = Color(4, 4, 4)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(visual):
		visual.self_modulate = Color(1, 1, 1)


func _update_facing() -> void:
	visual.scale.x = facing
	attack_hitbox.position.x = facing * 30.0
