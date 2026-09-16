extends Node2D
## 苔藓洞穴 Boss 房控制器：触发战斗、封锁入口/出口并临时锁定摄像机。
## 节点和碰撞形状放在 3_1.tscn，脚本只负责状态和连接。

@export var boss_room_trigger: NodePath = NodePath("Boss_Area")
@export var entrance_door: NodePath = NodePath("door_in")
@export var exit_door: NodePath = NodePath("door_out")
@export var entrance_barrier: NodePath = NodePath("EntranceBarrier")
@export var exit_barrier: NodePath = NodePath("ExitBarrier")
@export var boss_path: NodePath = NodePath("MossResonanceBoss")
@export var entrance_energy_wall: NodePath = NodePath("door_in/EnergyWall")
@export var exit_energy_wall: NodePath = NodePath("door_out/EnergyWall")
@export var boss_room_rect: Rect2 = Rect2(3274, 309, 1280, 720)
@export var camera_slide_duration: float = 0.8

var battle_active: bool = false
var battle_finished: bool = false
var _player_inside_room: bool = false
var _camera: Camera2D
var _camera_slide: Tween
var _saved_camera_limits := Rect2i()
var _saved_camera_smoothing: bool = false
var _saved_camera_offset := Vector2.ZERO
var _saved_camera_top_level: bool = false
var _saved_camera_position := Vector2.ZERO


func _ready() -> void:
	add_to_group("boss_arena")
	var trigger := get_node_or_null(boss_room_trigger) as Area2D
	if trigger:
		trigger.body_entered.connect(_on_room_trigger_body_entered)
		trigger.body_exited.connect(_on_room_trigger_body_exited)
		trigger.monitoring = true
	_set_barrier_enabled(entrance_barrier, false)
	_set_barrier_enabled(exit_barrier, false)
	_set_door_enabled(entrance_door, true)
	_set_door_enabled(exit_door, true)
	_set_energy_wall_enabled(false)
	call_deferred("_apply_defeated_state")


func _exit_tree() -> void:
	if battle_active:
		AudioManager.return_to_music("background")


func _apply_defeated_state() -> void:
	if not GameState.is_boss_defeated("moss_resonance_boss"):
		return
	battle_finished = true
	var boss := get_node_or_null(boss_path)
	if boss and is_instance_valid(boss) and boss.has_method("_show_defeated_background"):
		boss._show_defeated_background()
	_set_barrier_enabled(entrance_barrier, false)
	_set_barrier_enabled(exit_barrier, false)
	_set_door_enabled(entrance_door, true)
	_set_door_enabled(exit_door, true)
	_set_energy_wall_enabled(false)
	if not _player_inside_room:
		_restore_camera()


func _on_room_trigger_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside_room = true
		if battle_finished:
			_lock_camera_after_gameflow()
		else:
			begin_battle()


func _on_room_trigger_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside_room = false
	if not battle_active:
		_restore_camera()


func begin_battle() -> void:
	if battle_active or battle_finished:
		return
	battle_active = true
	_set_door_enabled(entrance_door, false)
	_set_door_enabled(exit_door, false)
	_set_barrier_enabled(entrance_barrier, true)
	_set_barrier_enabled(exit_barrier, true)
	_set_energy_wall_enabled(true)
	_lock_camera_after_gameflow()
	var boss := get_node_or_null(boss_path)
	if boss and boss.has_method("start_battle"):
		if boss.has_signal("victory"):
			boss.victory.connect(_on_boss_victory)
		boss.start_battle()


func _on_boss_victory() -> void:
	if battle_finished:
		return
	battle_active = false
	battle_finished = true
	_set_barrier_enabled(entrance_barrier, false)
	_set_barrier_enabled(exit_barrier, false)
	_set_door_enabled(entrance_door, true)
	_set_door_enabled(exit_door, true)
	_set_energy_wall_enabled(false)


func _set_door_enabled(path: NodePath, enabled: bool) -> void:
	var door := get_node_or_null(path) as Area2D
	if door:
		door.monitoring = enabled
		door.monitorable = enabled


func _set_barrier_enabled(path: NodePath, enabled: bool) -> void:
	var barrier := get_node_or_null(path) as CollisionObject2D
	if barrier:
		barrier.set_deferred("collision_layer", 1 if enabled else 0)
		barrier.set_deferred("collision_mask", 2 if enabled else 0)


func _set_energy_wall_enabled(enabled: bool) -> void:
	var entrance_wall := get_node_or_null(entrance_energy_wall) as CanvasItem
	var exit_wall := get_node_or_null(exit_energy_wall) as CanvasItem
	if entrance_wall:
		entrance_wall.visible = enabled
	if exit_wall:
		exit_wall.visible = enabled


func _lock_camera() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	if _camera == null:
		return
	_saved_camera_limits = Rect2i(_camera.limit_left, _camera.limit_top,
		_camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top)
	_saved_camera_smoothing = _camera.position_smoothing_enabled
	_saved_camera_offset = _camera.offset
	_camera.limit_left = int(boss_room_rect.position.x)
	_camera.limit_top = int(boss_room_rect.position.y)
	_camera.limit_right = int(boss_room_rect.end.x)
	_camera.limit_bottom = int(boss_room_rect.end.y)
	_camera.position_smoothing_enabled = false
	_camera.offset = Vector2.ZERO
	_camera.reset_smoothing()


func _lock_camera_after_gameflow() -> void:
	await get_tree().process_frame
	if battle_active or (battle_finished and _player_inside_room):
		_slide_camera_into_room()


func _slide_camera_into_room() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	if _camera == null:
		return
	_saved_camera_limits = Rect2i(_camera.limit_left, _camera.limit_top,
		_camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top)
	_saved_camera_smoothing = _camera.position_smoothing_enabled
	_saved_camera_offset = _camera.offset
	_saved_camera_top_level = _camera.top_level
	_saved_camera_position = _camera.position
	var start_position := _camera.global_position
	_camera.top_level = true
	_camera.position_smoothing_enabled = false
	_camera.offset = Vector2.ZERO
	_camera.global_position = start_position
	_camera_slide = create_tween()
	_camera_slide.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_slide.tween_property(_camera, "global_position", boss_room_rect.get_center(), camera_slide_duration)
	await _camera_slide.finished
	if not (battle_active or (battle_finished and _player_inside_room)) or not is_instance_valid(_camera):
		return
	_lock_camera_limits()


func _lock_camera_limits() -> void:
	_camera.limit_left = int(boss_room_rect.position.x)
	_camera.limit_top = int(boss_room_rect.position.y)
	_camera.limit_right = int(boss_room_rect.end.x)
	_camera.limit_bottom = int(boss_room_rect.end.y)
	_camera.position_smoothing_enabled = false
	_camera.offset = Vector2.ZERO
	_camera.global_position = boss_room_rect.get_center()
	_camera.reset_smoothing()


func _restore_camera() -> void:
	if _camera_slide and _camera_slide.is_valid():
		_camera_slide.kill()
	if not is_instance_valid(_camera):
		return
	_camera.limit_left = _saved_camera_limits.position.x
	_camera.limit_top = _saved_camera_limits.position.y
	_camera.limit_right = _saved_camera_limits.end.x
	_camera.limit_bottom = _saved_camera_limits.end.y
	_camera.position_smoothing_enabled = _saved_camera_smoothing
	_camera.offset = _saved_camera_offset
	_camera.top_level = _saved_camera_top_level
	if not _saved_camera_top_level:
		_camera.position = _saved_camera_position
	_camera.reset_smoothing()
