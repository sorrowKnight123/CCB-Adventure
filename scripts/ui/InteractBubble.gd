@tool
class_name InteractBubble
extends Control
## 统一的「按 X 交互」提示气泡（留声机的 E、音乐小游戏谱台的 W、隐藏房间钢琴的 W……）。
##
## 进入交互范围时渐显、离开时渐隐，免得突兀地闪出来。
## 结构照抄 `Phonograph.tscn` 原来那个 Bubble：Control → PanelContainer → Label。
##
## 用法：把它挂到可交互物下面，位置就是相对那个物的（面板自带向上偏移），然后：
##     bubble.显示()   /   bubble.隐藏()
## ⚠️ 调用方可以每帧无脑调（例如 `_process` 里按范围判断）—— 内部记了状态，
##    重复调用不会重开 tween，否则渐显动画永远播不完。

@export var 按键文本: String = "E":
	set(value):
		按键文本 = value
		_apply_text()

@export var 渐显时长: float = 0.15
@export var 渐隐时长: float = 0.2

var _shown: bool = false
var _tween: Tween = null


func _ready() -> void:
	_apply_text()
	if not Engine.is_editor_hint():
		modulate.a = 0.0
		_shown = false


func 显示() -> void:
	_set_shown(true)


func 隐藏() -> void:
	_set_shown(false)


func _set_shown(shown: bool) -> void:
	if shown == _shown:
		return
	_shown = shown
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0 if shown else 0.0,
		渐显时长 if shown else 渐隐时长)


func _apply_text() -> void:
	var label := get_node_or_null("Panel/Key") as Label
	if label != null:
		label.text = 按键文本
