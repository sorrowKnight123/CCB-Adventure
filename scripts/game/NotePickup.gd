extends Area2D
## 音符货币拾取物。玩家接触 -> 增加 notes -> 保存 -> 消失。
## 普通地图收集物与敌人掉落复用此场景；掉落的散射轨迹由 setup_drop 配置。
@export var amount: int = 1
## 拾取时是否弹「+N」提示。一次刷一大堆（例如小游戏通关奖励散落一地）时关掉，
## 免得文字刷屏破坏沉浸感 —— 玩家看左上角的音符计数就知道拿了多少。
@export var 显示提示: bool = true

var _taken: bool = false
var _is_drop: bool = false
var _drop_origin: Vector2 = Vector2.ZERO
var _drop_target: Vector2 = Vector2.ZERO
var _drop_elapsed: float = 0.0
var _drop_duration: float = 0.38
var _bob_time: float = 0.0
var _visual_base_position: Vector2 = Vector2.ZERO

@onready var visual: Sprite2D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_base_position = visual.position


func setup_drop(drop_amount: int, is_large: bool, target_offset: Vector2) -> void:
	amount = maxi(drop_amount, 1)
	_is_drop = true
	_drop_origin = global_position
	_drop_target = _drop_origin + target_offset
	_drop_elapsed = 0.0
	_drop_duration = 0.38 if not is_large else 0.48
	visual.scale = Vector2.ONE * (1.5 if is_large else 0.3)
	_visual_base_position = visual.position


func _physics_process(delta: float) -> void:
	if _is_drop:
		_drop_elapsed += delta
		var progress := clampf(_drop_elapsed / maxf(_drop_duration, 0.01), 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - progress, 2.0)
		var arc := sin(progress * PI) * 22.0
		global_position = _drop_origin.lerp(_drop_target, eased) + Vector2(0.0, -arc)
		if progress >= 1.0:
			_is_drop = false
		_bob_time = 0.0
	else:
		_bob_time += delta
		visual.position = _visual_base_position + Vector2(0.0, sin(_bob_time * 3.0) * 3.0)


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
