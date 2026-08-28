extends Area2D
## 音符货币拾取物。玩家接触 -> 增加 notes -> 保存 -> 消失。
## 数量在场景里用 amount 调（以后想改单个音符价值只改这里）。
@export var amount: int = 1

var _taken: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _taken:
		return
	if not body.is_in_group("player"):
		return
	_taken = true
	GameState.add_notes(amount)
	GameState.save_game()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_note_toast"):
		hud.show_note_toast(amount)
	queue_free()
