extends Area2D
## 魔法飞行拾取物：玩家接触 -> 获得魔法飞行 -> 保存 -> 刷新 HUD -> 对白提示 -> 消失。
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if GameState.has_magic_flight:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("grant_magic_flight"):
		body.grant_magic_flight()
	GameState.save_game()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("refresh_abilities"):
		hud.refresh_abilities()
	DialogueBridge.show_cue("res://dialogues/game.dialogue", "pickup_magicflight")
	queue_free()
