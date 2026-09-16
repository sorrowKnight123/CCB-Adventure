extends CanvasLayer
## 非阻塞教学提示：底部居中显示一行操作提示，不冻结玩家。
## 显示时长固定 5 秒，玩家无法取消；进入新的提示会立刻替换并重置 5 秒计时。

const SHOW_SECONDS := 5.0
const FADE_IN := 0.15
const FADE_OUT := 0.4

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Label

var _tween: Tween = null


func _ready() -> void:
	add_to_group("tutorial_prompt")
	panel.modulate.a = 0.0
	panel.hide()


func show_prompt(text: String) -> void:
	if text.is_empty():
		return
	# 新提示到来：重置计时（打断上一个提示）
	if _tween and _tween.is_valid():
		_tween.kill()
	label.text = text
	panel.show()
	panel.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(panel, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(SHOW_SECONDS)
	_tween.tween_property(panel, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(panel.hide)
