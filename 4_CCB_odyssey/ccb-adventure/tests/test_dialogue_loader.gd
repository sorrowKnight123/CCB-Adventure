extends Node
## Dialogue Manager 回归测试（Day 12 引入后扩展）：
## 1) 冒烟：dialogues/demo.dialogue 解析 / 数据结构 / 跟随跳转。
## 2) 全量 cue 遍历：dialogues/game.dialogue + clues.dialogue 的每个 ~ cue 都能解析、
##    角色=77、文本非空、cue 名未用保留字 end（迁移后对白内容都在 .dialogue，这里是防错网）。
## 注意：get_next_dialogue_line / get_line 是协程，必须 await。
## 场景模式运行（--script 不加载 autoload，DialogueManager 是 autoload）。

const GAME_CUES: Array[String] = [
	"tut_move", "tut_jump", "tut_dash", "tut_combat", "tut_inventory",
	"dt_forest", "dt_secret", "dt_clue1", "dt_boss",
	"pickup_doublejump", "pickup_magicdash", "pickup_magicclimb", "pickup_magicflight",
]
const CLUE_CUES: Array[String] = [
	"clue_village_note", "clue_forest_secret", "clue_school_high",
	"diary_village", "diary_forest", "letter_musichall",
]

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	# ---- 1) demo.dialogue 冒烟 ----
	var res: DialogueResource = load("res://dialogues/demo.dialogue")
	_check(res != null, "demo.dialogue 能被解析加载（.dialogue 导入插件生效）")
	if res != null:
		var line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "start")
		_check(line != null, "demo: 从 cue=start 取到第一句")
		if line:
			_check(line.character == "骑士77", "demo: 角色名解析=%s" % line.character)
			_check(line.text.begins_with("你好"), "demo: 台词解析=%s" % line.text)
			_check(line.responses.size() >= 2, "demo: 第 1 句带 %d 个选项" % line.responses.size())
			# 跟随第 1 个选项的跳转目标
			var r: DialogueResponse = line.responses[0]
			var next_line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, r.next_id)
			_check(next_line != null and next_line.character == "骑士77", "demo: 选项跳转到达分支句")
		var outro: DialogueLine = await DialogueManager.get_next_dialogue_line(res, "outro")
		_check(outro != null and outro.character == "王老师", "demo: cue=outro 可直达")

	# ---- 2) 默认对白气球能加载并实例化（DialogueBridge 默认用它）----
	var balloon_scene: PackedScene = load("res://ui/balloon/balloon.tscn")
	_check(balloon_scene != null, "ui/balloon/balloon.tscn 可加载")
	var balloon_inst: Node = balloon_scene.instantiate() if balloon_scene else null
	_check(balloon_inst != null and balloon_inst is CanvasLayer, "ui/balloon/balloon.tscn 可实例化（场景图引用完整）")
	if balloon_inst:
		balloon_inst.free()

	# ---- 3) 全量 cue 遍历 ----
	await _check_cues("res://dialogues/game.dialogue", GAME_CUES, "游戏对白")
	await _check_cues("res://dialogues/clues.dialogue", CLUE_CUES, "线索对白")

	_finish()


func _check_cues(path: String, cues: Array[String], label: String) -> void:
	var res: DialogueResource = load(path)
	_check(res != null, "%s: %s 能解析加载" % [label, path])
	if res == null:
		return
	_check(res.cues.size() >= cues.size(), "%s: 共 %d 个 cue（期望 ≥%d）" % [label, res.cues.size(), cues.size()])
	for cue in cues:
		_check(cue != "end", "%s: cue 名未用保留字 end" % label)
		var line: DialogueLine = await DialogueManager.get_next_dialogue_line(res, cue)
		_check(line != null, "%s: cue=%s 可解析" % [label, cue])
		if line:
			_check(line.character == "77", "%s: cue=%s 角色=%s" % [label, cue, line.character])
			_check(not line.text.is_empty(), "%s: cue=%s 文本非空" % [label, cue])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PASS] %s" % what)
	else:
		_failures += 1
		print("[FAIL] %s" % what)


func _finish() -> void:
	print("Dialogue smoke: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
