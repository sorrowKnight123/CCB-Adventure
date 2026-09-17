@tool
extends StaticBody2D
## 音乐小游戏的「琴键」史莱姆。
##
## 它不移动、不受重力、没有碰撞伤害、不会死亡，只做三件事：
##   1. 按 `音符` 把自己染成对应颜色（hue_shift shader）；
##   2. 被玩家近战命中时发 `被击中` 信号（顺序判定由 MusicGame.gd 负责）；
##   3. 播放受击表现（闪白 + 撑开压扁 → 回弹）。
##
## ── 为什么是 StaticBody2D ──
## 玩家近战走 `melee_hitbox.get_overlapping_bodies()`，只认 PhysicsBody2D。
## StaticBody2D + `collision_layer = 4`（enemy 层）能被找到，但完全不需要物理处理
## → 零重力、零 AI、绝对静止。玩家 collision_mask 不含 layer 3，所以能穿过去、不挡路。
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


func 设为已完成(done: bool) -> void:
	## 进度反馈：已按对的变暗（用户明确要求不做"下一只"提示）。
	_sprite.modulate = Color(0.42, 0.44, 0.5, 1.0) if done else Color.WHITE


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
