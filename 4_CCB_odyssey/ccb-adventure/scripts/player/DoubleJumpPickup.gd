extends Area2D
## Day 4：二段跳拾取物。玩家接触 → 获得二段跳 + 弹提示 + 消失（跨场景保留）。


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if GameState.has_double_jump:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("grant_double_jump"):
		body.grant_double_jump()
	GameState.save_game()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("refresh_abilities"):
		hud.refresh_abilities()
	DialogueBridge.show_cue("res://dialogues/game.dialogue", "pickup_doublejump")
	queue_free()
