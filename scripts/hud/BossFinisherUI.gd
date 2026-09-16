extends CanvasLayer
## 尾杀 QTE UI。布局放在 BossFinisherUI.tscn，脚本只更新进度和结果。

@onready var progress_label: Label = $Control/Progress
@onready var result_label: Label = $Control/Result
@onready var prompt_label: Label = $Control/Prompt


func _ready() -> void:
	add_to_group("boss_finisher_ui")
	hide_sequence()


func show_sequence(_config: Resource) -> void:
	visible = true
	progress_label.visible = true
	result_label.visible = false
	prompt_label.visible = true
	prompt_label.text = "拔下小提琴"


func set_note_progress(current: int, total: int, perfect_count: int) -> void:
	progress_label.text = "音符 %d/%d    Perfect %d" % [current, total, perfect_count]


func set_note_result(perfect: bool, perfect_count: int) -> void:
	result_label.visible = true
	result_label.text = "Perfect" if perfect else "Miss"
	result_label.modulate = Color(0.4, 1.0, 0.7) if perfect else Color(1.0, 0.35, 0.35)
	progress_label.text = "Perfect %d" % perfect_count


func show_result(success: bool, perfect_count: int, required: int) -> void:
	result_label.visible = true
	result_label.text = ("尾杀成功  Perfect %d/%d" if success else "尾杀失败  Perfect %d/%d") % [perfect_count, required]
	result_label.modulate = Color(0.5, 1.0, 0.75) if success else Color(1.0, 0.45, 0.35)
	prompt_label.text = "拔下小提琴" if success else "趁 Boss 虚弱时补刀"


func show_vulnerable(duration: float) -> void:
	result_label.visible = true
	result_label.text = "Boss 虚弱 %.1f 秒" % duration
	prompt_label.text = "趁 Boss 虚弱时补刀"


func hide_sequence() -> void:
	visible = false
