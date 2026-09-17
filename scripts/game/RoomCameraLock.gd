@tool
extends Node2D
## 进房间锁镜头：玩家进入 `房间矩形` 时把镜头平滑对到房间中心并锁住，离开时平滑还给玩家。
##
## 用法：随便找个节点挂上这个脚本，把 `房间矩形` 调成房间范围（世界坐标，编辑器里会画出来）。
## 检测区是**自动按矩形生成**的，不用手摆碰撞形状（省得形状和矩形对不上）。
##
## ⚠️ 严格遵守 `agent.md §20 镜头操作规范（严格禁止跳变）`：
##   · 只 tween / lerp，**绝不瞬时赋值** `global_position` / `zoom`
##   · **绝不碰** `position_smoothing_enabled`、`offset`，**绝不调** `reset_smoothing()`
##     （关平滑会让画面瞬间弹到节点位置，且只在玩家移动时看得出来 —— 表现为"偶尔跳一下"）

@export var 房间矩形: Rect2 = Rect2(0, 0, 1280, 720):
	set(value):
		房间矩形 = value
		# 运行时改也要重建检测区（编辑器里不建，免得把场景弄脏）
		if is_node_ready() and not Engine.is_editor_hint():
			_rebuild_area()
## 锁定时把镜头放到多大（>1 = 拉近）。房间比视口小时用它把墙框满。
@export var 锁定缩放: float = 1.4
## 滑入 / 滑出的时长
@export var 相机滑入时长: float = 0.5
## 锁定后每帧逼近目标的速度（越大越紧跟）
@export var 相机跟随速度: float = 10.0
@export var 调试显示范围: bool = true

var _camera: Camera2D = null
var _camera_tween: Tween = null
var _saved_top_level: bool = false
var _saved_position: Vector2 = Vector2.ZERO
var _saved_zoom: Vector2 = Vector2.ONE
var _locked: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	_build_area()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	if _locked:
		_approach_camera(delta)


func _rebuild_area() -> void:
	for child in get_children():
		if child is Area2D:
			child.queue_free()
	_build_area()


func _build_area() -> void:
	## 检测区按 `房间矩形` 自动生成（矩形用世界坐标，形状偏移换算成本地坐标）。
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = 房间矩形.size
	shape.shape = rect
	shape.position = 房间矩形.get_center() - global_position
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or _locked:
		return
	_lock_camera()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player") or not _locked:
		return
	_unlock_camera()


func _acquire_camera() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return false
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	return _camera != null


func _locked_zoom() -> Vector2:
	return Vector2(锁定缩放, 锁定缩放)


func _lock_camera() -> void:
	if not _acquire_camera():
		return
	# 切 top_level 会改变继承来的变换：先存世界坐标，翻转后赋回**同一个值**（值没变，不跳）
	var start_position := _camera.global_position
	_saved_top_level = _camera.top_level
	_saved_position = _camera.position
	_saved_zoom = _camera.zoom
	_camera.top_level = true
	_camera.global_position = start_position
	_kill_tween()
	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_camera, "global_position", 房间矩形.get_center(), 相机滑入时长)
	_camera_tween.tween_property(_camera, "zoom", _locked_zoom(), 相机滑入时长)
	_camera_tween.chain().tween_callback(func() -> void: _locked = true)


func _unlock_camera() -> void:
	_locked = false
	if not is_instance_valid(_camera):
		return
	_kill_tween()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var target := player.global_position if player != null else _camera.global_position
	_camera_tween = create_tween()
	_camera_tween.set_parallel(true)
	_camera_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(_camera, "zoom", _saved_zoom, 相机滑入时长)
	_camera_tween.tween_property(_camera, "global_position", target, 相机滑入时长)
	_camera_tween.chain().tween_callback(_finish_restore)


func _finish_restore() -> void:
	if not is_instance_valid(_camera):
		return
	# 先翻回 top_level，再在**同一次调用里**恢复本地 position（中间状态不会被渲染，所以看不到跳变）
	_camera.top_level = _saved_top_level
	if not _saved_top_level:
		_camera.position = _saved_position
	_camera.zoom = _saved_zoom


func _approach_camera(delta: float) -> void:
	## ⚠️ 只插值，绝不直接赋值（直接赋值就是跳变）。
	if not is_instance_valid(_camera):
		return
	var target_position := 房间矩形.get_center()
	var target_zoom := _locked_zoom()
	var t := clampf(delta * 相机跟随速度, 0.0, 1.0)
	_camera.global_position = _camera.global_position.lerp(target_position, t)
	_camera.zoom = _camera.zoom.lerp(target_zoom, t)
	# 亚像素吸附：免得永远逼近却不到（<1px 看不出来，但能让"锁定"真的锁住）
	if _camera.global_position.distance_to(target_position) < 0.5:
		_camera.global_position = target_position
	if absf(_camera.zoom.x - target_zoom.x) < 0.002:
		_camera.zoom = target_zoom


func _kill_tween() -> void:
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()


func _draw() -> void:
	if not Engine.is_editor_hint() or not 调试显示范围:
		return
	var rect := Rect2(房间矩形.position - global_position, 房间矩形.size)
	draw_rect(rect, Color(0.35, 0.85, 1.0, 0.8), false, 2.0)
