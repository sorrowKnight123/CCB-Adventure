extends Node2D
## 88 攻击的**分离命中特效**：一道猩红 slash 在命中帧炸开、叠加发光、然后淡出。
##
## 作者 2026-09-22 定的方案。为什么不烘焙进帧（实测依据）：
##   帧里的拖尾**线宽只有 1~2 屏幕像素**、颜色暗（R 92~143），而音乐厅背景是暖棕（R 115）
##   —— **拖尾比背景还暗**。这三条在已定稿的帧里改不了，而且帧**没法叠加发光**。
##   分离节点能做帧做不到的三件事：`BLEND_MODE_ADD` 叠加发光、亮度/大小/时长全可调、
##   不占角色帧的画布（现在共享画布已经 639 宽）。
##
## 形态照 `BossShockwave`（苔藓 Boss 的冲击波，本项目"分离特效"的既有先例），但更轻：
## 只一个 Sprite2D + 一个 Tween，没有判定、没有碰撞。
##
## 帧里的拖尾**保留**当"路径"，这个节点负责"打击感"，两者叠加。

## 出场时长（秒）。命中帧那一刻 spawn，0.2 秒内放大 + 淡出。
@export var 时长: float = 0.2
@export var 初始缩放: float = 0.6
@export var 结束缩放: float = 1.15
## 叠加亮度：>1 时叠得发白，是这个特效"亮"的关键
@export var 亮度: float = 1.6

var _精灵: Sprite2D = null


func _ready() -> void:
	_精灵 = Sprite2D.new()
	add_child(_精灵)
	# **叠加发光**：这是帧做不到、而"太淡"最需要的一条
	var 材质 := CanvasItemMaterial.new()
	材质.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_精灵.material = 材质


## `朝向` = +1 朝右 / -1 朝左（跟着 Boss 的 facing 走，贴图本身是朝右画的，会自动镜像）
## `垂直翻转` / `旋转` = 给"朝向之外还想微调"的场合（爪击那版是弧形，需要单独摆角度）
## `水平翻转` = **在自动镜像之上再翻一次**（XOR）—— 用来纠正贴图本身的左右画反
func setup(贴图: Texture2D, 世界位置: Vector2, 朝向: int, 缩放: float = 1.0,
		时长覆盖: float = -1.0, 垂直翻转: bool = false, 旋转: float = 0.0,
		水平翻转: bool = false) -> void:
	if _精灵 == null:
		_ready()
	_精灵.texture = 贴图
	global_position = 世界位置
	_精灵.flip_h = (朝向 < 0) != 水平翻转
	_精灵.flip_v = 垂直翻转
	_精灵.rotation = 旋转
	_精灵.modulate = Color(亮度, 亮度, 亮度, 1.0)
	var 倍 := 缩放
	_精灵.scale = Vector2(初始缩放 * 倍, 初始缩放 * 倍)
	_精灵.rotation = 0.0
	var 秒 := 时长 if 时长覆盖 <= 0.0 else 时长覆盖
	# 放大与淡出**并行**；淡出用 QUAD/EASE_OUT，一上来亮、收尾快
	var 补 := create_tween()
	补.set_parallel(true)
	补.tween_property(_精灵, "scale", Vector2(结束缩放 * 倍, 结束缩放 * 倍), 秒) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	补.tween_property(_精灵, "modulate:a", 0.0, 秒) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	补.chain().tween_callback(queue_free)
