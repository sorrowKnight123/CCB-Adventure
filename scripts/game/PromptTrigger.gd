extends Area2D
## 非阻塞教学提示触发器：玩家进入后让 TutorialPrompt 显示一行文字，不冻结操作。
## 布局/文本都在 main.tscn 场景里配置；脚本只做触发。
@export var text: String = ""
@export var once: bool = true

var _triggered: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if not body.is_in_group("player"):
		return
	if text.is_empty():
		return
	# 教学提示区域：如果上一段 DM 对白还没结束，直接打断它再显示新提示
	if DialogueBridge.is_active:
		DialogueBridge.interrupt()
	var prompt := get_tree().get_first_node_in_group("tutorial_prompt")
	if prompt and prompt.has_method("show_prompt"):
		prompt.show_prompt(text)
	if once:
		_triggered = true
		set_deferred("monitoring", false)
