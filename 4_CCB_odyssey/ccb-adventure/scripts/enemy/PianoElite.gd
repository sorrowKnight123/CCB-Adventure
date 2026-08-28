extends CharacterBody2D
## 钢琴精英：漂浮型区域弹幕怪。循环使用五线谱横扫 / 螺旋音浪 / 音阶坠落。
## 半血后攻击节奏加快、螺旋弹更多。占位美术：Polygon2D 色块，后续替换正式图。

enum State { ALIVE, DEAD }

@export var hp: int = 60
@export var max_hp: int = 60
@export var cycle_cooldown: float = 2.0
@export var enraged_cycle_cooldown: float = 1.3
@export var line_speed: float = 200.0
@export var spiral_speed: float = 180.0
@export var spiral_count: int = 8
@export var spiral_count_enraged: int = 12
@export var fall_count: int = 3

const ENEMY_PROJECTILE: PackedScene = preload("res://scenes/enemies/projectiles/EnemyProjectile.tscn")
const STAFF_LINE: PackedScene = preload("res://scenes/enemies/projectiles/StaffLine.tscn")
const FALLING_NOTE: PackedScene = preload("res://scenes/enemies/projectiles/FallingNote.tscn")

@onready var visual: Sprite2D = $Sprite2D

var player: CharacterBody2D = null
var state: State = State.ALIVE
var attack_index: int = 0
var cycle_timer: float = 0.0
var _attack_state: int = 0  # 0=无，1=五线谱，2=螺旋，3=坠note
var _attack_timer: float = 0.0
var _burst_count: int = 0
var _line_offsets: Array[float] = [20.0, 25.0, 30.0, 35.0, 40.0]


func _ready() -> void:
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	cycle_timer = 1.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return

	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		return

	if _attack_state != 0:
		_process_attack(delta)
	else:
		cycle_timer -= delta
		if cycle_timer <= 0.0:
			_start_attack(attack_index)
			attack_index = (attack_index + 1) % 3


func _is_enraged() -> bool:
	return hp <= max_hp / 2


func _start_attack(index: int) -> void:
	_attack_state = index + 1
	_attack_timer = 0.0
	_burst_count = 0


func _process_attack(delta: float) -> void:
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return

	match _attack_state:
		1:  # 五条水平谱线
			if _burst_count < _line_offsets.size():
				_spawn_staff_line(_line_offsets[_burst_count])
				_burst_count += 1
				_attack_timer = 0.12
			else:
				_end_attack()
		2:  # 螺旋音浪
			var count := spiral_count_enraged if _is_enraged() else spiral_count
			if _burst_count < count:
				_spawn_spiral_bullet(_burst_count, count)
				_burst_count += 1
				_attack_timer = 0.06
			else:
				_end_attack()
		3:  # 音阶坠落
			if _burst_count < fall_count:
				_spawn_falling_note(_burst_count)
				_burst_count += 1
				_attack_timer = 0.35
			else:
				_end_attack()
		_:
			_end_attack()


func _spawn_staff_line(offset_y: float) -> void:
	var line := STAFF_LINE.instantiate()
	get_parent().add_child(line)
	line.global_position = global_position + Vector2(0, offset_y)
	var dir := 1.0 if player.global_position.x >= global_position.x else -1.0
	line.setup(Vector2(dir, 0), line_speed)


func _spawn_spiral_bullet(index: int, total: int) -> void:
	var bullet := ENEMY_PROJECTILE.instantiate()
	get_parent().add_child(bullet)
	bullet.global_position = global_position
	bullet.damage = 1
	var angle := TAU * float(index) / float(total)
	bullet.setup(Vector2(cos(angle), sin(angle)), spiral_speed)


func _spawn_falling_note(index: int) -> void:
	var note := FALLING_NOTE.instantiate()
	get_parent().add_child(note)
	var px := player.global_position.x if player else global_position.x
	note.global_position = Vector2(px + float(index - 1) * 40.0, global_position.y - 260.0)
	note.damage = 1


func _end_attack() -> void:
	_attack_state = 0
	_attack_timer = 0.0
	cycle_timer = enraged_cycle_cooldown if _is_enraged() else cycle_cooldown


func take_damage(amount: int, _from_pos: Vector2, from_magic := false) -> void:
	if state == State.DEAD:
		return
	if not from_magic:
		GameState.add_music_inspiration(GameState.MUSIC_INSPIRATION_PER_HIT)
	hp -= amount
	if hp <= 0:
		_die()
		return
	_flash()


func _die() -> void:
	state = State.DEAD
	$CollisionShape2D.set_deferred("disabled", true)
	_flash()
	await get_tree().create_timer(0.15).timeout
	queue_free()


func _flash() -> void:
	visual.self_modulate = Color(4, 4, 4)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(visual):
		visual.self_modulate = Color(1, 1, 1)
