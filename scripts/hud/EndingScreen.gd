extends CanvasLayer
## Day 3：结局画面 "TO BE CONTINUED"。击败 Boss 后由 GameFlow 调用 show_ending()。


## 结局类型。不传参就是普通结局（兼容既有调用）。
enum 结局类型 { 普通, 真结局 }

const 文案 := {
	结局类型.普通: {
		"标题": "TO BE CONTINUED",
		"副标题": "88 为什么会失去理智？……",
	},
	结局类型.真结局: {
		"标题": "狂喜",
		"副标题": "77 与 88 的合奏 —— 不和谐音像雪一样消融。",
	},
}

var _shown: bool = false
var _类型: int = 结局类型.普通
var _title: Label = null
var _subtitle: Label = null


func _ready() -> void:
	add_to_group("ending")
	_build_ui()
	hide()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var title := Label.new()
	_title = title
	title.text = "TO BE CONTINUED"
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.offset_top = -80.0
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(title)

	var subtitle := Label.new()
	_subtitle = subtitle
	subtitle.text = "88 为什么会失去理智？……"
	subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.offset_top = 40.0
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.85, 1, 1))
	add_child(subtitle)

	var hint := Label.new()
	hint.text = "按 R 重新开始"
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -220.0
	hint.offset_right = -24.0
	hint.offset_top = -60.0
	hint.offset_bottom = -24.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(hint)


## `类型` 用 结局类型 枚举；不传参 = 普通结局（兼容既有调用）
func show_ending(类型: int = 结局类型.普通) -> void:
	_类型 = 类型
	var 条: Dictionary = 文案.get(类型, 文案[结局类型.普通])
	if _title != null:
		_title.text = 条["标题"]
	if _subtitle != null:
		_subtitle.text = 条["副标题"]
	_shown = true
	show()


func 当前结局类型() -> int:
	return _类型


func _process(_delta: float) -> void:
	if _shown and Input.is_action_just_pressed("restart"):
		GameState.reset()
		get_tree().change_scene_to_file(GameState.spawn_scene)
