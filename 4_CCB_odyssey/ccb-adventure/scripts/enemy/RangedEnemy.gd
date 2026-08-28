extends CharacterBody2D
## Day 3：远程敌人。保持距离射击，可受伤 / 死亡 / 击退。
## 占位美术：Polygon2D 色块；正式美术与动画后续替换。


const ENEMY_PROJECTILE: PackedScene = preload("res://scenes/enemies/projectiles/EnemyProjectile.tscn")

enum State { IDLE, CHASE, SHOOT, HURT, DEAD }

@export var hp: int = 2
@export var speed: float = 80.0
@export var gravity: float = 1200.0
@export var detect_range: float = 300.0
@export var min_range: float = 140.0
@export var shoot_cooldown: float = 2.0
@export var bullet_speed: float = 300.0
@export var bullet_damage: int = 1
@export var hurt_duration: float = 0.2
@export var knockback: float = 160.0

@onready var visual: Sprite2D = $Sprite2D
@onready var muzzle: Node2D = $Muzzle

var state: State = State.IDLE
var player: CharacterBody2D = null
var facing: int = -1

var shoot_cooldown_timer: float = 0.0
var hurt_timer: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
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

	shoot_cooldown_timer = maxf(shoot_cooldown_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y += gravity * delta

	match state:
		State.HURT:
			_process_hurt(delta)
		State.SHOOT:
			_process_shoot(delta)
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
	var dir := 1.0 if player.global_position.x > global_position.x else -1.0
	facing = int(dir)
	_update_facing()

	if state == State.IDLE:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if dist_x <= detect_range:
			state = State.CHASE
		return

	# CHASE：远则靠近、近则后撤、中间射击
	if dist_x > detect_range * 1.5:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	elif dist_x < min_range:
		velocity.x = move_toward(velocity.x, -dir * speed, speed * delta)
	elif shoot_cooldown_timer <= 0.0:
		_start_shoot()
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)


func _start_shoot() -> void:
	state = State.SHOOT
	shoot_cooldown_timer = shoot_cooldown
	var bullet := ENEMY_PROJECTILE.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.damage = bullet_damage
	bullet.setup(Vector2(facing, 0.0), bullet_speed)


func _process_shoot(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, speed * delta)
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
	var kb_dir := 1.0 if global_position.x >= from_pos.x else -1.0
	velocity.x = kb_dir * knockback
	_flash()


func _die() -> void:
	state = State.DEAD
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
	muzzle.position.x = facing * 20.0
