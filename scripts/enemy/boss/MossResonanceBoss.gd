extends CharacterBody2D
## 苔藓洞穴 Boss「苔藓共鸣兽」：基础骨架 + B 阶段三招。
## 招式时间轴先用 Timer/await 驱动，后续替换正式动画时不改变伤害接口。

const SHOCKWAVE_SCENE: PackedScene = preload("res://scenes/enemies/boss/BossShockwave.tscn")
const FINISHER_CONFIG: BossFinisherConfig = preload("res://data/boss/MossBossFinisher.tres")
const MOSS_STAGE_ONE: AudioStream = preload("res://audio/music/moss_1.ogg")
const MOSS_STAGE_TWO: AudioStream = preload("res://audio/music/moss_2.ogg")
const MOSS_FINISHER: AudioStream = preload("res://audio/music/moss_end(mars).ogg")
const SFX_LAND: AudioStream = preload("res://audio/enemy/moss/land.mp3")
const SFX_SLAM: AudioStream = preload("res://audio/enemy/moss/slam.mp3")
const SFX_PHASE_CHANGE: AudioStream = preload("res://audio/enemy/moss/phase_change.wav")

const BOSS_ID := "moss_resonance_boss"

enum State { INTRO, IDLE, ATTACK, PHASE_CHANGE, FINISHER, VULNERABLE, VICTORY, DEAD }

signal health_changed(current: int, maximum: int)
signal phase_changed(phase: int)
signal boss_battle_started
signal finisher_started
signal victory

@export var max_hp: int = 100
@export var gravity: float = 1200.0
@export var contact_damage: int = 1
@export var 胜利大音符数量: int = 4
@export var shockwave_damage: int = 1
@export var note_miss_damage: int = 1
@export var slam_damage: int = 1
@export var enrage_threshold: float = 0.5
@export var arena_left: float = 3270.0
@export var arena_right: float = 4550.0
@export var phase_one_attack_interval: float = 2.0
@export var phase_two_attack_interval: float = 0.5
@export var note_damage_to_boss: int = 5
@export var note_duration: float = 1.0
@export var note_perfect_window: float = 0.25
@export var note_spawn_offset: float = 150.0
@export var jump_velocity: float = -620.0
@export var jump_height_multiplier: float = 1.5
@export var jump_horizontal_speed: float = 1000.0
@export var phase_two_jump_count: int = 2
@export var phase_two_jump_pause: float = 0.15
@export var phase_two_note_count: int = 2
@export var phase_two_note_gap: float = 0.08
@export_range(0.1, 0.5, 0.05) var finisher_note_horizontal_range: float = 0.42
@export_range(0.1, 0.5, 0.05) var finisher_note_vertical_top_range: float = 0.38
@export_range(0.1, 0.5, 0.05) var finisher_note_vertical_bottom_range: float = 0.32
@export_range(0.0, 1.0, 0.05) var finisher_note_center_bias: float = 0.5
@export var finisher_shake_strength: float = 3.0
@export var finisher_shake_interval: float = 0.18
@export var shockwave_speed: float = 360.0
@export var shockwave_lifetime: float = 2.0
@export var slam_windup: float = 0.45
@export var slam_recovery: float = 0.45

@export_category("攻击特效")
@export var 攻击特效地面偏移: float = 0.0
@export var 攻击特效出现时长: float = 0.3
@export var 攻击特效初始缩放: float = 0.05
@export var 大跳特效缩放: float = 0.55
@export var 砸地特效缩放: float = 0.55
@export var 砸地落点特效缩放: float = 0.45

@export_category("Boss屏幕震动")
@export var 砸地震动强度: float = 10.0
@export var 砸地震动时长: float = 0.12
@export var 大跳震动强度: float = 8.0
@export var 大跳震动时长: float = 0.12

@export_category("Boss音效")
@export var 砸地音效音量分贝: float = -6.0
@export var 大跳落地音效提前时间: float = 0.4

@export_category("处决强拍震动")
@export var 处决强拍判定偏移: float = 0.9
@export var 处决强拍震动强度: float = 20.0
@export var 处决强拍震动时长: float = 0.16

@export_category("二阶段光环")
@export var 光环上下浮动幅度: float = 5.0
@export var 光环浮动周期: float = 2.4
@export_range(0.0, 1.0, 0.05) var 光环最小透明度: float = 0.65
@export_range(0.0, 1.0, 0.05) var 光环最大透明度: float = 1.0

@onready var visual: Polygon2D = $Visual
@onready var boss_sprite: AnimatedSprite2D = $BossSprite
@onready var finisher_pull_sprite: AnimatedSprite2D = $FinisherPullSprite
@onready var dead_sprite: Sprite2D = $DeadSprite
@onready var phase_aura_sprite: Sprite2D = $PhaseAuraSprite
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var qte_controller: Node = $QTEController
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer
var state: State = State.INTRO
var player: CharacterBody2D = null
var facing: int = -1
var hp: int = 0
var phase: int = 1
var battle_started: bool = false
var _phase_change_started: bool = false
var _finisher_pending: bool = false
var _configured_contact_damage: int = 1
var _attack_index: int = 0
var _attacks_since_resonance: int = 0
var _attack_serial: int = 0
var _attack_loop_started: bool = false
var _jump_in_progress: bool = false
var _jump_target_x: float = 0.0
var _jump_sfx_serial: int = 0
var _jump_sfx_played_serial: int = -1
var _finisher_resolving: bool = false
var _finisher_miss_count: int = 0
var _phase_aura_base_position: Vector2
var _phase_aura_time: float = 0.0
var _victory_drop_spawned: bool = false


func _ready() -> void:
	# Boss 的逻辑和子节点都随暂停菜单暂停；战斗计时器也使用 pauseable 模式。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("boss")
	add_to_group("enemies")
	if GameState.is_boss_defeated(BOSS_ID):
		_show_defeated_background()
		return
	hp = max_hp
	_configured_contact_damage = contact_damage
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	_phase_aura_base_position = phase_aura_sprite.position
	attack_hitbox.monitoring = false
	_set_contact_damage_enabled(false)
	_set_fx_visibility(false)
	health_changed.emit(hp, max_hp)
	_update_facing()


func _exit_tree() -> void:
	# 玩家死亡换场景时，终止仍在等待帧信号的攻击协程。
	battle_started = false
	_attack_serial += 1
	_jump_in_progress = false


func start_battle() -> void:
	if battle_started or state == State.DEAD:
		return
	battle_started = true
	state = State.INTRO
	_set_fx_visibility(false)
	boss_battle_started.emit()
	_attack_serial += 1
	_attacks_since_resonance = 0
	_set_contact_damage_enabled(false)
	velocity = Vector2.ZERO
	AudioManager.push_music("moss_boss", MOSS_STAGE_ONE, true, 0.0, -6.0)
	_intro_then_start()


func _intro_then_start() -> void:
	await get_tree().create_timer(0.5, false).timeout
	if not is_instance_valid(self) or not battle_started or state != State.INTRO:
		return
	state = State.IDLE
	_set_contact_damage_enabled(true)
	if not _attack_loop_started:
		_attack_loop_started = true
		_attack_loop()


func _physics_process(delta: float) -> void:
	_animate_phase_aura(delta)
	if not battle_started or state in [State.DEAD, State.FINISHER, State.VICTORY]:
		return
	_update_animation()
	if state in [State.INTRO, State.PHASE_CHANGE]:
		velocity = Vector2.ZERO
		return

	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		velocity.x = 0.0
		return

	if state == State.ATTACK:
		if _jump_in_progress:
			var remaining_x := _jump_target_x - global_position.x
			if absf(remaining_x) <= 8.0:
				velocity.x = 0.0
			else:
				var horizontal_direction := signf(remaining_x)
				velocity.x = move_toward(velocity.x, horizontal_direction * jump_horizontal_speed, jump_horizontal_speed * 4.0 * delta)
		else:
			velocity.x = 0.0
		if _jump_in_progress:
			velocity.y += gravity * delta
		else:
			if not is_on_floor():
				velocity.y += gravity * delta
		global_position.x = clampf(global_position.x, arena_left, arena_right)
		move_and_slide()
		if _jump_in_progress and is_on_floor() and velocity.y >= 0.0:
			_jump_in_progress = false
			velocity.x = 0.0
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return

	_face_player()
	state = State.IDLE
	velocity.x = 0.0
	if not is_on_floor():
		velocity.y += gravity * delta
	global_position.x = clampf(global_position.x, arena_left, arena_right)
	move_and_slide()


func take_damage(amount: int, from_pos: Vector2, from_magic := false) -> void:
	if state == State.VULNERABLE and amount > 0:
		_finish_vulnerable()
		return
	if state in [State.DEAD, State.FINISHER, State.VICTORY, State.INTRO, State.PHASE_CHANGE, State.VULNERABLE]:
		return
	if not from_magic:
		GameState.add_music_inspiration(GameState.MUSIC_INSPIRATION_PER_HIT)
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp, max_hp)
	if hp <= 0:
		_begin_finisher()
		return
	if not _phase_change_started and hp <= int(round(max_hp * enrage_threshold)):
		_phase_change_started = true
		phase = 2
		phase_changed.emit(phase)
		_attack_serial += 1
		_attacks_since_resonance = 0
		state = State.PHASE_CHANGE
		_set_contact_damage_enabled(false)
		AudioManager.switch_music("moss_boss", MOSS_STAGE_TWO, true, 0.0, -6.0)
		_phase_change_sequence()
		return
	_flash()


func _begin_finisher() -> void:
	if _finisher_pending or state == State.FINISHER:
		return
	_finisher_pending = true
	_finisher_miss_count = 0
	state = State.FINISHER
	_set_fx_visibility(false)
	# 处决倒地动画使用资源默认朝向，不继承战斗中的 facing。
	boss_sprite.flip_h = false
	boss_sprite.stop()
	boss_sprite.frame = 0
	boss_sprite.play("finisher_fall")
	_attack_serial += 1
	velocity = Vector2.ZERO
	attack_hitbox.monitoring = false
	_set_contact_damage_enabled(false)
	AudioManager.pause_current_music()
	if qte_controller.has_method("cancel_active_note"):
		qte_controller.cancel_active_note()
	finisher_started.emit()
	_run_finisher()


func set_vulnerable(enabled: bool) -> void:
	if state in [State.DEAD, State.VICTORY]:
		return
	state = State.VULNERABLE if enabled else State.IDLE
	_set_contact_damage_enabled(false)


func complete_victory() -> void:
	if state in [State.VICTORY, State.DEAD]:
		return
	state = State.VICTORY
	_set_fx_visibility(false)
	hp = 0
	if not _victory_drop_spawned:
		_victory_drop_spawned = true
		EnemyDrop.spawn_elite(self, 胜利大音符数量)
	attack_hitbox.monitoring = false
	_set_contact_damage_enabled(false)
	AudioManager.return_to_music("background")
	_show_defeated_background()
	if is_instance_valid(player):
		player.visible = true
	victory.emit()


func _show_defeated_background() -> void:
	battle_started = false
	state = State.VICTORY
	boss_sprite.stop()
	boss_sprite.visible = false
	finisher_pull_sprite.stop()
	finisher_pull_sprite.visible = false
	dead_sprite.visible = true
	_set_fx_visibility(false)
	attack_hitbox.monitoring = false
	_set_contact_damage_enabled(false)
	$CollisionShape2D.set_deferred("disabled", true)
	remove_from_group("enemies")


func _set_contact_damage_enabled(enabled: bool) -> void:
	contact_damage = _configured_contact_damage if enabled else 0


func _flash() -> void:
	boss_sprite.self_modulate = Color(4, 4, 4)
	await get_tree().create_timer(0.04, false).timeout
	if is_instance_valid(boss_sprite):
		boss_sprite.self_modulate = Color(1, 1, 1)


func _update_facing() -> void:
	visual.scale.x = facing
	boss_sprite.flip_h = facing < 0
	attack_hitbox.position.x = facing * 44.0


func _update_animation() -> void:
	if state in [State.ATTACK, State.PHASE_CHANGE, State.FINISHER, State.VICTORY]:
		return
	if boss_sprite.animation != "idle":
		boss_sprite.play("idle")


func _attack_loop() -> void:
	while battle_started and state not in [State.DEAD, State.FINISHER, State.VICTORY]:
		var interval := phase_two_attack_interval if phase == 2 else phase_one_attack_interval
		await get_tree().create_timer(maxf(interval, 0.0), false).timeout
		if not battle_started or state in [State.DEAD, State.FINISHER, State.VICTORY]:
			return
		if state != State.IDLE:
			continue
		var token := _attack_serial
		var attack_kind := _choose_attack()
		_register_attack(attack_kind)
		if attack_kind == "note":
			await _perform_resonance_note(token)
		elif attack_kind == "jump":
			await _perform_jump_attack(token)
		else:
			await _perform_slam_attack(token)
		_attack_index += 1
	_attack_loop_started = false


func _choose_attack() -> String:
	if _attacks_since_resonance >= 4:
		return "note"
	if player == null:
		return "note"
	# 音符固定占 1/4；其余 3/4 按距离在砸地和大跳之间分配。
	var roll := randf()
	if roll < 0.25:
		return "note"
	var distance := absf(player.global_position.x - global_position.x)
	if distance <= 500.0:
		return "slam" if roll < 0.75 else "jump"
	return "jump" if roll < 0.75 else "slam"


func _register_attack(attack_kind: String) -> void:
	if attack_kind == "note":
		_attacks_since_resonance = 0
	else:
		_attacks_since_resonance += 1


func _perform_resonance_note(token: int) -> void:
	state = State.ATTACK
	boss_sprite.play("note_cast")
	velocity.x = 0.0
	_face_player()
	if not await _wait_attack_time(0.3, token):
		_end_attack_if_active()
		return
	if player == null:
		_end_attack_if_active()
		return
	var note_count := maxi(phase_two_note_count, 1) if phase == 2 else 1
	var reflected_damage := 0
	for note_index in note_count:
		var note_position := player.global_position + Vector2(facing * note_spawn_offset, -48.0)
		if not qte_controller.spawn_note(note_position, note_duration, note_perfect_window):
			_end_attack_if_active()
			return
		var perfect: bool = await qte_controller.wait_for_note()
		if not _attack_token_valid(token):
			_end_attack_if_active()
			return
		if perfect:
			reflected_damage += note_damage_to_boss
		else:
			player.take_damage(note_miss_damage, global_position)
		if note_index < note_count - 1 and not await _wait_attack_time(phase_two_note_gap, token):
			return
	if reflected_damage > 0:
		take_damage(reflected_damage, player.global_position)
	if _attack_token_valid(token):
		state = State.IDLE


func _end_attack_if_active() -> void:
	if state == State.ATTACK:
		state = State.IDLE


func _perform_jump_attack(token: int) -> void:
	state = State.ATTACK
	var jump_count := maxi(phase_two_jump_count, 1) if phase == 2 else 1
	for jump_index in jump_count:
		boss_sprite.stop()
		boss_sprite.frame = 0
		boss_sprite.play("jump")
		_jump_sfx_serial += 1
		var jump_sfx_serial := _jump_sfx_serial
		_schedule_jump_land_sfx(token, jump_sfx_serial)
		if not await _perform_single_targeted_jump(token):
			return
		if _jump_sfx_played_serial != jump_sfx_serial:
			_jump_sfx_played_serial = jump_sfx_serial
			_play_sfx(SFX_LAND)
		FeedbackManager.camera_shake(大跳震动强度, 大跳震动时长)
		_spawn_shockwave(-1, shockwave_damage, "jump", -1.0, 大跳特效缩放)
		_spawn_shockwave(1, shockwave_damage, "jump", -1.0, 大跳特效缩放)
		if jump_index < jump_count - 1 and not await _wait_attack_time(phase_two_jump_pause, token):
			return
	if _attack_token_valid(token):
		state = State.IDLE


func _perform_single_targeted_jump(token: int) -> bool:
	if not is_inside_tree() or get_tree() == null:
		_jump_in_progress = false
		return false
	velocity.x = 0.0
	if player != null:
		_jump_target_x = clampf(player.global_position.x, arena_left, arena_right)
	_jump_in_progress = is_on_floor()
	if _jump_in_progress:
		# v^2/(2g) 与高度成正比，因此乘 sqrt(1.5) 才是实际高度 1.5 倍。
		velocity.y = jump_velocity * sqrt(maxf(jump_height_multiplier, 0.1))
	while _jump_in_progress:
		if not await _wait_for_next_frame():
			_jump_in_progress = false
			return false
		if not is_inside_tree() or not _attack_token_valid(token):
			_jump_in_progress = false
			return false
	if not is_inside_tree() or not _attack_token_valid(token):
		_jump_in_progress = false
		return false
	return _attack_token_valid(token)


func _wait_for_next_frame() -> bool:
	if not is_inside_tree():
		return false
	var scene_tree := get_tree()
	if scene_tree == null or not is_instance_valid(scene_tree):
		return false
	await scene_tree.process_frame
	return is_inside_tree()


func _schedule_jump_land_sfx(token: int, jump_sfx_serial: int) -> void:
	if not is_inside_tree():
		return
	var effective_jump_speed := absf(jump_velocity * sqrt(maxf(jump_height_multiplier, 0.1)))
	var estimated_air_time := effective_jump_speed * 2.0 / maxf(gravity, 0.001)
	var delay := maxf(estimated_air_time - maxf(大跳落地音效提前时间, 0.0), 0.0)
	var scene_tree := get_tree()
	if scene_tree == null or not is_instance_valid(scene_tree):
		return
	await scene_tree.create_timer(delay, false).timeout
	if not is_inside_tree() or not _attack_token_valid(token):
		return
	if jump_sfx_serial != _jump_sfx_serial or not _jump_in_progress:
		return
	_jump_sfx_played_serial = jump_sfx_serial
	_play_sfx(SFX_LAND)


func _perform_slam_attack(token: int) -> void:
	state = State.ATTACK
	var slam_animation := "slam_right" if facing > 0 else "slam_left"
	boss_sprite.play(slam_animation)
	if slam_animation == "slam_left":
		boss_sprite.flip_h = not boss_sprite.flip_h
	velocity.x = 0.0
	if not await _wait_attack_time(slam_windup, token):
		_update_facing()
		return
	_play_sfx(SFX_SLAM, 1.0, 砸地音效音量分贝)
	FeedbackManager.camera_shake(砸地震动强度, 砸地震动时长)
	_spawn_shockwave(facing, slam_damage, "slam", -1.0, 砸地特效缩放)
	_spawn_shockwave(facing, 0, "impact", 0.25, 砸地落点特效缩放)
	if not await _wait_attack_time(slam_recovery, token):
		_update_facing()
		return
	_update_facing()
	if _attack_token_valid(token):
		state = State.IDLE


func _spawn_shockwave(direction: int, damage: int, effect_kind: String = "slam", lifetime_override: float = -1.0, visual_scale: float = 0.55) -> void:
	var wave := SHOCKWAVE_SCENE.instantiate()
	get_tree().current_scene.add_child(wave)
	wave.global_position = global_position + Vector2(direction * 64.0, 攻击特效地面偏移)
	var lifetime := shockwave_lifetime if lifetime_override < 0.0 else lifetime_override
	wave.setup(direction, shockwave_speed, damage, lifetime, effect_kind, visual_scale, 攻击特效出现时长, 攻击特效初始缩放)


func _wait_attack_time(seconds: float, token: int) -> bool:
	await get_tree().create_timer(maxf(seconds, 0.0), false).timeout
	return _attack_token_valid(token)


func _attack_token_valid(token: int) -> bool:
	return token == _attack_serial and battle_started and state not in [State.DEAD, State.FINISHER, State.VICTORY, State.PHASE_CHANGE]


func _face_player() -> void:
	if player == null:
		return
	facing = 1 if player.global_position.x >= global_position.x else -1
	_update_facing()


func _phase_change_sequence() -> void:
	_play_sfx(SFX_PHASE_CHANGE)
	boss_sprite.play("phase_change", 0.5)
	phase_aura_sprite.visible = true
	await boss_sprite.animation_finished
	if not battle_started or state != State.PHASE_CHANGE:
		boss_sprite.speed_scale = 1.0
		return
	boss_sprite.speed_scale = 1.0
	visual.color = Color(0.35, 0.75, 0.8, 1.0)
	phase_aura_sprite.visible = true
	state = State.IDLE
	_set_contact_damage_enabled(true)


func _animate_phase_aura(delta: float) -> void:
	if not phase_aura_sprite.visible or phase != 2:
		return
	_phase_aura_time += delta
	var period := maxf(光环浮动周期, 0.05)
	var wave := (sin(_phase_aura_time * TAU / period) + 1.0) * 0.5
	phase_aura_sprite.position = _phase_aura_base_position + Vector2(0.0, lerpf(-光环上下浮动幅度, 光环上下浮动幅度, wave))
	phase_aura_sprite.modulate = Color(1.0, 1.0, 1.0, lerpf(光环最小透明度, 光环最大透明度, wave))


func _run_finisher() -> void:
	await boss_sprite.animation_finished
	if state != State.FINISHER or not is_instance_valid(player):
		return
	boss_sprite.visible = false
	if is_instance_valid(player):
		player.visible = false
	finisher_pull_sprite.visible = true
	finisher_pull_sprite.play("pull_loop")
	AudioManager.push_music("moss_finisher", MOSS_FINISHER, false, 0.0, -6.0)
	_run_finisher_shake()

	var sequence_start_msec := Time.get_ticks_msec()
	_run_finisher_beat_shakes(sequence_start_msec)
	var note_callback := Callable(self, "_on_finisher_note_resolved")
	qte_controller.note_resolved.connect(note_callback)
	for index in FINISHER_CONFIG.get_note_count():
		var target_spawn_time: float = float(FINISHER_CONFIG.get_note_spawn_time(index))
		var elapsed_seconds := float(Time.get_ticks_msec() - sequence_start_msec) / 1000.0
		var delay: float = target_spawn_time - elapsed_seconds
		await _wait_seconds(maxf(delay, 0.0))
		if state != State.FINISHER or not is_instance_valid(player):
			return
		qte_controller.spawn_finisher_note(_get_finisher_note_position(), FINISHER_CONFIG.note_duration, FINISHER_CONFIG.perfect_window)
	await _wait_seconds(maxf(FINISHER_CONFIG.finisher_end_time - (float(Time.get_ticks_msec() - sequence_start_msec) / 1000.0), 0.0))
	if state != State.FINISHER:
		return
	qte_controller.note_resolved.disconnect(note_callback)
	qte_controller.cancel_active_note()
	await _finish_success()


func _finish_success() -> void:
	await _wait_seconds(FINISHER_CONFIG.success_intro_duration)
	if state != State.FINISHER:
		return
	finisher_pull_sprite.play("pull_once")
	await finisher_pull_sprite.animation_finished
	_hold_finisher_pull_last_frame()
	await AudioManager.wait_until_music_finished("moss_finisher")
	if is_instance_valid(player) and player.has_method("grant_magic_flight"):
		player.grant_magic_flight()
	GameState.mark_boss_defeated(BOSS_ID)
	GameState.save_game()
	complete_victory()


func _hold_finisher_pull_last_frame() -> void:
	var frames := finisher_pull_sprite.sprite_frames
	if frames == null or not frames.has_animation("pull_once"):
		return
	var last_frame := frames.get_frame_count("pull_once") - 1
	finisher_pull_sprite.stop()
	finisher_pull_sprite.animation = &"pull_once"
	finisher_pull_sprite.frame = maxi(last_frame, 0)
	finisher_pull_sprite.frame_progress = 1.0


func _run_finisher_shake() -> void:
	while state == State.FINISHER and finisher_pull_sprite.visible:
		FeedbackManager.camera_shake(finisher_shake_strength)
		await _wait_seconds(maxf(finisher_shake_interval, 0.05))


func _run_finisher_beat_shakes(sequence_start_msec: int) -> void:
	for index in FINISHER_CONFIG.get_note_count():
		var beat_time := FINISHER_CONFIG.get_note_spawn_time(index) + 处决强拍判定偏移
		var elapsed_seconds := float(Time.get_ticks_msec() - sequence_start_msec) / 1000.0
		await _wait_seconds(maxf(beat_time - elapsed_seconds, 0.0))
		if state != State.FINISHER:
			return
		FeedbackManager.camera_shake(处决强拍震动强度, 处决强拍震动时长)


func _on_finisher_note_resolved(perfect: bool) -> void:
	if perfect:
		return
	_finisher_miss_count += 1
	if _finisher_miss_count % 5 == 0 and is_instance_valid(player):
		player.take_damage(1, global_position)


func _get_finisher_note_position() -> Vector2:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return global_position
	var viewport_size := get_viewport_rect().size / camera.zoom
	var center := camera.global_position
	var horizontal := randf_range(-viewport_size.x * finisher_note_horizontal_range, viewport_size.x * finisher_note_horizontal_range)
	var vertical := randf_range(-viewport_size.y * finisher_note_vertical_top_range, viewport_size.y * finisher_note_vertical_bottom_range)
	if randf() < finisher_note_center_bias:
		horizontal *= 0.45
		vertical *= 0.45
	return center + Vector2(horizontal, vertical)


func _get_camera_center() -> Vector2:
	var camera := get_viewport().get_camera_2d()
	return camera.global_position if camera else global_position


func _finish_failure() -> void:
	if is_instance_valid(player):
		player.take_damage(FINISHER_CONFIG.retaliation_damage, global_position)
	await _wait_seconds(FINISHER_CONFIG.retaliation_pause)
	if not is_instance_valid(self) or state != State.FINISHER:
		return
	hp = 1
	health_changed.emit(hp, max_hp)
	state = State.VULNERABLE
	_finisher_pending = false
	_set_contact_damage_enabled(false)
	await _wait_seconds(FINISHER_CONFIG.vulnerable_duration)
	if state != State.VULNERABLE:
		return
	var recovery_hp := maxi(1, int(round(max_hp * FINISHER_CONFIG.recovery_hp_ratio)))
	hp = recovery_hp
	health_changed.emit(hp, max_hp)
	state = State.IDLE
	_set_contact_damage_enabled(true)
	AudioManager.pop_music("moss_finisher")
	AudioManager.switch_music("moss_boss", MOSS_STAGE_TWO, true, 0.0, -6.0)
	_attack_serial += 1
	if not _attack_loop_started:
		_attack_loop_started = true
		_attack_loop()


func _finish_vulnerable() -> void:
	if _finisher_resolving:
		return
	_finisher_resolving = true
	state = State.FINISHER
	_set_contact_damage_enabled(false)
	AudioManager.switch_music("moss_boss", MOSS_FINISHER, false, 0.0, -6.0)
	await _finish_success()


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.0), false).timeout


func _play_sfx(stream: AudioStream, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if stream == null or not is_instance_valid(sfx_player):
		return
	sfx_player.stream = stream
	sfx_player.pitch_scale = pitch
	sfx_player.volume_db = volume_db
	sfx_player.play()


func _set_fx_visibility(aura_visible: bool) -> void:
	phase_aura_sprite.visible = aura_visible
	if not aura_visible:
		_phase_aura_time = 0.0
		phase_aura_sprite.position = _phase_aura_base_position
		phase_aura_sprite.modulate = Color.WHITE
