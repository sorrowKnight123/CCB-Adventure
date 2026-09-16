extends Control
## Day 11：标题界面。UI 布局 / 节点 / 样式都在 scenes/title.tscn 里（编辑器可视化编辑）。
## 本脚本只负责逻辑：BGM 循环兜底、按钮信号、设置面板开关、继续按钮存档状态。

@onready var _bgm: AudioStreamPlayer = $BGM
@onready var _continue_btn: Button = $ContinueBtn
@onready var _settings_panel: Control = $SettingsPanel


func _ready() -> void:
	# BGM 无限循环：mp3 自身 loop 开启，finished 再兜底重播一遍
	var stream: AudioStream = _bgm.stream
	if stream:
		stream.loop = true
	_bgm.finished.connect(_on_bgm_finished)

	# 继续按钮按存档状态初始化
	_continue_btn.text = "继续游戏" if GameState.has_save() else "（暂无存档）"
	_continue_btn.disabled = not GameState.has_save()

	$StartBtn.pressed.connect(_on_new_game)
	$ContinueBtn.pressed.connect(_on_continue)
	$SettingsBtn.pressed.connect(_on_settings)
	$SettingsPanel/Box/VBox/BackBtn.pressed.connect(func() -> void: _settings_panel.visible = false)


func _on_bgm_finished() -> void:
	_bgm.play()


func _on_new_game() -> void:
	GameState.reset()
	MetSys.reset_state()
	MetSys.set_save_data()
	Transition.fade_to(GameState.START_SCENE)


func _on_continue() -> void:
	if GameState.load_game():
		if MetSys.save_data == null:
			MetSys.set_save_data()
		Transition.fade_to(GameState.spawn_scene)


func _on_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible
