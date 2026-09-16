extends Area2D
## 危险区域（Area2D 版）：用碰撞形状精确圈定危险范围，玩家进入即触发危险伤害。
## 用法：场景里放 DangerZone 节点 + CollisionShape2D（编辑器里直接拖拽形状 = 判定范围，所见即所得）。
## 触发后复用玩家的完整危险流程（_danger_hit：减血 + fail 死亡动画 + 回本房间 spawnpoint）。

@export var 伤害: int = 2            # 触发时扣除的 HP
@export var 触发冷却: float = 0.5    # 触发间隔（秒），防边缘抖动/多区域连续触发

var _cooldown: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # 检测玩家（layer 2 = bit 1）
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _on_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0:
		return
	if body.is_in_group("player") and body.has_method("_danger_hit"):
		_cooldown = 触发冷却
		body._danger_hit()
