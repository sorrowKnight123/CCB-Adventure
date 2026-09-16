extends Node
## 对白桥接（Day 12）：把旧 DialogueBox 的「show_lines + is_active」契约桥到 Dialogue Manager 气球。
## autoload（排在 DialogueManager 之后）。保持 group "dialogue" + is_active，
## 使 Player/敌人软冻结与 test_dorm_runner 完全无需改动。
## 唯一入口 show_cue()：同步置 is_active=true（复刻旧 show_lines 同步语义，软冻结当帧生效），
## 对话结束（dialogue_ended）或切场景（气球随旧场景销毁）自动解锁。
## 进入新的非打断对话/教学区域时，可调用 interrupt() 直接打断上一段对白。

var is_active: bool = false
var _active_balloon: Node = null


func _ready() -> void:
	add_to_group("dialogue")
	DialogueManager.dialogue_ended.connect(func(_res: DialogueResource):
		is_active = false
		_active_balloon = null)
	# 气球是当前场景子节点，对白中切场景会连它一起销毁、dialogue_ended 不会触发 → 主动解锁防卡死
	get_tree().scene_changed.connect(func():
		is_active = false
		_active_balloon = null)
	DialogueManager.set_default_balloon("res://ui/balloon/balloon.tscn")


## 直接打断当前正在播放的对白（用于教程教学区域切换）。
func interrupt() -> void:
	if is_instance_valid(_active_balloon):
		_active_balloon.queue_free()
	_active_balloon = null
	is_active = false


## 弹一段 DM 对白。file 是 .dialogue 资源路径，cue 是 ~ 标题。
## 上一段对白未结束时默认不双开；教学提示区请用 PromptTrigger + TutorialPrompt（5s 定时），需要时用 interrupt() 打断。
func show_cue(dialogue_file: String, cue: String) -> void:
	if cue.is_empty():
		push_warning("DialogueBridge: 空 cue，忽略")
		return
	if is_active:
		return  # 防双开（DM 一 cue 一气球实例）
	is_active = true
	var res: DialogueResource = load(dialogue_file)
	if res == null:
		push_warning("DialogueBridge: 无法加载对白文件 %s" % dialogue_file)
		is_active = false
		return
	_active_balloon = DialogueManager.show_dialogue_balloon(res, cue)
	if _active_balloon and _active_balloon.has_method("set_input_grace"):
		_active_balloon.set_input_grace(0.3)

