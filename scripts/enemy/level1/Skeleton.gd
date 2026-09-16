@tool
extends CharacterBody2D
## 骷髅小怪（level1）：白 / 黄共用同一套逻辑，只换 SpriteFrames 皮肤。
## 所有数值都放在 Inspector（中文 @export）里，方便你改。
## 攻击：随机 Attack1（2/3）或 Attack2（1/3），命中帧可调。
## 注意：攻击一旦开始就不会被打断，只有攻击动画播完才结束。
## 调试可视化：索敌范围/攻击判定盒只在编辑器里显示（@tool），运行游戏不显示。

enum State { IDLE, CHASE, ATTACK, HURT, DEAD }

@export var 生命值: int = 6
@export var 移动速度: float = 60.0
@export var 重力: float = 1200.0
@export var 攻击伤害: int = 1
@export var contact_damage: int = 1
@export var 掉落普通音符数: int = 6
@export var 索敌范围: float = 150.0
@export var 攻击冷却: float = 1.2
@export var 攻击1概率: float = 2.0 / 3.0
@export var 攻击1命中帧: int = 8
@export var 攻击2命中帧: int = 7
@export var 受击时长: float = 0.2
@export var 击退力度: float = 160.0
@export var 命中盒偏移: float = 24.0  # 攻击判定盒整体相对身体的锚点距离（随朝向左右对称）
# 调试可视化（仅编辑器显示）：索敌范围（蓝圆）/ 攻击判定盒（红矩形，随朝向），改数值实时可见
@export var 调试显示范围: bool = true

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $AttackHitbox

var state := State.IDLE
var player: CharacterBody2D = null
var facing := -1
var attack_cooldown_timer := 0.0
var attack_timer := 0.0
var attack_duration := 0.0
var attack_hit_done := false
var attack_anim := "attack1"
var hurt_timer := 0.0
var _dead := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return  # 编辑器里只显示范围可视化，不初始化逻辑
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	hitbox.monitoring = true   # 常开，用于“玩家进入攻击判定盒→开始攻击”
	anim.play("idle")
	_update_facing()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _dead:
		return
	queue_redraw()  # 编辑器里实时重绘范围可视化
	attack_cooldown_timer = maxf(attack_cooldown_timer - delta, 0.0)
	if not is_on_floor():
		velocity.y += 重力 * delta

	match state:
		State.HURT:
			_process_hurt(delta)
		State.ATTACK:
			_process_attack(delta)
		_:
			_process_idle_chase(delta)

	move_and_slide()
	_update_facing()


func _process_idle_chase(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		state = State.IDLE
		anim.play("idle")
		velocity.x = move_toward(velocity.x, 0.0, 移动速度 * delta)
		return
	var dist_x := absf(player.global_position.x - global_position.x)

	# 攻击触发 = 玩家进入攻击判定盒（AttackHitbox 重叠检测）+ 冷却结束；判定盒在场景里可视化编辑
	var in_hitbox := _player_in_hitbox()
	if in_hitbox and attack_cooldown_timer <= 0.0:
		_start_attack()
		return

	if dist_x <= 索敌范围:
		state = State.CHASE
		if in_hitbox:
			# 玩家已在攻击判定盒内（攻击范围内）：CD 中不逼近，播 idle 等待
			velocity.x = move_toward(velocity.x, 0.0, 移动速度 * delta)
			anim.play("idle")
		else:
			anim.play("walk")
			var dir := 1.0 if player.global_position.x > global_position.x else -1.0
			velocity.x = move_toward(velocity.x, dir * 移动速度, 移动速度 * delta)
	else:
		state = State.IDLE
		velocity.x = move_toward(velocity.x, 0.0, 移动速度 * delta)
		anim.play("idle")


func _player_in_hitbox() -> bool:
	for body in hitbox.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func _start_attack() -> void:
	state = State.ATTACK
	attack_anim = "attack1" if randf() < 攻击1概率 else "attack2"
	anim.play(attack_anim)
	attack_timer = 0.0
	attack_hit_done = false
	attack_duration = _anim_duration(attack_anim)
	velocity.x = 0.0
	attack_cooldown_timer = 攻击冷却  # 攻击结束需等冷却才能再攻击（此前漏赋值 → 参数失效、无限连击）


func _process_attack(delta: float) -> void:
	# 攻击不可被打断：不管玩家是否离开攻击范围，都等动画播完才结束
	attack_timer += delta
	velocity.x = move_toward(velocity.x, 0.0, 移动速度 * delta)
	var sf := anim.sprite_frames
	var frame_dur := sf.get_frame_duration(attack_anim, 0) / sf.get_animation_speed(attack_anim)
	var hit_frame := 攻击1命中帧 if attack_anim == "attack1" else 攻击2命中帧
	if not attack_hit_done and attack_timer >= float(hit_frame) * frame_dur:
		attack_hit_done = true
		for body in hitbox.get_overlapping_bodies():
			if body.is_in_group("player"):
				body.take_damage(攻击伤害, global_position)
				break
	if attack_timer >= attack_duration:
		state = State.CHASE


func _process_hurt(delta: float) -> void:
	hurt_timer -= delta
	velocity.x = move_toward(velocity.x, 0.0, 移动速度 * delta)
	if hurt_timer <= 0.0:
		state = State.CHASE


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
	hurt_timer = 受击时长
	anim.play("hurt")
	var kb_dir := 1.0 if global_position.x >= from_pos.x else -1.0
	velocity.x = kb_dir * 击退力度


func _die() -> void:
	_dead = true
	state = State.DEAD
	hitbox.monitoring = false
	$CollisionShape2D.set_deferred("disabled", true)
	EnemyDrop.spawn_regular(self, 掉落普通音符数)
	anim.play("die")
	await get_tree().create_timer(_anim_duration("die")).timeout
	queue_free()


func _update_facing() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return
	# 每次帧都根据玩家方向更新朝向，确保移动/攻击方向一致
	facing = 1 if player.global_position.x > global_position.x else -1
	anim.flip_h = facing < 0
	# 命中盒整体锚点随朝向平移；形状自身的偏移（CollisionShape2D.position.x）也必须随朝向对称翻转，
	# 否则换朝向时判定盒不对称（如朝右伸 76px、朝左只伸 45px，且反方向还残留一段）。
	hitbox.position.x = facing * 命中盒偏移
	var shape_node := $AttackHitbox/CollisionShape2D
	shape_node.position.x = facing * absf(shape_node.position.x)


func _anim_duration(name: String) -> float:
	var sf := anim.sprite_frames
	var count := sf.get_frame_count(name)
	var total := 0.0
	for i in count:
		total += sf.get_frame_duration(name, i)
	return total / sf.get_animation_speed(name)


func _draw() -> void:
	## 调试范围可视化（仅编辑器显示）：蓝=索敌范围圆，红矩形=攻击判定盒（随 facing 朝向）。
	if not Engine.is_editor_hint():
		return  # 运行游戏不显示
	if not 调试显示范围:
		return
	var c := Vector2.ZERO
	draw_circle(c, 索敌范围, Color(0.3, 0.6, 1.0, 0.10))
	draw_arc(c, 索敌范围, 0, TAU, 64, Color(0.3, 0.6, 1.0, 0.45), 1.5)
	var hit_shape := hitbox.get_node("CollisionShape2D") as CollisionShape2D
	if hit_shape and hit_shape.shape is RectangleShape2D:
		var rect_size: Vector2 = (hit_shape.shape as RectangleShape2D).size
		var center := hitbox.position + hit_shape.position
		draw_rect(Rect2(center - rect_size * 0.5, rect_size), Color(1.0, 0.3, 0.3, 0.18), true)
		draw_rect(Rect2(center - rect_size * 0.5, rect_size), Color(1.0, 0.3, 0.3, 0.7), false, 1.5)
