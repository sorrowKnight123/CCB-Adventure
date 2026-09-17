@tool
extends CharacterBody2D
## 音乐小游戏的「琴键」史莱姆。
##
## 它不移动、不受重力、没有碰撞伤害、不会死亡，只做三件事：
##   1. 按 `音符` 把自己染成对应颜色（hue_shift shader）；
##   2. 被玩家近战命中时发 `被击中` 信号（顺序判定由 MusicGame.gd 负责）；
##   3. 播放受击表现（闪白 + 撑开压扁 → 回弹）。
##
## ── 为什么是 CharacterBody2D（而不是 StaticBody2D）──
## 曾经用 StaticBody2D（想着"零物理开销、绝对静止"），结果**玩家挥砍完全打不到它**：
## 实测玩家近战命中盒那个 Area2D 能检测到 layer 3 上的 CharacterBody2D，却检测不到
## 同样在 layer 3、同一位置的 StaticBody2D（而临时新建的 Area2D 反而能检测到它，
## 用 direct_space_state 查询也能查到 —— 所以这是个很难察觉的引擎坑）。
## 换成 CharacterBody2D 后：本脚本**不写 `_physics_process`、也不调 `move_and_slide()`**，
## 所以它依然零重力、绝对静止，与 StaticBody2D 的实际效果一致，代价可忽略。
##
## ── contact_damage 恒为 0 ──
## 玩家 Hurtbox（mask = layer 3）会检测到它并调 `take_damage(0)`。
## 靠 `Player.take_damage()` 开头的 `amount <= 0` 早退，保证玩家不白闪 / 不进无敌 / 不被打飞。

signal 被击中(from_pos: Vector2)

## 与 MusicNotes.NOTES 的顺序保持一致（下拉框在 Inspector 里选，避免手打错字）。
@export_enum("C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5") var 音符: String = "C4"
@export var 受击挤压幅度: float = 0.32
@export var 闪白时长: float = 0.09
@export var 回弹时长: float = 0.18

## 玩家 Hurtbox 会读这个属性；恒为 0 = 无碰撞伤害（配合 Player.take_damage 的 ≤0 早退）。
var contact_damage: int = 0

var _base_scale: Vector2 = Vector2.ONE
var _tween: Tween = null

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	_base_scale = _sprite.scale
	if Engine.is_editor_hint():
		# 编辑器里不改材质：@tool 节点在 _ready 里写属性会把场景标记成已修改。
		# 每只史莱姆是什么音，看 MusicGame 的槽位标注（会按该音的颜色画出来）。
		return
	_apply_note_color()
	add_to_group("enemies")   # 玩家近战靠这个组筛选
	_sprite.play(&"idle")


func get_note() -> String:
	return 音符


func take_damage(_amount: int, from_pos: Vector2, _from_magic := false) -> void:
	## 签名与 `Player._on_hit()` 的 `enemy.take_damage(damage, global_position)` 兼容。
	## 这里没有 HP：不死亡、不掉落、不给音乐灵感，只上报并做受击表现。
	if Engine.is_editor_hint():
		return
	被击中.emit(from_pos)
	play_hurt()


func play_hurt() -> void:
	## 闪白 + 横向撑开纵向压扁 → 回弹。连续命中会打断上一段，不会叠加变形。
	if _tween and _tween.is_valid():
		_tween.kill()
	_sprite.self_modulate = Color(2.6, 2.6, 2.6, 1.0)
	var squash := Vector2(
		_base_scale.x * (1.0 + 受击挤压幅度),
		_base_scale.y * (1.0 - 受击挤压幅度))
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_sprite, "self_modulate", Color.WHITE, 闪白时长)
	_tween.tween_property(_sprite, "scale", squash, 闪白时长 * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_property(_sprite, "scale", _base_scale, 回弹时长) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func 设为已完成() -> void:
	## 通关后整排史莱姆变暗（**不清除、不隐藏**）—— 表示这一局已经拿下。
	## ⚠️ 只在通关时调用：同一只史莱姆可能在序列里被弹响多次，
	##    "打一次就变暗"会让玩家以为它不能再用（用户明确要求删掉那个机制）。
	_sprite.modulate = Color(0.42, 0.44, 0.5, 1.0)


func _apply_note_color() -> void:
	var material := _sprite.material as ShaderMaterial
	if material == null:
		push_warning("MusicSlime 的 Sprite 上没有 ShaderMaterial，染色被跳过（音符=%s）" % 音符)
		return
	# 每只独立一份材质：共享材质会让所有史莱姆用同一个色相。
	material = material.duplicate()
	_sprite.material = material
	var color := MusicNotes.get_color(音符)
	material.set_shader_parameter("target_hue", color.h)
	material.set_shader_parameter("target_saturation", color.s)
	material.set_shader_parameter("value_scale", MusicNotes.get_value_scale(音符))
