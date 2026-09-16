extends CanvasLayer
## Day 5：场景切换淡入淡出（autoload，跨场景常驻）。
## Door / 标题 / 暂停菜单通过 Transition.fade_to(scene) 切换场景。


var _rect: ColorRect
var _busy: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func fade_to(scene: String) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))
	tw.tween_callback(_fade_in)


## 房间切换：2s 渐黑 → 切场景 → 2s 渐亮。
func fade_to_room(scene: String) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, 2.0)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))
	tw.tween_property(_rect, "color:a", 0.0, 2.0)
	tw.tween_callback(func() -> void: _busy = false)


## 慢速淡入淡出：先 fade_in 秒渐黑 → 切场景 → 保持黑屏 → fade_out 秒渐亮。
func fade_to_slow(scene: String, fade_in: float = 3.0, fade_out: float = 3.0) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 1.0, fade_in)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))
	tw.tween_property(_rect, "color:a", 0.0, fade_out)
	tw.tween_callback(func() -> void: _busy = false)


func _fade_in() -> void:
	var tw := create_tween()
	tw.tween_property(_rect, "color:a", 0.0, 0.25)
	tw.tween_callback(func() -> void: _busy = false)
