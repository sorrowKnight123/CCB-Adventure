extends Area2D
## Day 4：88 的线索收集物。玩家接触 → 通知 GameFlow 计数 + 弹提示，然后消失。
## Day 5：泛化为「收集品」（线索 / 日记 / 信件统一）。已收集的经 GameState 持久化。


@export var clue_cue: String = ""
@export var clue_id: String = ""

var _collected: bool = false


func _ready() -> void:
	add_to_group("clues")
	# 已收集的线索直接销毁，不连 body_entered，避免重复触发
	if clue_id != "" and GameState.has_collectible(clue_id):
		queue_free()
		return
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if body.is_in_group("player"):
		_collected = true
		var flow := get_tree().get_first_node_in_group("gameflow")
		if flow and flow.has_method("on_collectible_collected"):
			flow.on_collectible_collected(clue_id, clue_cue)
		queue_free()
