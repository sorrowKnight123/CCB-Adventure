extends Area2D
## Day 3：剧情触发区。玩家进入 → 弹 DM 对白（once 则只触发一次）。
## Day 4：trigger_id 非空时跨场景只触发一次（经 GameState 持久化）。
## Day 12：改用 Dialogue Manager——cue 指向 .dialogue 文件里的 ~ 标题，文本统一进 dialogues/。


@export var cue: String = ""
@export var dialogue_file: String = "res://dialogues/game.dialogue"
@export var once: bool = true
@export var trigger_id: String = ""

var _triggered: bool = false


func _ready() -> void:
	# 已触发过的剧情对话直接停用，避免重复弹出
	if trigger_id != "" and GameState.has_trigger(trigger_id):
		set_deferred("monitoring", false)
		return
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _triggered:
		return
	if body.is_in_group("player"):
		if cue != "":
			DialogueBridge.show_cue(dialogue_file, cue)
		if once:
			_triggered = true
			set_deferred("monitoring", false)
		if trigger_id != "":
			GameState.mark_trigger(trigger_id)
