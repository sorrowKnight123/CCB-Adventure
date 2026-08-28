extends CharacterBody2D
## Day 2：近战敌人。状态机 IDLE → CHASE → ATTACK，可受伤 / 死亡 / 击退。
## 占位美术：Polygon2D 色块；正式美术与动画后续替换。


enum State { IDLE, CHASE, ATTACK, HURT, DEAD }

@export var hp: int = 3
@export var speed: float = 90.0
@export var gravity: float = 1200.0
@export var detect_range: float = 180.0
@export var attack_range: float = 40.0
@export var damage: int = 1
@export var attack_cooldown: float = 1.0
@export var attack_duration: float = 0.25
@export var hurt_duration: float = 0.2
@export var knockback: float = 160.0
# 可选巡逻：patrol_left < patrol_right 时启用；未启用时保持原行为（默认关闭，不影响旧测试）。
@export var patrol_left: float = -1.0
@export var patrol_right: float = -1.0

@onready var visual: Polygon2D = $Visual
@onready var attack_hitbox: Area2D = $AttackHitbox

var state: State = State.IDLE
var player: CharacterBody2D = null
var facing: int = -1
var _patrol_dir: int = 1

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

	# Day 4：对话期间敌人冻结（不移动、不攻击）
	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		return

	attack_cooldown_timer = maxf(attack_cooldown_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y += gravity * delta

	match state:
		State.HURT:
			_process_hurt(delta)
		State.ATTACK:
			_process_attack(delta)
		_:
			_process_idle_chase(delta)

	move_and_slide()


func _process_idle_chase(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		return

	var dist_x := absf(player.global_position.x - global_position.x)

	if state == State.IDLE:
		if patrol_left >= 0.0 and patrol_right > patrol_left:
			_process_patrol(delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if dist_x <= detect_range:
			state = State.CHASE
		return

	# CHASE
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


func _process_patrol(delta: float) -> void:
	## 简单往返巡逻：只在 IDLE 且未发现玩家时生效。
	if global_position.x <= patrol_left:
		_patrol_dir = 1
	elif global_position.x >= patrol_right:
		_patrol_dir = -1
	facing = _patrol_dir
	_update_facing()
	velocity.x = move_toward(velocity.x, _patrol_dir * speed, speed * delta)


func _process_attack(delta: float) -> void:
	attack_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, speed * delta)

	if not _hit_this_attack:
		for body in attack_hitbox.get_overlapping_bodies():
			if body.is_in_group("player"):
				body.take_damage(damage, global_position)
				_hit_this_attack = true
				break

	if attack_timer <= 0.0:
		attack_hitbox.monitoring = false
		attack_cooldown_timer = attack_cooldown
		state = State.CHASE


func _process_hurt(delta: float) -> void:
	hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	if hurt_timer <= 0.0:
		state = State.CHASE


func _start_attack() -> void:
	state = State.ATTACK
	attack_timer = attack_duration
	_hit_this_attack = false
	attack_hitbox.monitoring = true


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
	attack_hitbox.position.x = facing * 28.0
