@tool
extends CharacterBody2D
## 蝙蝠小怪（level1 飞行怪）：悬空移动，不落地。
## 行为：待机睡觉(sleep) → 玩家进入索敌范围惊醒(wakeup) → 追击(run，水平+垂直跟随) →
##       攻击范围 X+Y 达标且冷却结束 → attack1(2/3 概率) / attack2(1/3 概率) → 命中帧判定 → 冷却。
## 所有数值中文 @export（Inspector 可调）；动画 AnimatedSprite2D + SpriteFrames（bat_frames.tres）。
## 调试可视化：索敌范围/攻击判定盒只在编辑器里显示（@tool），运行游戏不显示。

enum State { SLEEP, WAKEUP, IDLE, CHASE, ATTACK, HURT, DEAD }

@export var 生命值: int = 6
@export var 移动速度: float = 80.0
@export var 攻击伤害: int = 1
@export var contact_damage: int = 1
@export var 掉落普通音符数: int = 4
@export var 掉落大音符数量: int = 0
@export var 索敌范围: float = 200.0
@export var 攻击冷却: float = 1.2
@export var 攻击1概率: float = 2.0 / 3.0
@export var 攻击1命中帧: int = 4
@export var 攻击2命中帧: int = 5
@export var 受击时长: float = 0.2
@export var 击退力度: float = 160.0
@export var 命中盒偏移: float = 28.0
# 追击时垂直跟随玩家的速度系数（0=不跟y，1=全速跟y）
@export var 垂直跟随系数: float = 0.6
# 悬停浮动幅度
@export var 浮动幅度: float = 8.0
# 调试可视化（仅编辑器显示）：索敌范围（蓝圆）/ 攻击判定盒（红矩形，随朝向），改数值实时可见
@export var 调试显示范围: bool = true

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $AttackHitbox

var state := State.SLEEP
var player: CharacterBody2D = null
var facing := -1
var attack_cooldown_timer := 0.0
var attack_timer := 0.0
var attack_duration := 0.0
var attack_hit_done := false
var attack_anim := "attack1"
var hurt_timer := 0.0
var _hover_time := 0.0
var _dead := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return  # 编辑器里只显示范围可视化，不初始化逻辑
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	hitbox.monitoring = true
	anim.play("sleep")
	_update_facing()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _dead:
		return
	queue_redraw()  # 编辑器里实时重绘范围可视化
	attack_cooldown_timer = maxf(attack_cooldown_timer - delta, 0.0)
	_hover_time += delta
	match state:
		State.HURT:
			_process_hurt(delta)
		State.ATTACK:
			_process_attack(delta)
		_:
			_process_neutral(delta)
	move_and_slide()
	_update_facing()


## 中立状态：睡眠 / 惊醒 / 待机飞行 / 追击
func _process_neutral(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		state = State.SLEEP
		anim.play("sleep")
		velocity = Vector2.ZERO
		return
	var dist_x := absf(player.global_position.x - global_position.x)
	var dist_y := absf(player.global_position.y - global_position.y)

	match state:
		State.SLEEP:
			anim.play("sleep")
			velocity = Vector2.ZERO
			if dist_x <= 索敌范围 and dist_y <= 索敌范围 * 0.6:
				state = State.WAKEUP
				anim.play("wakeup")
				anim.animation_finished.connect(_on_wakeup_done, CONNECT_ONE_SHOT)
		State.WAKEUP:
			velocity = Vector2.ZERO  # 惊醒动画播完前不动
		State.IDLE:
			anim.play("idle_fly")
			_hover(delta)
		State.CHASE:
			anim.play("run")
			# 攻击触发 = 玩家进入攻击判定盒（AttackHitbox 重叠检测）+ 冷却结束；判定盒在场景里可视化编辑
			var in_hitbox := _player_in_hitbox()
			if in_hitbox and attack_cooldown_timer <= 0.0:
				_start_attack()
			elif in_hitbox:
				# 玩家已在攻击判定盒内但冷却中 → 不追击，悬停等待
				_hover(delta)
			else:
				# 朝玩家移动：水平 + 垂直跟随
				var dir := 1.0 if player.global_position.x > global_position.x else -1.0
				velocity.x = move_toward(velocity.x, dir * 移动速度, 移动速度 * delta)
				var v_y := signf(player.global_position.y - global_position.y) * 移动速度 * 垂直跟随系数
				velocity.y = move_toward(velocity.y, v_y, 移动速度 * 垂直跟随系数 * delta)
			# 玩家离开索敌范围 → 回去睡觉
			if dist_x > 索敌范围 or dist_y > 索敌范围 * 0.8:
				state = State.SLEEP
				velocity = Vector2.ZERO


func _player_in_hitbox() -> bool:
	for body in hitbox.get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func _on_wakeup_done() -> void:
	if state == State.WAKEUP:
		state = State.CHASE


func _start_attack() -> void:
	state = State.ATTACK
	attack_anim = "attack1" if randf() < 攻击1概率 else "attack2"
	anim.play(attack_anim)
	attack_timer = 0.0
	attack_hit_done = false
	attack_duration = _anim_duration(attack_anim)
	velocity = Vector2.ZERO
	attack_cooldown_timer = 攻击冷却  # §13.6：冷却计时器必须赋值，否则无限连击


func _process_attack(delta: float) -> void:
	# 攻击不可打断：不管玩家是否离开攻击范围，都等动画播完才结束
	attack_timer += delta
	velocity = Vector2.ZERO
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
	velocity.y = move_toward(velocity.y, 0.0, 移动速度 * delta)
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
	EnemyDrop.spawn_elite(self, 掉落大音符数量)
	anim.play("die")
	await get_tree().create_timer(_anim_duration("die")).timeout
	queue_free()


func _hover(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 移动速度 * delta)
	velocity.y = sin(_hover_time * 3.0) * 浮动幅度


func _update_facing() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return
	# 每帧按玩家方向更新朝向；命中盒锚点 + 形状偏移都要随朝向对称翻转（§13.6）
	facing = 1 if player.global_position.x > global_position.x else -1
	anim.flip_h = facing > 0  # 素材原始朝左：玩家在右(facing=1)时翻转朝右，在左时不翻转
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
