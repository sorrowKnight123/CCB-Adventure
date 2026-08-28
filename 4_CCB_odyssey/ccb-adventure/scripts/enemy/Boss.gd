extends CharacterBody2D
## Day 3：Boss = 失去理智的 88。普通近战 + 冲撞 + 残血强化。
## 占位美术：大色块；88 的正式立绘/动作帧由用户后续提供。


enum State { IDLE, CHASE, WINDUP, CHARGE, ATTACK, HURT, DEAD }

signal defeated
signal health_changed(current: int, maximum: int)

@export var max_hp: int = 30
@export var speed: float = 120.0
@export var gravity: float = 1200.0
@export var detect_range: float = 400.0
@export var attack_range: float = 50.0
@export var melee_damage: int = 2
@export var contact_damage: int = 2
@export var attack_cooldown: float = 1.2
@export var attack_duration: float = 0.3

@export var charge_speed: float = 480.0
@export var charge_cooldown: float = 3.0
@export var charge_windup: float = 0.6
@export var charge_duration: float = 0.8

@export var enrage_threshold: float = 0.5
@export var knockback: float = 60.0
@export var hurt_duration: float = 0.15

@onready var visual: Polygon2D = $Visual
@onready var attack_hitbox: Area2D = $AttackHitbox

var state: State = State.IDLE
var player: CharacterBody2D = null
var facing: int = -1
var hp: int = 0
var enraged: bool = false

var attack_cooldown_timer: float = 0.0
var attack_timer: float = 0.0
var charge_cooldown_timer: float = 0.0
var charge_timer: float = 0.0
var hurt_timer: float = 0.0
var _charge_dir: int = -1
var _hit_this_attack: bool = false


func _ready() -> void:
	add_to_group("boss")
	add_to_group("enemies")
	# 已击败则不再出现（跨场景持久化）
	if GameState.boss_defeated:
		queue_free()
		return
	hp = max_hp
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	attack_hitbox.monitoring = false
	charge_cooldown_timer = charge_cooldown
	health_changed.emit(hp, max_hp)
	_update_facing()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	# Day 4：对话期间 Boss 冻结（不移动、不攻击）
	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		return

	attack_cooldown_timer = maxf(attack_cooldown_timer - delta, 0.0)
	charge_cooldown_timer = maxf(charge_cooldown_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y += gravity * delta

	match state:
		State.HURT:
			_process_hurt(delta)
		State.WINDUP:
			_process_windup(delta)
		State.CHARGE:
			_process_charge(delta)
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
	var dir := 1.0 if player.global_position.x > global_position.x else -1.0
	facing = int(dir)
	_update_facing()

	if state == State.IDLE:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if dist_x <= detect_range:
			state = State.CHASE
		return

	# CHASE
	if dist_x <= attack_range and attack_cooldown_timer <= 0.0:
		_start_attack()
	elif charge_cooldown_timer <= 0.0:
		_start_windup(dir)
	elif dist_x > detect_range * 1.5:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	else:
		velocity.x = move_toward(velocity.x, dir * speed, speed * delta)


func _start_attack() -> void:
	state = State.ATTACK
	attack_timer = attack_duration
	attack_cooldown_timer = attack_cooldown
	_hit_this_attack = false
	attack_hitbox.monitoring = true


func _process_attack(delta: float) -> void:
	attack_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, speed * delta)

	if not _hit_this_attack:
		for body in attack_hitbox.get_overlapping_bodies():
			if body.is_in_group("player"):
				body.take_damage(melee_damage, global_position)
				_hit_this_attack = true
				break

	if attack_timer <= 0.0:
		attack_hitbox.monitoring = false
		state = State.CHASE


func _start_windup(dir: int) -> void:
	state = State.WINDUP
	charge_timer = charge_windup
	_charge_dir = dir
	charge_cooldown_timer = charge_cooldown
	visual.self_modulate = Color(1.4, 0.6, 0.6)


func _process_windup(delta: float) -> void:
	charge_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	if charge_timer <= 0.0:
		_start_charge()


func _start_charge() -> void:
	state = State.CHARGE
	charge_timer = charge_duration
	_hit_this_attack = false
	attack_hitbox.monitoring = true
	_restore_visual()


func _process_charge(delta: float) -> void:
	charge_timer -= delta
	velocity.x = _charge_dir * charge_speed

	if not _hit_this_attack:
		for body in attack_hitbox.get_overlapping_bodies():
			if body.is_in_group("player"):
				body.take_damage(contact_damage, global_position)
				_hit_this_attack = true
				break

	if charge_timer <= 0.0 or is_on_wall():
		attack_hitbox.monitoring = false
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
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp, max_hp)

	if hp <= 0:
		_die()
		return

	# 残血强化：首次跌破阈值触发
	if not enraged and hp <= max_hp * enrage_threshold:
		_enrage()

	state = State.HURT
	hurt_timer = hurt_duration
	attack_hitbox.monitoring = false
	var kb_dir := 1.0 if global_position.x >= from_pos.x else -1.0
	velocity.x = kb_dir * knockback
	_flash()


func _enrage() -> void:
	enraged = true
	speed *= 1.4
	charge_cooldown *= 0.6
	_restore_visual()


func _die() -> void:
	state = State.DEAD
	GameState.boss_defeated = true
	attack_hitbox.monitoring = false
	$CollisionShape2D.set_deferred("disabled", true)
	visual.self_modulate = Color(4, 4, 4)
	defeated.emit()
	await get_tree().create_timer(0.6).timeout
	queue_free()


func _flash() -> void:
	visual.self_modulate = Color(4, 4, 4)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(visual):
		_restore_visual()


func _restore_visual() -> void:
	visual.self_modulate = Color(1, 0.4, 0.8) if enraged else Color(1, 1, 1)


func _update_facing() -> void:
	visual.scale.x = facing
	attack_hitbox.position.x = facing * 36.0
