extends Node
## 魔法飞行冒烟测试：在 enemy_lab 房间内，从最左侧起飞，确认能飞到最右侧才被墙停下。

var _lab: Node
var _player: CharacterBody2D
var _physics_frames: int = 0
var _started: bool = false
var _done: bool = false


func _ready() -> void:
	_lab = load("res://tests/enemy_lab.tscn").instantiate()
	add_child(_lab)
	await get_tree().process_frame
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if _player == null:
		_finish(false)
		return
	_player.global_position = Vector2(200, 560)
	_player.velocity = Vector2.ZERO
	_player.has_magic_flight = true
	GameState.has_magic_flight = true
	_player.facing = 1
	_player._start_flight()
	_started = true


func _physics_process(_delta: float) -> void:
	if not _started or _done:
		return
	_physics_frames += 1
	var x := _player.global_position.x
	if x > 1200.0:
		_finish(true)
	elif _physics_frames > 180:
		print("FLIGHT DEBUG x=%.1f state=%s vel=%s wall=%s floor=%s" % [x, str(_player.state), str(_player.velocity), str(_player.is_on_wall()), str(_player.is_on_floor())])
		_finish(false)


func _finish(ok: bool) -> void:
	if _done:
		return
	_done = true
	print("FLIGHT TEST " + ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
