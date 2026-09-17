extends Node2D
## 音乐小游戏测试房间。Godot 里 F6 直接跑这个场景。
##
## 通关会写进存档（永久完成，进区不再触发），所以这里给了一个「重置通关状态」按钮，
## 方便反复试。参数不用改代码 —— 全在 Inspector 里：
##   MusicGame 节点      → 演示节奏 / 音符特效 / 自动平铺 / 调试显示槽位
##   Slimes 下的史莱姆   → 每只的音符（下拉框，颜色跟着音走）
##   配置(.tres)         → 演奏顺序 / 通关奖励 / 演示间隔

@onready var _music_game: Node2D = $MusicGame


func _ready() -> void:
	$UI/Panel/VBox/ResetTrigger.pressed.connect(_on_reset_trigger_pressed)
	$UI/Panel/VBox/Reload.pressed.connect(_on_reload_pressed)


func _on_reset_trigger_pressed() -> void:
	var trigger_id: String = str(_music_game.get("触发ID"))
	GameState.triggered_ids.erase(trigger_id)
	GameState.save_game()
	get_tree().reload_current_scene()


func _on_reload_pressed() -> void:
	get_tree().reload_current_scene()
