extends ColorRect
## 音乐厅背景的「压暗遮罩」：铺满整个房间，夹在**背景与跳跳乐之间** ——
## 只压暗背景（含地面美术层），不会压暗平台与鼓，所以能把跳跳乐凸显出来。
##
## 用途：boss 二阶段平台出现时，调用 `设置变暗(true)` 把背景压暗，平台就跳出来了。
## **默认是关的**（`_ready` 里 alpha=0），接口留好、调用方以后接（本轮不接）。
##
## 调试：默认开着 `调试按键`，在场景里按 **B** 就能切换，方便直接看效果。

@export var 变暗程度: float = 0.55      ## 完全不透明时压多黑（0~1）
@export var 渐变时长: float = 0.4       ## 开关的过渡时长（秒）
@export var 调试按键: bool = true       ## 是否允许用 B 键手动切换（上线前可关）

var _on: bool = false
var _b_was_down: bool = false


func _ready() -> void:
	color = Color(0, 0, 0, 0)
	set_process(调试按键)


## 给 boss 二阶段调用：把背景压暗/恢复。`立即` = 不走渐变。
func 设置变暗(on: bool, 立即: bool = false) -> void:
	_on = on
	var 目标: float = 变暗程度 if on else 0.0
	if 立即:
		color.a = 目标
		return
	var tween := create_tween()
	tween.tween_property(self, "color:a", 目标, 渐变时长)


func 是否变暗() -> bool:
	return _on


func _process(_delta: float) -> void:
	# 按一下 B 切一次（不是按住连切）
	var b_down := Input.is_physical_key_pressed(KEY_B)
	if b_down and not _b_was_down:
		设置变暗(not _on)
	_b_was_down = b_down
