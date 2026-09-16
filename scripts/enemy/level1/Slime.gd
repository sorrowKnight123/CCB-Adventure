@tool
extends CharacterBody2D
## 史莱姆基础敌人：绿色巡逻型与橙色警戒型共用脚本。
## 两种史莱姆都只有 idle 动画，接触伤害直接使用根节点的身体碰撞盒。

enum State { IDLE, PATROL, CHASE, RETURN, HURT, DEAD }
enum Behavior { PATROL, GUARD }

@export_category("基础")
@export_enum("巡逻型", "警戒型") var 行为模式: int = Behavior.PATROL
@export var 生命值: int = 3
@export var 重力: float = 1200.0
@export var 接触伤害: int = 1
@export var 掉落普通音符数: int = 3
@export var 接触伤害冷却: float = 0.8
@export var 受击时长: float = 0.12
@export var 击退力度: float = 100.0
@export var 死亡后延迟: float = 0.12
@export var 调试显示范围: bool = true

@export_category("绿色巡逻型")
@export var 巡逻速度: float = 40.0
@export var 巡逻距离: float = 160.0
@export var 边界停留时间: float = 0.3
@export_enum("向左", "向右") var 初始巡逻方向: int = 1

@export_category("橙色警戒型")
@export var 追踪速度: float = 70.0
@export var 最大追踪距离: float = 320.0
@export var 返航速度: float = 55.0
@export var 失去目标延迟: float = 0.25

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = get_node_or_null("DetectionArea") as Area2D

var state: State = State.IDLE
var player: CharacterBody2D = null
var hurt_timer: float = 0.0
var contact_cooldown_timer: float = 0.0
var boundary_pause_timer: float = 0.0
var lost_target_timer: float = 0.0
var _patrol_center_x: float = 0.0
var _patrol_left: float = 0.0
var _patrol_right: float = 0.0
var _patrol_dir: int = 1
var _home_position: Vector2
var _dead: bool = false

# 与玩家现有 Hurtbox 的兼容属性：玩家通过 body.get("contact_damage") 读取伤害。
var contact_damage: int:
	get:
		return 接触伤害


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_home_position = global_position
	_patrol_center_x = global_position.x
	_patrol_left = _patrol_center_x - absf(巡逻距离)
	_patrol_right = _patrol_center_x + absf(巡逻距离)
	_patrol_dir = 1 if 初始巡逻方向 == 1 else -1
	state = State.PATROL if 行为模式 == Behavior.PATROL else State.IDLE
	anim.play("idle")
	_update_facing()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _dead:
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D

	contact_cooldown_timer = maxf(contact_cooldown_timer - delta, 0.0)
	if hurt_timer > 0.0:
		hurt_timer -= delta

	if not is_on_floor():
		velocity.y += 重力 * delta

	if state == State.HURT:
		_process_hurt(delta)
	else:
		if 行为模式 == Behavior.PATROL:
			_process_patrol(delta)
		else:
			_process_guard(delta)

	move_and_slide()
	_process_contact_damage()
	_update_facing()


func _process_patrol(delta: float) -> void:
	state = State.PATROL
	if boundary_pause_timer > 0.0:
		boundary_pause_timer = maxf(boundary_pause_timer - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, 巡逻速度 * 5.0 * delta)
		return

	if is_on_wall() or (_patrol_dir > 0 and global_position.x >= _patrol_right) or (_patrol_dir < 0 and global_position.x <= _patrol_left):
		global_position.x = clampf(global_position.x, _patrol_left, _patrol_right)
		_patrol_dir *= -1
		boundary_pause_timer = maxf(边界停留时间, 0.0)

	velocity.x = _patrol_dir * 巡逻速度


func _process_guard(delta: float) -> void:
	if player == null:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, 追踪速度 * 4.0 * delta)
		return

	var in_detection := _player_in_detection_area()
	var home_distance := absf(global_position.x - _home_position.x)

	match state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 追踪速度 * 4.0 * delta)
			if in_detection:
				state = State.CHASE
				lost_target_timer = 0.0
		State.CHASE:
			if home_distance >= absf(最大追踪距离):
				state = State.RETURN
				lost_target_timer = 0.0
			elif in_detection:
				lost_target_timer = 0.0
				var dir := signf(player.global_position.x - global_position.x)
				if is_zero_approx(dir):
					dir = 1.0
				velocity.x = move_toward(velocity.x, dir * 追踪速度, 追踪速度 * 5.0 * delta)
			else:
				lost_target_timer += delta
				velocity.x = move_toward(velocity.x, 0.0, 追踪速度 * 5.0 * delta)
				if lost_target_timer >= maxf(失去目标延迟, 0.0):
					state = State.RETURN
					lost_target_timer = 0.0
		State.RETURN:
			if in_detection and home_distance < absf(最大追踪距离):
				state = State.CHASE
				lost_target_timer = 0.0
			else:
				var to_home := _home_position.x - global_position.x
				if absf(to_home) <= 2.0:
					global_position.x = _home_position.x
					velocity.x = 0.0
					state = State.IDLE
				else:
					velocity.x = move_toward(velocity.x, signf(to_home) * 返航速度, 返航速度 * 5.0 * delta)
		_:
			state = State.IDLE


func _process_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 击退力度 * 4.0 * delta)
	if hurt_timer <= 0.0:
		state = State.PATROL if 行为模式 == Behavior.PATROL else State.CHASE


func _process_contact_damage() -> void:
	if contact_cooldown_timer > 0.0 or body_shape == null or body_shape.shape == null:
		return

	# 复用根节点的身体形状查询玩家，不创建第二个接触伤害区域。
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_shape.shape
	query.transform = body_shape.global_transform
	query.collision_mask = 2  # 玩家 CharacterBody2D 所在层
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	for result in get_world_2d().direct_space_state.intersect_shape(query, 8):
		var body := result.get("collider") as Node2D
		if body != null and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(接触伤害, global_position)
			contact_cooldown_timer = maxf(接触伤害冷却, 0.0)
			break


func _player_in_detection_area() -> bool:
	if detection_area == null or not detection_area.monitoring:
		return false
	for body in detection_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func take_damage(amount: int, from_pos: Vector2, from_magic := false) -> void:
	if _dead:
		return
	if not from_magic:
		GameState.add_music_inspiration(GameState.MUSIC_INSPIRATION_PER_HIT)
	生命值 -= amount
	if 生命值 <= 0:
		_die()
		return

	state = State.HURT
	hurt_timer = maxf(受击时长, 0.0)
	var kb_dir := 1.0 if global_position.x >= from_pos.x else -1.0
	velocity.x = kb_dir * 击退力度
	_flash()


func _die() -> void:
	_dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	EnemyDrop.spawn_regular(self, 掉落普通音符数)
	if is_instance_valid(body_shape):
		body_shape.set_deferred("disabled", true)
	_flash()
	await get_tree().create_timer(maxf(死亡后延迟, 0.0)).timeout
	if is_instance_valid(self):
		queue_free()


func _flash() -> void:
	anim.self_modulate = Color(4.0, 4.0, 4.0, 1.0)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(anim):
		anim.self_modulate = Color.WHITE


func _update_facing() -> void:
	var direction := _patrol_dir
	if 行为模式 == Behavior.GUARD and absf(velocity.x) > 0.1:
		direction = 1 if velocity.x > 0.0 else -1
	anim.flip_h = direction < 0


func _draw() -> void:
	if not Engine.is_editor_hint() or not 调试显示范围:
		return
	if 行为模式 == Behavior.PATROL:
		draw_line(Vector2(_patrol_left - global_position.x, 4.0), Vector2(_patrol_right - global_position.x, 4.0), Color(0.3, 0.7, 1.0, 0.65), 2.0)
	else:
		var shape_node := get_node_or_null("DetectionArea/CollisionShape2D") as CollisionShape2D
		if shape_node and shape_node.shape is CircleShape2D:
			var radius := (shape_node.shape as CircleShape2D).radius
			draw_arc(shape_node.position, radius, 0.0, TAU, 64, Color(0.3, 0.7, 1.0, 0.5), 2.0)
	var rect_shape := body_shape.shape as RectangleShape2D
	if rect_shape:
		var rect := Rect2(body_shape.position - rect_shape.size * 0.5, rect_shape.size)
		draw_rect(rect, Color(1.0, 0.3, 0.3, 0.12), true)
		draw_rect(rect, Color(1.0, 0.3, 0.3, 0.7), false, 1.5)
