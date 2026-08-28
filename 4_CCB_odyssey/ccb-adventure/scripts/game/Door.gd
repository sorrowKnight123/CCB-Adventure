extends Area2D
## Day 4：房间门。玩家进入 → 记录目标出生点 + 切换场景（跨房间移动）。

@export var target_scene: String = ""
@export var target_spawn_id: String = ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	GameState.set_spawn(target_scene, target_spawn_id)
	GameState.save_game()
	Transition.fade_to_room(target_scene)
