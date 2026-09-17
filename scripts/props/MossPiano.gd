extends Node2D
## 隐藏房间里的陈旧三角钢琴：按 W 反复查看；
## 看到第 `发现次数` 次时，会在琴架上发现一张羊皮纸（「狂喜之诗 其一」）。
##
## 交互模式照 `scripts/npc/BlueWizard.gd`：Area2D 进出范围 + `_process` 读 interact 动作 + `DialogueBridge.show_cue`。
## 对话用**旁白**写法（`game.dialogue` 里那两行不带 `角色名:` 前缀）。
##
## ⚠️ 计数只在**本次进场景内**有效（没给 GameState 加新存档字段）；
##    但奖励一旦拿到就是永久的 —— 靠 `GameState.collect()` 记在存档里，之后再交互只会播普通旁白。

const DIALOGUE_FILE: String = "res://dialogues/game.dialogue"
const 普通旁白: String = "piano_examine"
const 发现旁白: String = "piano_found"
const 发现次数: int = 5
const 收集品ID: String = "ecstasy_1"
const ABILITY_CUTSCENE: PackedScene = preload("res://ui/AbilityCutscene.tscn")

## 羊皮纸的图标（过场动画里显示）。留空则不显示图标（过场本身照常播）。
@export var 羊皮纸图标: Texture2D
@export var 物品名: String = "狂喜之诗 其一"
@export var 物品说明: String = "写满癫狂音流的羊皮纸残页。凑齐四张，也许能拼出什么。"
@export var 交互提示: NodePath = NodePath("Bubble")
@export var 交互区域: NodePath = NodePath("InteractArea")

var _player_in_range: bool = false
var _查看次数: int = 0
var _已获得: bool = false
var _发现旁白已播: bool = false

@onready var _bubble: InteractBubble = get_node_or_null(交互提示) as InteractBubble
@onready var _area: Area2D = get_node_or_null(交互区域) as Area2D


func _ready() -> void:
	_已获得 = GameState.has_collectible(收集品ID)
	if _area != null:
		_area.body_entered.connect(_on_area_body_entered)
		_area.body_exited.connect(_on_area_body_exited)
	DialogueManager.passed_cue.connect(_on_dialogue_passed_cue)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func _process(_delta: float) -> void:
	if _bubble != null:
		# 对话进行中不显示提示（免得和对话框叠在一起）
		if _player_in_range and not DialogueBridge.is_active:
			_bubble.显示()
		else:
			_bubble.隐藏()
	if not _player_in_range:
		return
	if DialogueBridge.is_active:
		return
	if Input.is_action_just_pressed("interact"):
		_查看钢琴()


func _on_area_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true


func _on_area_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false


func _查看钢琴() -> void:
	if _已获得:
		DialogueBridge.show_cue(DIALOGUE_FILE, 普通旁白)
		return
	_查看次数 += 1
	if _查看次数 < 发现次数:
		DialogueBridge.show_cue(DIALOGUE_FILE, 普通旁白)
	else:
		DialogueBridge.show_cue(DIALOGUE_FILE, 发现旁白)


func _on_dialogue_passed_cue(cue: String) -> void:
	## 只认自己那句 —— 免得别的对话结束也触发结算
	if cue == 发现旁白:
		_发现旁白已播 = true


func _on_dialogue_ended(_resource: Resource) -> void:
	if not _发现旁白已播:
		return
	_发现旁白已播 = false
	_结算获得羊皮纸()


func _结算获得羊皮纸() -> void:
	_已获得 = true
	GameState.collect(收集品ID)
	GameState.save_game()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_collect_count"):
		hud.set_collect_count(GameState.collected_ids.size(), GameState.COLLECT_TOTAL)
	_play_cutscene()


func _play_cutscene() -> void:
	## 复用能力获取过场（它完全参数化，不依赖 Player）。
	## ⚠️ 它内部会 `get_tree().paused = true`，所以已经暂停时不要调用（会误解除原来的暂停）。
	if get_tree().paused:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var cutscene: Node = ABILITY_CUTSCENE.instantiate()
	scene.add_child(cutscene)
	cutscene.show_ability(羊皮纸图标, 物品名, 物品说明, "获得物品")
