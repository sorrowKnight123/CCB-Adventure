extends Node
## Day 4：房间协调器。每房间一个：设置相机边界、初始化 HUD 线索、Boss 房连接结局。


@export var camera_left: int = 0
@export var camera_right: int = 1150
@export var camera_top: int = -200
@export var camera_bottom: int = 700
@export var is_boss_room: bool = false

var _tracked_player: Node2D


func _ready() -> void:
	add_to_group("gameflow")
	call_deferred("_post_ready")


func _post_ready() -> void:
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

	if is_boss_room:
		var boss := get_tree().get_first_node_in_group("boss")
		if boss and boss.has_signal("defeated"):
			boss.defeated.connect(_on_boss_defeated)


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


func _on_boss_defeated() -> void:
	GameState.save_game()
	await get_tree().create_timer(1.5).timeout
	var ending := get_tree().get_first_node_in_group("ending")
	if ending and ending.has_method("show_ending"):
		ending.show_ending()
