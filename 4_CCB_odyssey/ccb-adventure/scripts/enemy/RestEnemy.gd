extends CharacterBody2D
## 休止符：固定位置不移动。玩家进入攻击范围后，周期性释放慢速波纹弹。
## 波纹无伤害，命中玩家会使其僵直 1.5 秒（由 RestWave 调用 Player.stagger）。
## 占位美术：Polygon2D 色块，后续替换正式图。

@export var hp: int = 3
@export var detect_range: float = 260.0
@export var shoot_cooldown: float = 2.5
@export var wave_speed: float = 150.0

const REST_WAVE: PackedScene = preload("res://scenes/enemies/projectiles/RestWave.tscn")

var player: CharacterBody2D = null
var shoot_timer: float = 0.0
var state: int = 0  # 0=待机，1=攻击


func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	shoot_timer = shoot_cooldown * 0.5


func _physics_process(delta: float) -> void:
	if state == 99:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return

	shoot_timer -= delta
	var dist_x := absf(player.global_position.x - global_position.x)
	var dist_y := absf(player.global_position.y - global_position.y)
	var in_range := dist_x <= detect_range and dist_y <= 120.0

	if in_range and shoot_timer <= 0.0:
		_fire_wave()


func _fire_wave() -> void:
	shoot_timer = shoot_cooldown
	var wave := REST_WAVE.instantiate()
	get_parent().add_child(wave)
	wave.global_position = global_position
	var dir := (player.global_position - global_position).normalized()
	wave.setup(dir, wave_speed)


func take_damage(amount: int, _from_pos: Vector2, from_magic := false) -> void:
	if state == 99:
		return
	if not from_magic:
		GameState.add_music_inspiration(GameState.MUSIC_INSPIRATION_PER_HIT)
	hp -= amount
	if hp <= 0:
		_die()
		return
	_flash()


func _die() -> void:
	state = 99
	$CollisionShape2D.set_deferred("disabled", true)
	_flash()
	await get_tree().create_timer(0.12).timeout
	queue_free()


func _flash() -> void:
	var visual := $Visual as Polygon2D
	visual.self_modulate = Color(4, 4, 4)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(visual):
		visual.self_modulate = Color(1, 1, 1)
