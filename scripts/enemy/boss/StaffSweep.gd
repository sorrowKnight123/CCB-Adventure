extends Node2D
## 88 的二号招：**五线谱横扫** —— 5 条线绑成一个整体，从右往左推，中间留一道"缝"。
##
## 规则（作者定的"不要完全随机安全逻辑"）：
##   · **缝的位置从 5 个固定模板里取**，不随机；随机的只有音符点缀
##   · **碰到扣血，但线不会消失**；每人每次只判一次（抄 `BossShockwave` 的 `_hit_player` 守卫）
##   · 不需要贴图：5 条线用 `_draw()` 程序化画，音符点缀可选
##
## 判定形状的算法：给一个**外框**和一个**安全区**，把"外框挖掉安全区"分解成 2~4 个矩形。
## 于是 5 个模板只是 5 组 (外框, 安全区)，加模板不用改逻辑。

@export var 线数: int = 5
@export var 线色: Color = Color(0.89, 0.11, 0.24, 0.92)
@export var 线宽: float = 3.0
@export var 行距: float = 18.0
@export var 行进速度: float = 260.0
@export var 伤害: int = 1
## 音符点缀的数量（纯视觉）
@export var 音符数: int = 7
@export var 调试显示范围: bool = false

## 每个模板 = { 说明, 外框, 安全区 }，坐标是**本节点局部**（y 向上为负）
const 模板表: Array[Dictionary] = [
	{"说明": "贴地·中间留缝",
	 "外框": Rect2(-210, -60, 420, 96), "安全区": Rect2(-46, -60, 92, 96)},
	{"说明": "中位·左侧留缝",
	 "外框": Rect2(-210, -150, 420, 96), "安全区": Rect2(-160, -150, 92, 96)},
	{"说明": "高位·右侧留缝（逼玩家跳）",
	 "外框": Rect2(-210, -240, 420, 96), "安全区": Rect2(68, -240, 92, 96)},
	{"说明": "上下夹击·中间留横缝",
	 "外框": Rect2(-210, -300, 420, 280), "安全区": Rect2(-210, -190, 420, 110)},
	{"说明": "全屏·一条窄竖缝",
	 "外框": Rect2(-210, -430, 420, 470), "安全区": Rect2(-40, -430, 80, 470)},
]

var _已命中: bool = false
var _存活: bool = false
var _左界: float = 0.0
var _模板: int = 0
var _外框: Rect2 = Rect2()
var _安全区: Rect2 = Rect2()

@onready var 判定: Area2D = $判定


## `锚点y` = 88 所在的地面高度（世界坐标）。**必须由调用方传进来** ——
## 以前这里读的是 `global_position.y`，而刚 `instantiate()` 出来的节点还没进场景树，
## 那个值是 **0**，于是五线谱生成在世界 (1620, 0)：在画面上方约 2900px 处横扫，
## 整个生命周期都在视野外，既看不见也打不到玩家。
## 模板坐标本来就是以"脚下 y = 0"为基准设计的（外框 y 从 -60 到 -430）。
func setup(速度: float, 招伤: int, 模板序号: int, 活动左: float, 活动右: float,
		锚点y: float) -> void:
	行进速度 = 速度
	伤害 = 招伤
	_模板 = clampi(模板序号, 0, 模板表.size() - 1)
	_左界 = 活动左
	var 条 := 模板表[_模板]
	_外框 = 条["外框"]
	_安全区 = 条["安全区"]
	# 从场地右侧推入，纵向贴在 88 所在的地面高度上
	global_position = Vector2(活动右 + 220.0, 锚点y)
	_重建判定()
	_存活 = true
	queue_redraw()
	print("[五线谱] 模板 %d：%s ｜ 速度 %d ｜ 生成于 (%.0f, %.0f) ｜ 缝 %s"
		% [_模板, 条["说明"], int(行进速度), global_position.x, global_position.y,
			str(_安全区)])


func _ready() -> void:
	add_to_group("boss_hazard")
	if 判定 != null:
		判定.body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if not _存活:
		return
	var dlg := get_tree().get_first_node_in_group("dialogue")
	if dlg != null and dlg.is_active:
		return
	position.x -= 行进速度 * delta
	# 走过活动左界再多一点就自己消失（"线继续走出画面自然消失"）
	if position.x < _左界 - 260.0:
		_存活 = false
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# 命中一次后不再判（线继续飞）—— 与 BossShockwave 同一套语义
	if _已命中 or not body.is_in_group("player"):
		return
	_已命中 = true
	body.take_damage(伤害, global_position)


# ──────────────────────────── 判定形状 ────────────────────────────


## 把"外框挖掉安全区"分解成 2~4 个矩形，逐个加 CollisionShape2D
func _重建判定() -> void:
	if 判定 == null:
		return
	for c in 判定.get_children():
		c.queue_free()
	for r in _分解矩形(_外框, _安全区):
		var 形 := CollisionShape2D.new()
		var 矩 := RectangleShape2D.new()
		矩.size = r.size
		形.shape = 矩
		形.position = r.position + r.size * 0.5
		判定.add_child(形)


## 外框 减 安全区 → 矩形列表（安全区若整条贯通，就是 2 块；否则 4 块）
func _分解矩形(外框: Rect2, 安全: Rect2) -> Array[Rect2]:
	var 出: Array[Rect2] = []
	var 交 := 外框.intersection(安全)
	if 交.size.x <= 0.0 or 交.size.y <= 0.0:
		出.append(外框)                       # 安全区在外框之外：整块都是危险
		return 出
	# 左 / 右
	if 交.position.x > 外框.position.x:
		出.append(Rect2(外框.position, Vector2(交.position.x - 外框.position.x, 外框.size.y)))
	if 交.end.x < 外框.end.x:
		出.append(Rect2(Vector2(交.end.x, 外框.position.y),
			Vector2(外框.end.x - 交.end.x, 外框.size.y)))
	# 上 / 下（只在安全区没贯通整高时才有）
	if 交.position.y > 外框.position.y:
		出.append(Rect2(外框.position, Vector2(外框.size.x, 交.position.y - 外框.position.y)))
	if 交.end.y < 外框.end.y:
		出.append(Rect2(Vector2(外框.position.x, 交.end.y),
			Vector2(外框.size.x, 外框.end.y - 交.end.y)))
	return 出


# ──────────────────────────── 视觉（程序化） ────────────────────────────


func _draw() -> void:
	if _外框.size == Vector2.ZERO:
		return
	# 5 条平行线，遇到安全区断开 —— 让"缝"一眼看得见
	var 外框左 := _外框.position.x
	var 外框右 := _外框.end.x
	var 中高 := (_外框.position.y + _外框.end.y) * 0.5
	var 起 := 中高 - 行距 * (线数 - 1) * 0.5
	for i in 线数:
		var y := 起 + 行距 * i
		# 在这条线的 y 上，安全区是否贯通？贯通则断开
		var 段列表 := _该行的可见段(Rect2(外框左, y, 外框右 - 外框左, 1.0))
		for 段 in 段列表:
			draw_line(Vector2(段.position.x, y), Vector2(段.end.x, y), 线色, 线宽)
	# 音符点缀（纯视觉，位置由模板固定，不参与判定）
	var rng := RandomNumberGenerator.new()
	rng.seed = 88 * 100 + _模板
	for _i in 音符数:
		var x := rng.randf_range(外框左 + 10.0, 外框右 - 10.0)
		var y := 起 + 行距 * rng.randi_range(0, 线数 - 1)
		if not _安全区.has_point(Vector2(x, y)):
			draw_circle(Vector2(x, y + 6.0), 5.0, Color(1, 1, 1, 0.9))
			draw_line(Vector2(x + 4.0, y + 6.0), Vector2(x + 4.0, y - 16.0), Color(1, 1, 1, 0.9), 2.0)
	if 调试显示范围:
		draw_rect(_外框, Color(1, 0.3, 0.3, 0.5), false, 2.0)
		draw_rect(_安全区, Color(0.3, 1.0, 0.4, 0.8), false, 2.0)


## 某一条水平线在安全区内要断开，返回它可见的区段
func _该行的可见段(行: Rect2) -> Array[Rect2]:
	var 交 := 行.intersection(_安全区)
	if 交.size.x <= 0.0:
		return [行] as Array[Rect2]
	var 出: Array[Rect2] = []
	if 交.position.x > 行.position.x:
		出.append(Rect2(行.position, Vector2(交.position.x - 行.position.x, 行.size.y)))
	if 交.end.x < 行.end.x:
		出.append(Rect2(Vector2(交.end.x, 行.position.y), Vector2(行.end.x - 交.end.x, 行.size.y)))
	return 出
