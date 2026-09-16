extends Node
## Day 4：房间协调器。每房间一个：设置相机边界、初始化 HUD 线索。


@export var camera_left: int = 0
@export var camera_right: int = 1150
@export var camera_top: int = -200
@export var camera_bottom: int = 700
var _tracked_player: Node2D


func _ready() -> void:
	add_to_group("gameflow")
	call_deferred("_post_ready")


func _post_ready() -> void:
	AudioManager.start_background_music()
	if MetSys.save_data == null:
		MetSys.set_save_data()

	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_collect_count"):
		hud.set_collect_count(GameState.collected_ids.size(), GameState.COLLECT_TOTAL)

	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player:
		_tracked_player = player
		var cam := player.get_node_or_null("Camera2D") as Camera2D
		if cam:
			cam.limit_left = camera_left
			cam.limit_right = camera_right
			cam.limit_top = camera_top
			cam.limit_bottom = camera_bottom

func _physics_process(_delta: float) -> void:
	if _tracked_player and MetSys.current_room and MetSys.save_data:
		MetSys.set_player_position(_tracked_player.global_position)


func on_collectible_collected(clue_id: String, clue_cue: String = "") -> void:
	GameState.collect(clue_id)
	GameState.save_game()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_collect_count"):
		hud.set_collect_count(GameState.collected_ids.size(), GameState.COLLECT_TOTAL)
	if clue_cue != "":
		DialogueBridge.show_cue("res://dialogues/clues.dialogue", clue_cue)
