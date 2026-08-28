extends Area2D
## Day 5：魔法冲刺拾取物。玩家接触 → 获得魔法冲刺（可穿过魔法屏障）+ 提示 + 消失（跨场景保留）。


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if GameState.has_magic_dash:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("grant_magic_dash"):
		body.grant_magic_dash()
	GameState.save_game()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("refresh_abilities"):
		hud.refresh_abilities()
	DialogueBridge.show_cue("res://dialogues/game.dialogue", "pickup_magicdash")
	queue_free()
