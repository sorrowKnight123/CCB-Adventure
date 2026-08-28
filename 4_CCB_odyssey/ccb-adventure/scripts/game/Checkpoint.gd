extends Area2D
## Day 4：检查点。玩家接触 → 记录复活点 + 点亮（跨场景保留）。

var _active: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _active or not body.is_in_group("player"):
		return
	_active = true
	var scene_path: String = get_tree().current_scene.scene_file_path
	GameState.set_checkpoint(scene_path, global_position)
	GameState.save_game()
	if has_node("Visual"):
		$Visual.self_modulate = Color(1.0, 1.0, 0.6, 1.0)
