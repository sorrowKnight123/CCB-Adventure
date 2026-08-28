extends CharacterBody2D
## 77 —— 魔法少女（Day 1）：移动 / 跳跃 / 冲刺 / 近战挥杖 / 爱心魔法。
## Day 2：HP / 受伤 / 死亡 / 重生 + 近战命中伤害。
## Day 4：二段跳能力 + 检查点复活 + 跨场景状态（GameState）。
## Day 9：三段连续近战（attack1 轻挥 1-4 帧 / attack2 挥击 5-9 / attack3 重斩 10-17），
##        连击窗口 = 当前段动画时长；窗口内点击升段、长按自动衔接、第三段后循环回第一段。
## 占位实现：用图标和颜色代表角色与状态，正式美术与动画后续替换。


enum State { IDLE, RUN, JUMP, ATTACK, DASH, CLIMB, CROUCH, FLIGHT, HEAL, SIT }

signal health_changed(current: int, maximum: int)

@export var speed: float = 240.0
@export var acceleration: float = 1600.0
@export var friction: float = 1600.0
@export var gravity: float = 1200.0
@export var jump_velocity: float = -600.0  # 最大跳跃高度约150px（重力1200）
@export var coyote_time: float = 0.1
@export var jump_buffer: float = 0.1

@export var dash_speed: float = 500.0
@export var dash_duration: float = 0.3  # 冲刺距离翻倍（速度不变，时长/无敌帧翻倍）
@export var dash_cooldown: float = 0.6

@export var magic_speed: float = 600.0
@export var magic_cooldown: float = 0.3

# 魔法攀升：贴墙时继续朝墙推即可骑扫帚沿墙上升。
@export var climb_speed: float = 160.0
@export var climb_jump_away_speed: float = 260.0
# 魔法飞行：长按 G 蓄力后朝面朝方向直线飞行。
@export var flight_charge_duration: float = 1.0
@export var flight_speed_multiplier: float = 3.0
@export var flight_cancel_jump_speed: float = 120.0
# 下蹲 + 跳跃可落到下一层：短暂忽略单向平台层。
@export var drop_through_duration: float = 0.18

# 相机缩放：默认 1 是最大视野（最远），滚轮可放大到 4（面积1/16，边长1/4）。
@export var camera_zoom_min: float = 1.0
@export var camera_zoom_max: float = 4.0
@export var camera_zoom_step: float = 0.05

# 手感：跳跃键提前松开时，把上升速度削减到这个值（负值=仍向上，但更矮）。
@export var jump_cut_velocity: float = -160.0
# 打击感：命中顿帧 / 镜头震动。
@export var hitstop_duration: float = 0.045
@export var camera_shake_decay: float = 6.0

var max_hp: int = GameState.MAX_HP
@export var melee_damage: int = 1
@export var magic_damage: int = 2
@export var invincible_time: float = 0.5
@export var has_double_jump: bool = false
@export var has_magic_dash: bool = false
@export var has_magic_climb: bool = false
@export var has_magic_flight: bool = false

const MAGIC_PROJECTILE: PackedScene = preload("res://scenes/player/MagicProjectile.tscn")
# Day 5：魔法屏障专用碰撞层（layer 4 = bit 3 = 8）。玩家默认与其碰撞，魔法冲刺期间无视。
const BARRIER_LAYER: int = 8
const ONE_WAY_LAYER: int = 16
const PLAYER_LAYER: int = 2

# Day 9：三段连击（1-4 轻挥 → 5-9 挥击 → 10-17 重斩）。17 帧 AI 图集画布/比例/脚底/中心
#   均不一致，已由 entity/77/动作/align_attack.py 统一对齐后打包进 art/attack.png。
#   此处仅控制「攻击美术原始朝向」：true=朝左。若实际朝向相反，改成 false 即可（一行切换）。
const ATTACK_ART_FACES_LEFT := true

# Day 7：跑步/冲刺/跳跃动画。run.png（14 帧，约 10fps 循环，帧数/时长由编辑器手调）
#   与 dash.png（单帧，冲刺与跳跃共用）均由 Player.tscn 里的 AnimationPlayer 关键帧动画驱动，
#   脚本只负责按状态切换动画名。dash.png 内容 778px 高，比 run 帧(320px)大，
#   动画关键帧里单独设了 scale 0.085 统一大小（run 为 0.31）。

# 留声机存档：sit 用独立 Sprite2D（SitSprite）+ 补间淡入/淡出，避免被 AnimationPlayer 覆盖
const SIT_SCALE := Vector2(0.08, 0.08)
const SIT_POS := Vector2(-1, -13)

@onready var sprite: Sprite2D = $Sprite2D
@onready var action_sprite: Sprite2D = $ActionSprite
@onready var sit_sprite: Sprite2D = $SitSprite
@onready var climb_sprite: AnimatedSprite2D = $ClimbSprite
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var muzzle: Node2D = $Muzzle
@onready var player_collision: CollisionShape2D = $CollisionShape2D
@onready var camera: Camera2D = $Camera2D
@onready var charge_sprite: Sprite2D = $ChargeSprite
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var state: State = State.IDLE
var facing: int = 1
var dash_direction: int = 1
var wall_dir: int = 1  # 攀升时墙所在侧：1=右侧墙，-1=左侧墙（用于计算远离墙的跳跃方向）
var flight_direction: int = 1
var _flight_charge_time: float = 0.0
var _is_charging_flight: bool = false
var _is_dash_intangible: bool = false
var _heal_chant_time: float = 0.0

var hp: int = 0
var air_jumps: int = 0
var default_collision_position: Vector2
var _is_collision_shrunk: bool = false
var default_collision_shape: CapsuleShape2D

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var attack_timer: float = 0.0
var magic_cooldown_timer: float = 0.0
var invincible_timer: float = 0.0
var stagger_timer: float = 0.0
var shake_timer: float = 0.0
var shake_strength: float = 0.0
var _is_drop_through: bool = false
var _danger_cooldown: float = 0.0
var _hurt_flash_timer: float = 0.0
var _death_sequence_running: bool = false
var _landing_timer: float = 0.0
var _air_start_y: float = 0.0
var _was_on_floor: bool = true
var _hitstop_active: bool = false

var _melee_hit_set: Dictionary = {}
var _current_action: String = ""

# Day 9：连击状态。combo_stage = 1/2/3 表示当前段；0 = 未攻击。
var combo_stage: int = 0
var _attack_press_queued: bool = false   # 攻击动画进行中按下的下一击（窗口内缓冲）
const BODY_HALF_W := 200.0   # 胶囊体半径（半宽）

func _ready() -> void:
	add_to_group("player")
	default_collision_shape = player_collision.shape as CapsuleShape2D
	default_collision_position = player_collision.position
	hp = GameState.hp
	has_double_jump = GameState.has_double_jump
	has_magic_dash = GameState.has_magic_dash
	has_magic_climb = GameState.has_magic_climb
	has_magic_flight = GameState.has_magic_flight
	collision_layer = PLAYER_LAYER
	collision_mask |= BARRIER_LAYER  # 默认与魔法屏障碰撞
	air_jumps = 1 if has_double_jump else 0
	health_changed.emit(hp, max_hp)
	_update_facing(0.0)
	_update_visual()
	call_deferred("_apply_spawn")


func _input(event: InputEvent) -> void:
	# 鼠标滚轮缩放镜头：默认 1 = 最大视野（最远），向上滚放大到 4。
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		var target := camera.zoom.x
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			target = clampf(target + camera_zoom_step, camera_zoom_min, camera_zoom_max)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target = clampf(target - camera_zoom_step, camera_zoom_min, camera_zoom_max)
		else:
			return
		camera.zoom = Vector2(target, target)

func _restore_collision_shape() -> void:
	if _is_collision_shrunk:
		player_collision.shape = default_collision_shape
		player_collision.position = default_collision_position
		_is_collision_shrunk = false
	
func _shrink_collision() -> void:
	if _is_collision_shrunk:return
	var old_total = default_collision_shape.height + 2.0 * default_collision_shape.radius
	var new_total = old_total * 0.75  # 取四分之三
	var new_height = new_total - 2.0 * default_collision_shape.radius
	var new_shape = CapsuleShape2D.new()
	new_shape.radius = default_collision_shape.radius
	new_shape.height = new_height
	player_collision.shape = new_shape
	# 下移中心使得底部位置不变
	var offset_y = -(old_total - new_total) / 2.0
	player_collision.position = Vector2(
		default_collision_position.x,
		default_collision_position.y - offset_y
	)
	_is_collision_shrunk = true
	
func _apply_spawn() -> void:
	var matched := false
	for sp in get_tree().get_nodes_in_group("spawn_points"):
		if sp.id == GameState.spawn_id:
			global_position = sp.global_position
			matched = true
			break
	if not matched:
		global_position = GameState.spawn_position
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.reset_smoothing()


func grant_double_jump() -> void:
	has_double_jump = true
	GameState.has_double_jump = true
	air_jumps = 1


func grant_magic_dash() -> void:
	has_magic_dash = true
	GameState.has_magic_dash = true


func grant_magic_climb() -> void:
	has_magic_climb = true
	GameState.has_magic_climb = true


func grant_magic_flight() -> void:
	has_magic_flight = true
	GameState.has_magic_flight = true


func _near_phonograph() -> bool:
	var ph := get_tree().get_first_node_in_group("phonograph")
	return ph != null and is_instance_valid(ph) and ph.has_method("can_interact") and ph.can_interact()


func restore_full_hp() -> void:
	hp = max_hp
	GameState.hp = hp
	health_changed.emit(hp, max_hp)


func start_sit() -> void:
	_landing_timer = 0.0
	_restore_collision_shape()
	state = State.SIT
	velocity = Vector2.ZERO
	sit_sprite.position = SIT_POS
	sit_sprite.scale = SIT_SCALE
	sit_sprite.visible = true
	sit_sprite.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(sit_sprite, "modulate:a", 1.0, 0.2)
	_update_visual()


func exit_sit() -> void:
	if state != State.SIT:
		return
	var tw := create_tween()
	tw.tween_property(sit_sprite, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void:
		sit_sprite.visible = false
		state = State.IDLE
		_update_visual()
	)


func _heal_tier() -> int:
	return clamp(GameState.heal_tier, 0, GameState.HEAL_TIERS.size() - 1)


func _heal_config() -> Dictionary:
	return GameState.HEAL_TIERS[_heal_tier()]


func _try_start_heal() -> bool:
	if not is_on_floor():
		return false
	if hp >= max_hp:
		return false
	var cfg := _heal_config()
	if not GameState.spend_music_inspiration(int(cfg["cost"])):
		return false
	_heal_chant_time = 0.0
	state = State.HEAL
	velocity.x = 0.0
	_update_visual()
	return true


func _process_heal(delta: float) -> void:
	if not Input.is_action_pressed("heal") or not is_on_floor():
		_cancel_heal()
		return
	_heal_chant_time += delta
	var cfg := _heal_config()
	if _heal_chant_time < float(cfg["chant_time"]):
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		_update_visual()
		return
	# 吟唱完成：回复 HP，若仍按住且灵感足够则自动继续下一轮
	var heal_amount: int = int(cfg["heal"])
	hp = mini(hp + heal_amount, max_hp)
	GameState.hp = hp
	health_changed.emit(hp, max_hp)
	_heal_chant_time = 0.0
	_play_heal_finish_visual()
	if not Input.is_action_pressed("heal"):
		state = State.IDLE
		_update_visual()
		return
	if not _try_start_heal():
		state = State.IDLE
		_update_visual()


func _cancel_heal() -> void:
	if state != State.HEAL:
		return
	state = State.IDLE
	_heal_chant_time = 0.0
	_update_visual()


func _play_heal_finish_visual() -> void:
	# 占位：若后续生成了 heal 动画，这里可切换为 heal 完成特效
	pass


func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_process_camera_shake(delta)
	_update_landing_state(delta)

	# 兜底：若冲刺被其他操作打断（攻击/下蹲/爬墙/存档等），确保无敌标志复位
	if _is_dash_intangible and state != State.DASH:
		_set_dash_intangible(false)

	# 留声机存档：sit 状态绝对优先，完全冻结，只等留声机（按 E）退出
	if state == State.SIT:
		velocity = Vector2.ZERO
		_update_visual()
		return

	# 落地动画：0.5s 下蹲→站起；玩家操作可打断
	if _landing_timer > 0.0:
		if _landing_interrupted():
			_cancel_landing()
		else:
			velocity.x = move_toward(velocity.x, 0.0, friction * delta)
			if not is_on_floor():
				velocity.y += gravity * delta
			move_and_slide()
			_update_visual()
			return

	# 休止符僵直：期间无法操作，只施加重力与落地判定
	if stagger_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		_update_visual()
		return

	# Day 3：对话期间暂停操作（只施加重力与落地判定）
	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		if state == State.ATTACK:
			melee_hitbox.visible = false
			melee_hitbox.monitoring = false
		combo_stage = 0
		_restore_collision_shape()
		state = State.IDLE
		_is_charging_flight = false
		_set_dash_intangible(false)
		collision_mask |= BARRIER_LAYER  # 若对话打断了魔法冲刺/攀升，确保恢复屏障碰撞
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
			state = State.JUMP
		move_and_slide()
		if is_on_floor():
			coyote_timer = coyote_time
			air_jumps = 1 if has_double_jump else 0
			if _is_collision_shrunk and state != State.JUMP and state != State.DASH:
				_restore_collision_shape()
		_update_visual()
		return

	# 回血吟唱：松手 / 受伤打断；移动、攻击、跳跃不会打断
	if state == State.HEAL:
		_process_heal(delta)
		_update_drop_through()
		move_and_slide()
		_update_visual()
		return

	var input_dir := Input.get_axis("move_left", "move_right")

	# 可变跳跃高度：上升中提前松开跳跃，削减上升速度。
	if Input.is_action_just_released("jump") and velocity.y < jump_cut_velocity:
		velocity.y = jump_cut_velocity

	# 下蹲中移动/跳跃/冲刺/攻击/魔法都会立刻打断下蹲，并在同一帧执行对应动作。
	# 特殊情况：S+Space 仍视为“下穿平台”，不在这里打断，由 _process_crouch 处理。
	var crouch_interrupted := state == State.CROUCH and (
		absf(input_dir) > 0.1
		or (Input.is_action_just_pressed("jump") and not Input.is_action_pressed("crouch"))
		or (Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0)
		or Input.is_action_just_pressed("attack")
		or (Input.is_action_just_pressed("magic") and magic_cooldown_timer <= 0.0)
	)
	if crouch_interrupted:
		_restore_collision_shape()
		state = State.IDLE

	# 魔法飞行蓄力：长按 G 达到 flight_charge_duration 后松开即起飞。
	if Input.is_action_just_pressed("flight") and has_magic_flight and not _is_charging_flight:
		if state != State.ATTACK and state != State.DASH and state != State.CROUCH and state != State.FLIGHT:
			_is_charging_flight = true
			_flight_charge_time = 0.0

	if _is_charging_flight:
		_process_flight_charge(delta)
		_update_drop_through()
		move_and_slide()
		_update_visual()
		return

	if state == State.CROUCH:
		_process_crouch(input_dir, delta)
	elif state == State.CLIMB:
		_process_climb(input_dir, delta)
	elif state == State.FLIGHT:
		_process_flight(delta)
	else:
		if state != State.ATTACK and state != State.DASH and _can_start_climb(input_dir):
			_start_climb()
		elif state != State.ATTACK and state != State.DASH and Input.is_action_pressed("crouch") and is_on_floor():
			_start_crouch()
		else:
			if Input.is_action_pressed("heal") and not _near_phonograph() and _try_start_heal():
				_update_drop_through()
				move_and_slide()
				_update_visual()
				return

			if Input.is_action_just_pressed("jump"):
				jump_buffer_timer = jump_buffer
				if state == State.ATTACK:
					_cancel_attack_on_jump()  # 攻击后摇可被跳跃取消：立即切到跳跃状态

			if Input.is_action_just_pressed("dash")  and dash_cooldown_timer <= 0.0:
				_start_dash(input_dir)

			if Input.is_action_just_pressed("attack"):
				if state != State.ATTACK:
					_play_attack(1)             # 第 1 段：全新连击（也打断冲刺/跳跃状态）
				else:
					_attack_press_queued = true  # 攻击中按下 → 缓冲为下一段（连击窗口）

			if Input.is_action_just_pressed("magic")  and magic_cooldown_timer <= 0.0:
				_cast_magic()

			if state == State.DASH:
				_process_dash(delta)
			elif state == State.ATTACK:
				_process_attack(input_dir, delta)
			else:
				_process_normal(input_dir, delta)

	_update_drop_through()
	move_and_slide()

	if _is_drop_through and is_on_floor():
		_is_drop_through = false

	_check_danger()
	if _death_sequence_running:
		return  # 死亡/地刺流程优先，不再执行后续落地/动画切换

	# 落地瞬间立即进入落地动画，避免 fall 与 land 之间出现 idle 帧
	if not _was_on_floor and is_on_floor():
		_start_landing()

	if state == State.FLIGHT:
		# 只被墙停住；地板/单向平台不算墙，避免起步时贴地误判。
		if is_on_wall():
			state = State.IDLE
			velocity = Vector2.ZERO

	if state == State.CROUCH:
		if not is_on_floor():
			_restore_collision_shape()
			state = State.JUMP
		elif _landing_timer <= 0.0 and not Input.is_action_pressed("crouch"):
			_restore_collision_shape()
			state = State.IDLE

	if is_on_floor():
		coyote_timer = coyote_time
		air_jumps = 1 if has_double_jump else 0

	# 攀升退出条件：落地 / 离墙 / 松开或反向推墙
	if state == State.CLIMB:
		if is_on_floor():
			state = State.IDLE
		elif not is_on_wall():
			state = State.JUMP
			velocity.x = -float(wall_dir) * climb_jump_away_speed * 0.5
		elif absf(input_dir) < 0.1 or signf(input_dir) != float(wall_dir):
			state = State.JUMP
			velocity.x = -float(wall_dir) * climb_jump_away_speed * 0.5

	_update_facing(input_dir)
	_update_state()
	# 只要状态变为 IDLE，就恢复碰撞盒（如果当前是缩小状态）
	if state == State.IDLE and _is_collision_shrunk:
		_restore_collision_shape()
	_update_visual()


func _tick_timers(delta: float) -> void:
	coyote_timer = maxf(coyote_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	magic_cooldown_timer = maxf(magic_cooldown_timer - delta, 0.0)
	invincible_timer = maxf(invincible_timer - delta, 0.0)
	stagger_timer = maxf(stagger_timer - delta, 0.0)
	_danger_cooldown = maxf(_danger_cooldown - delta, 0.0)
	_hurt_flash_timer = maxf(_hurt_flash_timer - delta, 0.0)


func stagger(duration: float) -> void:
	## 休止符命中：僵直期间无法操作（移动/跳跃/冲刺/攻击/魔法），但重力仍生效。
	stagger_timer = maxf(stagger_timer, duration)


# ---- 打击感：顿帧与镜头震动 ----

func _start_camera_shake(duration: float, strength: float) -> void:
	shake_timer = maxf(shake_timer, duration)
	shake_strength = maxf(shake_strength, strength)


func _process_camera_shake(delta: float) -> void:
	if shake_timer <= 0.0:
		return
	shake_timer -= delta
	var current := shake_strength * maxf(shake_timer, 0.0) / camera_shake_decay
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * current
	if shake_timer <= 0.0:
		shake_timer = 0.0
		shake_strength = 0.0
		camera.offset = Vector2.ZERO


func _apply_hitstop(duration: float) -> void:
	## 命中顿帧：把全局 time_scale 短暂压到 0，用忽略 time_scale 的计时器恢复。
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.0
	await get_tree().create_timer(duration, true, false, true)
	Engine.time_scale = 1.0
	_hitstop_active = false


# ---- 魔法攀升 ----

func _can_start_climb(input_dir: float) -> bool:
	## 空中、拥有能力、贴墙、且持续朝墙推，才能开始攀升。
	if not has_magic_climb:
		return false
	if is_on_floor():
		return false
	if not is_on_wall():
		return false
	var wn := get_wall_normal()
	if absf(wn.x) < 0.5:
		return false
	var wall_side := 1 if wn.x < 0.0 else -1  # 法线朝外：右墙法线 x<0
	return signf(input_dir) == float(wall_side)


func _start_climb() -> void:
	var wn := get_wall_normal()
	wall_dir = 1 if wn.x < 0.0 else -1
	state = State.CLIMB
	_restore_collision_shape()
	combo_stage = 0
	melee_hitbox.visible = false
	melee_hitbox.monitoring = false
	velocity.x = float(wall_dir) * 60.0
	velocity.y = -climb_speed


func _process_climb(_input_dir: float, _delta: float) -> void:
	## 攀升期间：禁用近战/远程；可以跳跃（默认远离墙）。
	## 这里用“直接控制 velocity”实现“暂时改变重力方向”的等价效果：不再施加向下重力，而是沿墙向上。
	if Input.is_action_just_pressed("jump"):
		_climb_jump()
		return
	velocity.x = float(wall_dir) * 60.0
	velocity.y = -climb_speed


func _climb_jump() -> void:
	## 攀升中跳跃：初始方向朝远离墙的一侧。
	state = State.JUMP
	_shrink_collision()
	velocity.y = jump_velocity
	velocity.x = -float(wall_dir) * climb_jump_away_speed
	jump_buffer_timer = 0.0
	coyote_timer = 0.0


func _start_crouch() -> void:
	state = State.CROUCH
	combo_stage = 0
	melee_hitbox.visible = false
	melee_hitbox.monitoring = false
	velocity.x = 0.0
	_shrink_collision()  # 下蹲碰撞盒与跳跃/冲刺一致（高度降低）


func _process_crouch(_input_dir: float, delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	if Input.is_action_just_pressed("jump") and Input.is_action_pressed("crouch"):
		_is_drop_through = true
		velocity.y = 80.0
	if not is_on_floor():
		velocity.y += gravity * delta


func _update_drop_through() -> void:
	## 单向平台：从下方跳上来时忽略；下落时碰撞；S+Space 持续忽略直到落地。
	if _is_drop_through or velocity.y < 0.0:
		collision_mask &= ~ONE_WAY_LAYER
	else:
		collision_mask |= ONE_WAY_LAYER


func _update_landing_state(delta: float) -> void:
	if _landing_timer > 0.0:
		_landing_timer -= delta
		if _landing_timer <= 0.0:
			_restore_collision_shape()
			state = State.IDLE
		return
	
	if not is_on_floor():
		if _was_on_floor:
			_air_start_y = global_position.y
		_was_on_floor = false


func _start_landing() -> void:
	_was_on_floor = true
	_landing_timer = 0.5
	state = State.CROUCH
	_current_action = ""
	_shrink_collision()


func _landing_interrupted() -> bool:
	return absf(Input.get_axis("move_left", "move_right")) > 0.1 \
		or Input.is_action_just_pressed("jump") \
		or Input.is_action_just_pressed("dash") \
		or Input.is_action_just_pressed("attack") \
		or Input.is_action_just_pressed("magic")


func _cancel_landing() -> void:
	_landing_timer = 0.0
	_restore_collision_shape()
	state = State.IDLE


# ---- 魔法飞行 ----

func _process_flight_charge(delta: float) -> void:
	if state == State.CLIMB:
		# 挂在墙上蓄力：不坠落，仍贴着墙
		velocity.x = wall_dir * 60.0
		velocity.y = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
	_flight_charge_time += delta
	if Input.is_action_just_released("flight"):
		if _flight_charge_time >= flight_charge_duration:
			_start_flight()
		else:
			_is_charging_flight = false
	elif not Input.is_action_pressed("flight"):
		_is_charging_flight = false


func _start_flight() -> void:
	_is_charging_flight = false
	var from_wall := state == State.CLIMB
	state = State.FLIGHT
	flight_direction = -wall_dir if from_wall else facing
	facing = flight_direction  # 飞行方向即面朝方向
	_update_facing(0.0)  # 立即更新 sprite 朝向，避免动画仍朝墙
	combo_stage = 0
	melee_hitbox.visible = false
	melee_hitbox.monitoring = false
	velocity = Vector2(flight_direction * speed * flight_speed_multiplier, 0.0)


func _process_flight(_delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_cancel_flight_to_jump()
		return
	velocity = Vector2(flight_direction * speed * flight_speed_multiplier, 0.0)


func _cancel_flight_to_jump() -> void:
	state = State.JUMP
	_shrink_collision()
	velocity.y = jump_velocity
	velocity.x = flight_direction * flight_cancel_jump_speed
	jump_buffer_timer = 0.0
	coyote_timer = 0.0


# ---- 冲刺无敌帧（无法选中） ----

func _set_dash_intangible(enabled: bool) -> void:
	_is_dash_intangible = enabled
	# 不再把 collision_layer 置 0：保持可被教程触发点 / 攻击判定盒检测到。
	# 冲刺无敌改由 take_damage() 里的 _is_dash_intangible 判断。


func _process_normal(input_dir: float, delta: float) -> void:
	var target: float = input_dir * speed
	var accel: float = acceleration if absf(input_dir) > 0.0 else friction
	velocity.x = move_toward(velocity.x, target, accel * delta)

	if not is_on_floor():
		velocity.y += gravity * delta

	if jump_buffer_timer > 0.0:
		if is_on_floor() or coyote_timer > 0.0:
			_do_jump()
		elif has_double_jump and air_jumps > 0:
			_do_jump()
			air_jumps -= 1


func _do_jump() -> void:
	velocity.y = jump_velocity
	_shrink_collision()   # 替换掉原来的手动创建代码
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	state = State.JUMP


func _start_dash(input_dir: float) -> void:
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_direction = facing if absf(input_dir) < 0.01 else (1 if input_dir > 0.0 else -1)
	# Day 5：魔法冲刺期间暂时无视魔法屏障（移除屏障层位）
	if has_magic_dash:
		collision_mask &= ~BARRIER_LAYER
	state = State.DASH
	_set_dash_intangible(true)  # 冲刺期间无法被敌人/子弹选中
		# 冲刺时碰撞盒压矮（高度减半）
	_shrink_collision()   


func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity = Vector2(dash_direction * dash_speed, 0.0)
	if dash_timer <= 0.0:
		collision_mask |= BARRIER_LAYER  # 冲刺结束恢复屏障碰撞
		_set_dash_intangible(false)
		_restore_collision_shape()       # 冲刺结束恢复碰撞盒，避免一直缩小
		state = State.IDLE
		


func _play_attack(stage: int) -> void:
	## 播放第 stage 段攻击（1/2/3）。每段完整播放，命中盒按段重开、可再次命中。
	combo_stage = stage
	state = State.ATTACK
	_restore_collision_shape()
	collision_mask |= BARRIER_LAYER  # 若从魔法冲刺中攻击，恢复屏障碰撞
	_configure_hitbox(stage)
	melee_hitbox.visible = true
	melee_hitbox.monitoring = true
	_melee_hit_set = {}
	_attack_press_queued = false  # 新攻击开始即清掉残留缓冲（如对话打断后）
	var anim_name := "attack%d" % stage
	attack_timer = anim_player.get_animation(anim_name).length  # 时长取自动画，二者永不脱节
	_current_action = anim_name
	anim_player.play(anim_name)


func _configure_hitbox(stage: int) -> void:
	var cs := $MeleeHitbox/CollisionShape2D
	var shape := cs.shape as RectangleShape2D
	var y_offset: float
	match stage:
		1:
			shape.size = Vector2(80, 100)
			y_offset = -30.5
		2:
			shape.size = Vector2(100, 100)
			y_offset = -30
		3:
			shape.size = Vector2(105, 120)
			y_offset = -40
	# 水平偏移 = 半宽 × 朝向（向外伸），垂直偏移保留原值
	cs.position = Vector2(shape.size.x / 2.0 * facing, y_offset)

func _end_combo() -> void:
	## 连击结束（打完三段无衔接 / 窗口内未按下一次）：归位到第 1 段待机。
	combo_stage = 0
	melee_hitbox.visible = false
	melee_hitbox.monitoring = false
	state = State.IDLE


func _cancel_attack_on_jump() -> void:
	## 攻击后摇可被跳跃取消（Day 10 手感）：按下跳跃立刻结束攻击、切到跳跃状态。
	## 地面 / 土狼窗口 → 直接起跳；空中且有二段跳 → 消耗一次空中跳跃取消；
	## 空中无二段跳 → 至少取消攻击、回到自由下落。
	_end_combo()                       # 归零连击、关闭命中盒（state → IDLE）
	_attack_press_queued = false
	if is_on_floor() or coyote_timer > 0.0:
		_do_jump()
	elif has_double_jump and air_jumps > 0:
		air_jumps -= 1
		_do_jump()
	else:
		state = State.JUMP


func _process_attack(input_dir: float, delta: float) -> void:
	attack_timer -= delta
	# Day 4：近战攻击期间可自由移动（同魔法，不打断位移）
	var target := input_dir * speed
	var accel := acceleration if absf(input_dir) > 0.0 else friction
	velocity.x = move_toward(velocity.x, target, accel * delta)
	if not is_on_floor():
		velocity.y += gravity * delta
	_melee_check_hits()
	if attack_timer <= 0.0:
		_on_attack_complete()


func _on_attack_complete() -> void:
	## 一段攻击动画播完：长按自动衔接下一段（第 3 段后循环回第 1 段）；
	## 若窗口内按过 → 升段；否则连击结束、归位到第 1 段。
	var holding := Input.is_action_pressed("attack")
	var advance := _attack_press_queued or holding
	_attack_press_queued = false
	if combo_stage < 3:
		if advance:
			_play_attack(combo_stage + 1)
		else:
			_end_combo()
	else:  # 第 3 段（重斩）
		if holding:
			_play_attack(1)   # 长按：打满三段后循环回第 1 段
		else:
			_end_combo()      # 点击/松手：连击结束归位


func _melee_check_hits() -> void:
	var dmg := melee_damage * (2 if combo_stage == 3 else 1)  # 第 3 段重斩双倍伤害
	for body in melee_hitbox.get_overlapping_bodies():
		if body.is_in_group("enemies") and not _melee_hit_set.has(body.get_instance_id()):
			_melee_hit_set[body.get_instance_id()] = true
			body.take_damage(dmg, global_position)
			_apply_hitstop(hitstop_duration)
			_start_camera_shake(0.08, 1.5 if combo_stage != 3 else 2.5)


func _cast_magic() -> void:
	if not GameState.spend_music_inspiration(GameState.MAGIC_INSPIRATION_COST):
		return  # 音乐灵感不足：暂不发射
	magic_cooldown_timer = magic_cooldown
	var projectile := MAGIC_PROJECTILE.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = muzzle.global_position
	projectile.damage = magic_damage
	projectile.setup(get_local_mouse_position(), magic_speed)


func take_damage(amount: int, from_pos: Vector2) -> void:
	if invincible_timer > 0.0 or hp <= 0 or _is_dash_intangible:
		return
	_cancel_heal()
	hp = maxi(hp - amount, 0)
	GameState.hp = hp
	health_changed.emit(hp, max_hp)
	_hurt_flash_timer = 0.15
	invincible_timer = invincible_time
	_is_charging_flight = false
	if state == State.FLIGHT:
		state = State.IDLE
		velocity = Vector2.ZERO
	_start_camera_shake(0.12, 2.5)

	var kb_dir := 1.0 if global_position.x >= from_pos.x else -1.0
	velocity.x = kb_dir * 300.0
	velocity.y = -200.0

	if hp <= 0:
		_die()


func _check_danger() -> void:
	if _death_sequence_running or _danger_cooldown > 0.0:
		return
	var current := get_tree().current_scene
	if current == null:
		return
	var danger := current.get_node_or_null("layers/danger") as TileMapLayer
	if danger == null:
		return
	# 多采样点：脚底 / 躯干 / 中心，避免站在地刺上但中心在刺上方而检测不到
	var samples := [
		global_position + Vector2(0, 30),
		global_position + Vector2(0, 10),
		global_position,
	]
	for p in samples:
		var cell := danger.local_to_map(p)
		if danger.get_cell_source_id(cell) != -1:
			_danger_cooldown = 0.5
			_danger_hit()
			return


func _danger_hit() -> void:
	if _death_sequence_running:
		return
	_death_sequence_running = true
	hp = maxi(hp - 2, 0)
	GameState.hp = hp
	health_changed.emit(hp, max_hp)
	_hurt_flash_timer = 0.15
	GameState.reset_music_inspiration()
	set_physics_process(false)
	set_process(false)
	_play_fail_animation()
	# 受伤白闪（danger 地形伤害也闪一下），闪完再继续死亡动画
	action_sprite.self_modulate = Color(4, 4, 4)
	sprite.self_modulate = Color(4, 4, 4, 1)
	await get_tree().create_timer(0.15).timeout
	action_sprite.self_modulate = Color(1, 1, 1)
	sprite.self_modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(0.85).timeout
	# 复活：临时存档点优先；无临时存档点则回核心存档点（满状态）
	if GameState.has_temp_checkpoint():
		GameState.respawn_at_temp_checkpoint()
	else:
		GameState.hp = max_hp
		GameState.respawn_at_checkpoint()
	# 3s 渐黑 → 切换场景 → 3s 渐亮（camera 恢复）
	Transition.fade_to_slow(GameState.spawn_scene, 3.0, 3.0)


func _play_fail_animation() -> void:
	_current_action = "fail"
	anim_player.play("fail")
	action_sprite.visible = true
	sprite.visible = false


func _die() -> void:
	_death_sequence_running = true
	set_physics_process(false)
	set_process(false)
	_play_fail_animation()
	# 受伤白闪（死亡也算受伤）
	action_sprite.self_modulate = Color(4, 4, 4)
	sprite.self_modulate = Color(4, 4, 4, 1)
	await get_tree().create_timer(0.15).timeout
	action_sprite.self_modulate = Color(1, 1, 1)
	sprite.self_modulate = Color(1, 1, 1, 1)
	await get_tree().create_timer(0.85).timeout
	# 检查点复活：满血 + 回到最近检查点（跨场景，能力/线索保留）
	GameState.hp = max_hp
	GameState.reset_music_inspiration()
	GameState.respawn_at_checkpoint()
	# 死亡动画结束 → 3s 渐黑 → 切场景 → 3s 渐亮恢复
	Transition.fade_to_slow(GameState.spawn_scene, 3.0, 3.0)


func _update_facing(input_dir: float) -> void:
	if state == State.DASH:
		return
	if state == State.FLIGHT:
		facing = flight_direction
		sprite.flip_h = facing < 0
		return
	if absf(input_dir) > 0.0:
		facing = 1 if input_dir > 0.0 else -1
	sprite.flip_h = facing < 0
	melee_hitbox.position.x = facing * 24.0
	muzzle.position.x = facing * 24.0


func _update_state() -> void:
	if state == State.DASH or state == State.ATTACK or state == State.CLIMB or state == State.CROUCH or state == State.FLIGHT:
		return
	if not is_on_floor():
		state = State.JUMP
	elif absf(velocity.x) > 1.0:
		state = State.RUN
	else:
		state = State.IDLE


func _update_visual() -> void:
	if _is_charging_flight:
		sprite.visible = false
		action_sprite.visible = false
		sit_sprite.visible = false
		climb_sprite.visible = false
		animated_sprite.visible = false
		charge_sprite.visible = true
		# 蓄力方向：攀墙时用“远离墙”的方向（=起飞方向），其余用 facing
		var charge_dir := -wall_dir if state == State.CLIMB else facing
		charge_sprite.flip_h = charge_dir < 0
		if _current_action != "flight_charge":
			_current_action = "flight_charge"
			anim_player.play("flight_charge")
		return

	if state == State.HEAL:
		charge_sprite.visible = false
		sit_sprite.visible = false
		climb_sprite.visible = false
		sprite.visible = false
		action_sprite.visible = false
		animated_sprite.visible = true
		animated_sprite.flip_h = facing < 0
		if _current_action != "heal":
			_current_action = "heal"
			anim_player.play("heal")
		return

	if state == State.CLIMB:
		charge_sprite.visible = false
		sit_sprite.visible = false
		animated_sprite.visible = false
		sprite.visible = false
		action_sprite.visible = false
		climb_sprite.visible = true
		climb_sprite.flip_h = facing < 0
		if not climb_sprite.is_playing():
			climb_sprite.play("default")
		_current_action = "climb"
		anim_player.stop()
		return

	if state == State.SIT:
		charge_sprite.visible = false
		animated_sprite.visible = false
		climb_sprite.visible = false
		sprite.visible = false
		action_sprite.visible = false
		sit_sprite.visible = true
		sit_sprite.flip_h = facing < 0
		_current_action = "sit"
		anim_player.stop()
		return

	sit_sprite.visible = false
	climb_sprite.visible = false
	animated_sprite.visible = false
	charge_sprite.visible = false
	var base := Color(1, 1, 1)
	match state:
		State.ATTACK:
			base = Color(1, 0.85, 0.85)
		State.DASH:
			base = Color(0.85, 0.7, 1) if has_magic_dash else Color(0.85, 1, 1)
		State.CLIMB:
			base = Color(0.75, 0.85, 1)
		State.CROUCH:
			base = Color(0.85, 0.9, 0.8)
		State.FLIGHT:
			base = Color(0.7, 0.85, 1)
		State.HEAL:
			base = Color(0.95, 0.95, 1)
	if invincible_timer > 0.0 and int(invincible_timer * 20.0) % 2 == 0:
		base.a = 0.4
	if stagger_timer > 0.0:
		base = Color(1, 0.9, 0.4)
	sprite.self_modulate = base
	# Day 7：跑步/冲刺/跳跃动画由 AnimationPlayer 关键帧驱动。
	#   动作精灵图角色朝向与待机立绘相反，故翻转取反；动作播放时隐藏待机立绘避免重叠。
	action_sprite.self_modulate = Color(1, 1, 1)  # 动作精灵不染色，避免下蹲/冲刺等颜色变化
	# 受伤白闪：敌人伤害 / danger 地形伤害都触发
	if _hurt_flash_timer > 0.0:
		sprite.self_modulate = Color(4, 4, 4, base.a)
		action_sprite.self_modulate = Color(4, 4, 4)
	# 攻击美术原始朝向固定（见 ATTACK_ART_FACES_LEFT）；其余动作图与待机立绘朝向相反。
	if state == State.ATTACK:
		action_sprite.flip_h = (not sprite.flip_h) if ATTACK_ART_FACES_LEFT else sprite.flip_h
	elif state == State.FLIGHT:
		# 飞行动画始终朝向真实飞行方向（尤其攀墙起飞时，忽略按住往墙的输入）
		action_sprite.flip_h = flight_direction > 0
	else:
		action_sprite.flip_h = not sprite.flip_h
	var action := ""
	match state:
		State.RUN:
			action = "run"
		State.DASH:
			action = "dash"
		State.JUMP:
			action = "jump" if velocity.y < 0.0 else "fall"
		State.CROUCH:
			action = "crouch" if _landing_timer <= 0.0 else "land"
		State.FLIGHT:
			action = "dash"  # 复用跳跃/冲刺单帧动画，正式飞行动画后续替换
		State.ATTACK:
			action = "attack%d" % combo_stage if combo_stage > 0 else ""
		State.HEAL:
			action = "heal" if anim_player.has_animation("heal") else ""
	sprite.visible = action.is_empty()
	action_sprite.visible = not action.is_empty()
	if action != _current_action:
		_current_action = action
		if action.is_empty():
			anim_player.stop()
		else:
			anim_player.play(action)
