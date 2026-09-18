extends Sprite2D
## 音乐厅的「弹跳鼓」——跳跳乐的核心件（弹跳植物在音乐厅的换皮版）。
## 玩家从上方踩到 → 鼓面压扁回弹 + 玩家被弹起 + 一声鼓响。
##
## ── 与 `scripts/props/JumpPlant.gd` 的关系 ──
## 行为、数值、门禁逻辑全部照搬（跳跃强度 700、触发冷却 0.4、`需要通关ID` 门禁同款），
## 只有三处不同，所以另开了这个脚本而不是改那个：
##   ① 它是**静态贴图**（一张鼓），没有帧动画 → 用 tween 把精灵压扁再回弹来表现"鼓面震动"
##      （JumpPlant 是 AnimatedSprite2D + SpriteFrames，播放 jump 序列）
##   ② 音效换成**鼓声**（`音效列表` 可导出，默认用 `drum_kick.wav`）
##   ③ **不飘彩色音符**：音乐厅里鼓很多，每个都飘音符会糊成一片
##
## ⚠️ 鼓声**必须只有一个音**（作者定的"鼓声全用 kick"）。
##    这里曾经踩过两次同一个坑：鼓实例若带一个**空的** `音效列表` 覆盖，
##    就会退回"多个占位音里随机取一个"，听起来就是鼓声随机。
##    所以留空时的兜底**只能是一个音**，绝不能是多个 —— 见 `默认鼓声`。

@export var 跳跃强度: float = 700.0          # 玩家弹跳初速度（与 JumpPlant 一致）
@export var 触发冷却: float = 0.4            # 防连续触发
@export var 压扁幅度: float = 0.32           # 鼓面压扁比例（0.32 = 压掉 32% 高度）
@export var 压扁时长: float = 0.10           # 压扁用时
@export var 回弹时长: float = 0.22           # 回弹用时
## 非空时 → 这个鼓是「门禁」：该 ID 没达标之前隐藏且踩不到（与 JumpPlant 同款语义）。
@export var 需要通关ID: String = ""
## 鼓声池。**留空只会退回 `默认鼓声` 这一个音**（不是随机）——
## 关卡里的鼓实例如果带一个空覆盖，随机取音就会复活，所以兜底必须是单音。
@export var 音效列表: Array[AudioStream] = []

const 默认鼓声: AudioStream = preload("res://audio/props/music_hall/drum_kick.wav")

var _cooldown: float = 0.0
var _bouncing: bool = false
var _locked: bool = false

@onready var _audio: AudioStreamPlayer = $DrumAudio

var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_base_scale = scale
	$Trigger.body_entered.connect(_on_trigger_body_entered)
	if 需要通关ID != "" and not _门禁已开():
		_set_locked(true)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	# 与 JumpPlant 一样用轮询而不是信号连线：不跟某个具体小游戏/Boss 节点耦合
	if _locked and _门禁已开():
		解锁()


func _门禁已开() -> bool:
	return GameState.has_trigger(需要通关ID) or GameState.is_boss_defeated(需要通关ID)


func _set_locked(locked: bool) -> void:
	_locked = locked
	visible = not locked
	# ⚠️ 只隐藏不够：Trigger 是 Area2D，不关 monitoring 的话踩到"看不见的鼓"照样会被弹飞
	$Trigger.set_deferred("monitoring", not locked)
	$Trigger.set_deferred("monitorable", not locked)


func 解锁() -> void:
	if not _locked:
		return
	_set_locked(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", _base_scale, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _locked or _cooldown > 0.0 or _bouncing:
		return
	if not body.is_in_group("player"):
		return
	if body.velocity.y <= 0.0:      # 只响应从上方踩下来；从下面顶上来不触发
		return
	_打击(body)


func _打击(player: Node2D) -> void:
	_cooldown = 触发冷却
	_bouncing = true
	# 1) 鼓面压扁 → 回弹（代替帧动画）
	var tween := create_tween()
	tween.tween_property(self, "scale",
		Vector2(_base_scale.x * (1.0 + 压扁幅度 * 0.5), _base_scale.y * (1.0 - 压扁幅度)), 压扁时长
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _base_scale, 回弹时长
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 2) 玩家弹跳 + 刷新空中行动（可再冲刺 + 二段跳次数重置）
	player.velocity.y = -跳跃强度
	if player.has_method("reset_air_actions"):
		player.reset_air_actions()
	# 3) 鼓声
	var 池: Array = 音效列表 if not 音效列表.is_empty() else [默认鼓声]
	_audio.stream = 池[randi() % 池.size()]
	_audio.play()
	# 4) 动画期间不接受重复触发
	await get_tree().create_timer(压扁时长 + 回弹时长).timeout
	_bouncing = false
