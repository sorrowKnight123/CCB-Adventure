extends Node2D
## 开发者敌人实验室：普通小房间 + UI 按钮，用于手动测试所有敌对生物。
## 不是游戏内容，运行方式：在编辑器打开 res://tests/enemy_lab.tscn 后按 F6。

const SCENES: Dictionary = {
	"quarter": "res://scenes/enemies/quarter_note/Enemy.tscn",
	"eighth": "res://scenes/enemies/eighth_note/RangedEnemy.tscn",
	"bass": "res://scenes/enemies/bass_clef/BassClef.tscn",
	"sharp": "res://scenes/enemies/sharp/SharpEnemy.tscn",
	"rest": "res://scenes/enemies/rest/RestEnemy.tscn",
	"piano": "res://scenes/enemies/piano_elite/PianoElite.tscn",
}


func _ready() -> void:
	$UI/Panel/VBox/SpawnQuarter.pressed.connect(_spawn.bind("quarter"))
	$UI/Panel/VBox/SpawnEighth.pressed.connect(_spawn.bind("eighth"))
	$UI/Panel/VBox/SpawnBass.pressed.connect(_spawn.bind("bass"))
	$UI/Panel/VBox/SpawnSharp.pressed.connect(_spawn.bind("sharp"))
	$UI/Panel/VBox/SpawnRest.pressed.connect(_spawn.bind("rest"))
	$UI/Panel/VBox/SpawnPiano.pressed.connect(_spawn.bind("piano"))
	$UI/Panel/VBox/Clear.pressed.connect(_clear_enemies)
	$UI/Panel/VBox/ResetPlayer.pressed.connect(_reset_player)


func _spawn(id: String) -> void:
	var path: String = SCENES.get(id, "")
	if path.is_empty():
		return
	var scene: PackedScene = load(path)
	if scene == null:
		return
	var enemy: Node = scene.instantiate()
	enemy.global_position = Vector2(700 + randi_range(-120, 120), 560)
	add_child(enemy)


func _clear_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()


func _reset_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	if player == null:
		return
	player.global_position = Vector2(200, 560)
	player.velocity = Vector2.ZERO
	player.hp = player.max_hp
	GameState.hp = player.max_hp
	player.mana = GameState.MAX_MANA
	GameState.mana = GameState.MAX_MANA
	player.health_changed.emit(player.hp, player.max_hp)
	player.mana_changed.emit(player.mana, GameState.MAX_MANA)
