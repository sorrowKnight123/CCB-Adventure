class_name AbilityNote
extends "res://scripts/game/NotePickup.gd"
## 小游戏通关时额外喷出的「能力音符」：2 倍大小、彩虹变色、白色光晕、像谱台一样闪光。
## 碰到玩家 -> 发 `能力` 对应的能力（过场动画由 `Player.grant_*()` 内部自己播）-> 消失。
##
## ── 为什么继承 NotePickup ──
## 抛落物理（`setup_launch`）、落地浮动、`PickupArea` 检测父脚本都写好了，
## 这里只改「长什么样」和「捡到以后做什么」。
## ⚠️ 父脚本没有 class_name，只能按路径 extends。
##
## ── 外观 ──
## `Visual` 挂 `rainbow_note.gdshader`，`_process` 每帧推进 target_hue（彩虹循环）
## 与 sweep（谱台同款扫光）。⚠️ 材质必须每个实例一份，共用一份会让场上所有音符同步闪。
## `Halo` 是白色径向光晕（`art/icons/glow_halo.tres`），靠 `modulate.a` 呼吸。
##
## ── 光晕贴图为什么自己新做一张 ──
## 关卡里现成的 `new_gradient_texture_2d.tres` 每个色标 alpha 都是 1（画出来是不透明圆盘，
## 不是光晕），而且关卡的 MossGlow 在共用它，改它会连带改环境光。

const RAINBOW_SHADER: Shader = preload("res://shaders/rainbow_note.gdshader")

## 能力 id：对应 `Player` 上的 `grant_<id>()`（double_jump / magic_dash / magic_climb / magic_flight）。
@export var 能力: String = "double_jump"
## 彩虹转一圈的秒数。
@export var 彩虹周期: float = 2.4
## 扫光带扫过一趟的秒数（跟谱台的「流光周期」一个观感）。
@export var 流光周期: float = 2.4
## 光晕呼吸的明暗范围与周期。
@export var 光晕最暗: float = 0.45
@export var 光晕最亮: float = 0.85
@export var 光晕呼吸周期: float = 1.8

var _material: ShaderMaterial
var _hue_phase: float = 0.0
var _sweep: float = 0.0
var _halo_time: float = 0.0
var _halo: Sprite2D
var _halo_base_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	super()                                  # 连 PickupArea 信号 + 记住 Visual 的基准位置
	var material := ShaderMaterial.new()
	material.shader = RAINBOW_SHADER
	visual.material = material
	_material = material
	_halo = get_node_or_null("Halo") as Sprite2D
	if _halo != null:
		_halo_base_position = _halo.position
		_halo_time = 光晕呼吸周期 * 0.37      # 错开相位，场上多个时光晕不同步


func _process(delta: float) -> void:
	if _material != null:
		_hue_phase = fmod(_hue_phase + delta / maxf(彩虹周期, 0.05), 1.0)
		_sweep = fmod(_sweep + delta / maxf(流光周期, 0.05), 1.0)
		_material.set_shader_parameter("target_hue", _hue_phase)
		_material.set_shader_parameter("sweep", _sweep)
	if _halo == null:
		return
	_halo_time += delta
	var breath := 0.5 + 0.5 * sin(_halo_time * TAU / maxf(光晕呼吸周期, 0.05))
	_halo.modulate.a = lerpf(光晕最暗, 光晕最亮, breath)
	# 跟着 Visual 一起浮动：父脚本待机时上下浮动的是 Visual，光晕是另一个兄弟节点
	_halo.position = _halo_base_position + (visual.position - _visual_base_position)


func _on_body_entered(body: Node2D) -> void:
	## 覆盖父类（父类的实现是「加音符 + 消失」）：这里发能力。
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	_发能力(body)
	queue_free()


func 是能力奖励() -> bool:
	## 给自检用的标记：本类同时具备父类的 `setup_launch` / `_on_body_entered`，
	## 测试靠这个方法把能力音符从「通关奖励撒了一地」里排除出去。
	return true


func _发能力(body: Node2D) -> void:
	var method := "grant_" + 能力
	if 能力 == "" or not body.has_method(method):
		# 兜底：真发不出去也别让玩家白捡，按普通音符算
		push_warning("AbilityNote：玩家身上没有 %s()，退化成 +%d 绕梁余音" % [method, amount])
		GameState.add_notes(amount)
		GameState.save_game()
		if 显示提示:
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null and hud.has_method("show_note_toast"):
				hud.show_note_toast(amount)
		return
	body.call(method)                         # 过场动画由 Player.grant_* 内部播
	GameState.save_game()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("refresh_abilities"):
		hud.refresh_abilities()
