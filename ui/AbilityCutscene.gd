extends CanvasLayer
## 能力获取过场动画（复用）。
## 流程：暂停游戏 → 背景渐暗 → 图标+文字一起淡入 → [Space] 继续 → 全部一起淡出 → 恢复游戏。
## 节点结构与动画关键帧都在 AbilityCutscene.tscn（AnimationPlayer，编辑器可调），本脚本只留逻辑。

signal finished

@onready var _anim: AnimationPlayer = $AnimationPlayer
@onready var _title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var _icon: TextureRect = $CenterContainer/VBoxContainer/Icon
@onready var _name_label: Label = $CenterContainer/VBoxContainer/NameLabel
@onready var _desc_label: Label = $CenterContainer/VBoxContainer/DescLabel
@onready var _ability_audio: AudioStreamPlayer = $AbilityAudio

var _active: bool = false
var _can_continue: bool = false


func _ready() -> void:
	add_to_group("ability_cutscene")
	_anim.animation_finished.connect(_on_animation_finished)


## 外部入口：播放能力过场。icon_texture 为 null 时图标区域留空（占位，后续放图即可）。
## 继续提示在 show_ability 动画末尾（约 3 秒后）才淡入，期间按 Space 无效，保证至少 3 秒阅读时间。
## `title` 是顶部那行小标题，默认「获得能力」；拿物品时传「获得物品」之类。
func show_ability(icon_texture: Texture2D, ability_name: String, ability_desc: String = "",
		title: String = "获得能力") -> void:
	if _active:
		return
	_active = true
	_can_continue = false
	_title_label.text = title
	_icon.texture = icon_texture
	_name_label.text = ability_name
	_desc_label.text = ability_desc
	_ability_audio.play()
	get_tree().paused = true
	_anim.play("show_ability")


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"show_ability":
		_can_continue = true
	elif anim_name == &"fade_out":
		_finish()


func _input(event: InputEvent) -> void:
	if not _active or not _can_continue:
		return
	if event.is_action_pressed("ui_accept"):
		_can_continue = false
		_anim.play("fade_out")


func _finish() -> void:
	if not _active:
		return
	_active = false
	get_tree().paused = false
	finished.emit()
	queue_free()
