extends CharacterBody2D
## 音符货币拾取物。玩家接触 -> 增加 notes -> 保存 -> 消失。
##
## ── 节点结构 ──
##   自己（CharacterBody2D）  collision_mask = 17（实心地形 1 + 单向平台 16）→ 用于**地形碰撞**
##   └─ PickupArea（Area2D）  collision_mask = 2（玩家）              → 用于**检测玩家**
##   └─ Visual（Sprite2D）
##
## ── 三种出场方式 ──
##   默认            —— 原地待机（手摆的地图收集物用；**不施加重力**，摆放位置即最终位置）
##   setup_drop()    —— 敌人掉落：沿抛物线小跳到指定落点（不走物理，行为与以前完全一致）
##   setup_launch()  —— 受重力抛出去（小游戏通关奖励用）：**只给一个初速度**，
##                      撞墙 / 落平台 / 落斜坡全交给物理引擎，不预判任何落点。

@export var amount: int = 1
## 拾取时是否弹「+N」提示。一次刷一大堆（例如小游戏通关奖励散落一地）时关掉，
## 免得文字刷屏破坏沉浸感 —— 玩家看左上角的音符计数就知道拿了多少。
@export var 显示提示: bool = true
## 抛落时的重力（跟玩家一致 1200）。项目没设 2d/default_gravity，
## 直接用引擎默认 980 手感会偏飘。
@export var 重力: float = 1200.0

var _taken: bool = false
var _bob_time: float = 0.0
var _visual_base_position: Vector2 = Vector2.ZERO

# setup_drop（敌人掉落式）
var _is_drop: bool = false
var _drop_origin: Vector2 = Vector2.ZERO
var _drop_target: Vector2 = Vector2.ZERO
var _drop_elapsed: float = 0.0
var _drop_duration: float = 0.38

# setup_launch（物理抛落式）
var _launched: bool = false

@onready var visual: Sprite2D = $Visual
@onready var _pickup_area: Area2D = $PickupArea


func _ready() -> void:
	_pickup_area.body_entered.connect(_on_body_entered)
	_visual_base_position = visual.position


func setup_drop(drop_amount: int, is_large: bool, target_offset: Vector2) -> void:
	## 敌人掉落：沿抛物线小跳到落点后停住。**不走物理**，行为与以前一致。
	amount = maxi(drop_amount, 1)
	_is_drop = true
	_drop_origin = global_position
	_drop_target = _drop_origin + target_offset
	_drop_elapsed = 0.0
	_drop_duration = 0.38 if not is_large else 0.48
	visual.scale = Vector2.ONE * (1.5 if is_large else 0.3)
	_visual_base_position = visual.position


func setup_launch(launch_amount: int, initial_velocity: Vector2) -> void:
	## 受重力抛出去：**只记下初速度**，之后每帧加重力 + move_and_slide()。
	## 撞墙、落平台、落斜坡、被地形挡住 —— 全部由物理引擎处理，这里不预判落点。
	amount = maxi(launch_amount, 1)
	_is_drop = false
	_launched = true
	velocity = initial_velocity


func _physics_process(delta: float) -> void:
	if _launched:
		_process_launch(delta)
		return
	if _is_drop:
		_process_drop(delta)
		return
	# 待机：原地轻微上下浮动（手摆的地图收集物不会掉下去）
	_bob_time += delta
	visual.position = _visual_base_position + Vector2(0.0, sin(_bob_time * 3.0) * 3.0)


func _process_launch(delta: float) -> void:
	velocity.y += 重力 * delta
	move_and_slide()
	# 落地就停住（撞墙不算落地：move_and_slide 会沿墙滑下来，最后仍然落地）
	if is_on_floor():
		velocity = Vector2.ZERO
		_launched = false
		_bob_time = 0.0


func _process_drop(delta: float) -> void:
	_drop_elapsed += delta
	var progress := clampf(_drop_elapsed / maxf(_drop_duration, 0.01), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 2.0)
	var arc := sin(progress * PI) * 22.0
	global_position = _drop_origin.lerp(_drop_target, eased) + Vector2(0.0, -arc)
	if progress >= 1.0:
		_is_drop = false
	_bob_time = 0.0


func _on_body_entered(body: Node2D) -> void:
	if _taken:
		return
	if not body.is_in_group("player"):
		return
	_taken = true
	GameState.add_notes(amount)
	GameState.save_game()
	if 显示提示:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_note_toast"):
			hud.show_note_toast(amount)
	queue_free()
