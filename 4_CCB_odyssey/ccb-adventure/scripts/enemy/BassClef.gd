extends CharacterBody2D
## 低音谱号：远程二连发。把符号上的两个点发射出去，点没长出来之前无法攻击并会后撤。
## 占位美术：Polygon2D 色块，后续替换正式图。

enum State { IDLE, CHASE, SHOOT, EMPTY, HURT, DEAD }

@export var hp: int = 4
@export var speed: float = 70.0
@export var detect_range: float = 300.0
@export var min_range: float = 150.0
@export var shoot_cooldown: float = 2.5
@export var bullet_speed: float = 240.0
@export var bullet_damage: int = 1
@export var empty_time: float = 3.0
@export var second_shot_delay: float = 0.25

const BASS_DOT: PackedScene = preload("res://scenes/enemies/projectiles/BassDot.tscn")
const WHITE_BODY: Texture2D = preload("res://art/enemy/d_body_white.png")
const WHITE_DOT: Texture2D = preload("res://art/enemy/d_dot_white.png")

@onready var visual: Sprite2D = $Body
@onready var dot_l: Sprite2D = $DotL
@onready var dot_r: Sprite2D = $DotR
@onready var muzzle: Node2D = $Muzzle

var state: State = State.IDLE
var player: CharacterBody2D = null
var facing: int = -1

var shoot_cooldown_timer: float = 0.0
var empty_timer: float = 0.0
var shot_timer: float = 0.0
var shots_left: int = 0

var _dot_l_home: Vector2
var _dot_r_home: Vector2
var _dot_home_scale: Vector2 = Vector2(0.1, 0.1)


func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	shoot_cooldown_timer = shoot_cooldown * 0.5
	_dot_l_home = dot_l.position
	_dot_r_home = dot_r.position
	_dot_home_scale = dot_l.scale
	_update_dots()


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		return

	if player:
		facing = 1 if player.global_position.x > global_position.x else -1
		_update_facing_visual()

	shoot_cooldown_timer = maxf(shoot_cooldown_timer - delta, 0.0)
	if state == State.EMPTY:
		empty_timer -= delta
		if empty_timer <= 0.0:
			state = State.CHASE
			_update_dots()

	match state:
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		State.SHOOT:
			_process_shoot(delta)
		State.EMPTY:
			_process_empty(delta)
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
	var dir := 1.0 if player.global_position.x > global_position.x else -1.0
	facing = int(dir)

	if state == State.IDLE:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		if dist_x <= detect_range:
			state = State.CHASE
		return

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
	shots_left = 2
	shot_timer = 0.0


func _process_shoot(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, speed * delta)
	shot_timer -= delta
	if shots_left > 0 and shot_timer <= 0.0:
		var dot := dot_l if shots_left == 2 else dot_r
		_fire_dot(dot)
		shots_left -= 1
		if shots_left > 0:
			shot_timer = second_shot_delay
	if shots_left == 0:
		state = State.EMPTY
		empty_timer = empty_time
		_update_dots()


func _fire_dot(dot: Sprite2D) -> void:
	var dir := (player.global_position - global_position).normalized() if player else Vector2(facing, 0.0)

	# 发射的子弹直接使用图片切出的黑点，命中判定与视觉一致。
	var projectile := BASS_DOT.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = dot.global_position
	projectile.damage = bullet_damage
	projectile.setup(dir, bullet_speed)

	# 后仰 + 甩点：身体小幅后仰，黑点旋转并缩小甩出。
	_play_fling_tween(dot)


func _process_empty(delta: float) -> void:
	if player == null:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		return
	var dir := 1.0 if player.global_position.x > global_position.x else -1.0
	velocity.x = move_toward(velocity.x, -dir * speed, speed * delta)


func _play_fling_tween(dot: Sprite2D) -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(visual, "rotation", -0.1 * facing, 0.07)
	tw.tween_property(visual, "scale", Vector2(0.096, 0.096), 0.07)
	tw.tween_property(dot, "position", dot.position + Vector2(facing * 16.0, -10.0), 0.14)
	tw.tween_property(dot, "rotation", dot.rotation + facing * 0.5, 0.14)
	tw.tween_property(dot, "scale", dot.scale * 0.7, 0.14)

	var tw2 := create_tween()
	tw2.tween_interval(0.14)
	tw2.tween_property(visual, "rotation", 0.0, 0.12)
	tw2.tween_property(visual, "scale", Vector2(0.1, 0.1), 0.12)


func _update_facing_visual() -> void:
	# 有两个点的一面朝向玩家：玩家在右，点朝右；玩家在左，整体镜像。
	visual.flip_h = facing > 0
	if state != State.SHOOT:
		var dot_x := 41.0 if facing < 0 else -61.0
		dot_l.position.x = dot_x
		dot_r.position.x = dot_x


func _update_dots() -> void:
	var show_dots: bool = state != State.EMPTY
	dot_l.visible = show_dots
	dot_r.visible = show_dots
	if show_dots:
		_reset_dot(dot_l, _dot_l_home)
		_reset_dot(dot_r, _dot_r_home)


func _reset_dot(dot: Sprite2D, home: Vector2) -> void:
	var dot_x := 41.0 if facing > 0 else -41.0
	dot.position = Vector2(dot_x, home.y)
	dot.rotation = 0.0
	dot.scale = _dot_home_scale


func take_damage(amount: int, _from_pos: Vector2, from_magic := false) -> void:
	if state == State.DEAD:
		return
	if not from_magic:
		GameState.add_music_inspiration(GameState.MUSIC_INSPIRATION_PER_HIT)
	hp -= amount
	if hp <= 0:
		_die()
		return
	state = State.HURT
	_flash()


func _die() -> void:
	state = State.DEAD
	$CollisionShape2D.set_deferred("disabled", true)
	_flash()
	await get_tree().create_timer(0.12).timeout
	queue_free()


func _flash() -> void:
	# 黑底贴图不能用 self_modulate 提亮（黑×4仍是黑），因此受击时短暂替换为白色剪影贴图。
	var old_body := visual.texture
	var old_dot_l := dot_l.texture
	var old_dot_r := dot_r.texture
	visual.texture = WHITE_BODY
	dot_l.texture = WHITE_DOT
	dot_r.texture = WHITE_DOT
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(visual):
		visual.texture = old_body
	if is_instance_valid(dot_l):
		dot_l.texture = old_dot_l
	if is_instance_valid(dot_r):
		dot_r.texture = old_dot_r
