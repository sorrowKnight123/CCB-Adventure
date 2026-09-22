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
## 音符点缀的数量（纯视觉）。**2026-09-22 起贴图自带音符，这个只在没贴图时兜底。**
@export var 音符数: int = 7
## 谱贴图（作者 2026-09-22 定：五线谱整条 + 音符 + 谱号 + 左右血溅，是一张图）。
## 一图 2 条谱，共 4 张（2 高音谱号 + 2 低音谱号），实战随机取一张。
## 尺寸 420×72 —— 与旧的程序化谱（5 线 × 行距 18 = 72）一致。
@export var 谱贴图集: Array[Texture2D] = []
## 贴图左端**谱号**占的宽度比例。除最左那一段外，其余段从谱号右侧起裁，
## 否则"缝"把谱切开后每段都会顶着一个谱号。
@export_range(0.0, 0.4, 0.01) var 谱头宽比例: float = 0.13
## 谱台同款**扫光**（2026-09-22 作者要求："加一个类似 musicgame 谱台的同款周期闪烁效果，
## 更醒目，提醒玩家躲避"）。用现成的 `shaders/sweep_shine.gdshader`：一条斜向高光带
## 按 `sweep` 0→1 扫过，加法叠加在谱面上。
## ⚠️ 材质必须**每个实例一份** —— 共用一份会让场上两条谱同步闪（`AbilityNote` 里记过这个坑）。
## 作者 2026-09-22："闪烁的间隔时间加长一倍，不要太频繁" —— 谱台原本是 2.4 秒一趟，
## 这里用 **4.8 秒**。
@export var 流光周期: float = 4.8
@export_range(0.0, 3.0, 0.05) var 扫光强度: float = 1.15
@export var 调试显示范围: bool = false

const 扫光着色器 := preload("res://shaders/sweep_shine.gdshader")

## 每个模板 = { 说明, 外框, 安全区 }，坐标是**本节点局部**（y 向上为负）。
##
## ⚠️ **2026-09-22 大改：取消 x 方向的"缝"**。作者原话：
##   "我从头到尾就没有要求安全区，就是一条完整的谱，上面每一点碰到都有伤害，
##    玩家只能跳跃等方式改变 y 坐标躲避，**x 坐标是没有任何缝隙的**。"
##   之前那 5 个模板的"缝"是**我按设计稿里那句"5 个高度模板（缝的位置固定）"自己
##   理解成 x 方向留空**加进去的 —— 加错了方向。
##
## 现在的规则：
##   · 谱永远是**完整不断的一条**（宽 420 = 贴图原宽，x 方向**没有任何缺口**）
##   · 5 个模板只差在 **y（高度）**：谱在哪一层、要不要上下夹击、留多高的缝
##   · 玩家靠**跳 / 蹲 / 改变 y** 躲，横向怎么跑都没用
##   · `安全区` 是**横向贯通的一条带**（挖掉它 = 上下两块），所以判定天然没有 x 缺口
const 模板表: Array[Dictionary] = [
	# ① 贴地：谱贴着地面 → 必须跳过去
	{"说明": "贴地（跳过去）",
	 "外框": Rect2(-210, -72, 420, 72), "安全区": Rect2(0, -99999, 0, 0)},
	# ② 中位：谱在腰胸高度 → 蹲下或跳过去
	{"说明": "中位（蹲下或跳）",
	 "外框": Rect2(-210, -170, 420, 72), "安全区": Rect2(0, -99999, 0, 0)},
	# ③ 高位：谱在头顶高度 → 贴地站着就安全
	{"说明": "高位（站着别跳）",
	 "外框": Rect2(-210, -270, 420, 72), "安全区": Rect2(0, -99999, 0, 0)},
	# ④ 上下夹击：上下各一条，中间 148 高是安全带 → 站在中间
	{"说明": "上下夹击（站中间）",
	 "外框": Rect2(-210, -300, 420, 292), "安全区": Rect2(-210, -228, 420, 148)},
	# ⑤ 全屏·一条窄横缝：谱竖直铺满，中间留 80 高的安全带
	{"说明": "全屏·一条窄横缝（挤进缝里）",
	 "外框": Rect2(-210, -390, 420, 442), "安全区": Rect2(-210, -102, 420, 80)},
]

## 贴图的自然宽度。模板表里的每块宽都是它的整数倍（见上）。
const 贴图宽 := 420.0

var _已命中: bool = false
var _存活: bool = false
var _左界: float = 0.0
var _模板: int = 0
var _外框: Rect2 = Rect2()
var _安全区: Rect2 = Rect2()
var _贴图: Texture2D = null
## 扫光相位（0→1 循环）
var _扫光: float = 0.0

## 贴图集为空时的兜底目录（Inspector 里挂了就以 Inspector 为准）
const 贴图目录 := "res://art/enemies/boss88/staff"

@onready var 判定: Area2D = $判定


## `锚点y` = 88 所在的地面高度（世界坐标）。**必须由调用方传进来** ——
## 以前这里读的是 `global_position.y`，而刚 `instantiate()` 出来的节点还没进场景树，
## 那个值是 **0**，于是五线谱生成在世界 (1620, 0)：在画面上方约 2900px 处横扫，
## 整个生命周期都在视野外，既看不见也打不到玩家。
## 模板坐标本来就是以"脚下 y = 0"为基准设计的（外框 y 从 -60 到 -430）。
func setup(速度: float, 招伤: int, 模板序号: int, 活动左: float, 活动右: float,
		锚点y: float) -> void:
	# 外框比贴图宽多少倍，速度就快多少倍 —— 保证**扫过时间**与旧版一致
	# （旧版外框 420、速度 260；现在 932 就乘 2.22）。
	伤害 = 招伤
	_模板 = clampi(模板序号, 0, 模板表.size() - 1)
	_左界 = 活动左
	var 条 := 模板表[_模板]
	行进速度 = 速度 * (float(条["外框"].size.x) / 贴图宽)
	_外框 = 条["外框"]
	_安全区 = 条["安全区"]
	# 谱贴图**随机取一张**（作者："实战技能中可以随机放"）。4 张尺寸完全一致，
	# 只有谱号（高/低音）与音符、血溅形状不同。
	_贴图 = _取贴图()
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
	_挂扫光()


## 挂扫光材质。**每个实例一份**（共用会让场上两条谱同步闪）。
func _挂扫光() -> void:
	var 材 := ShaderMaterial.new()
	材.shader = 扫光着色器
	材.set_shader_parameter("strength", 扫光强度)
	材.set_shader_parameter("sweep", 0.0)
	material = 材


## 扫光相位推进（谱台同款：每 `流光周期` 秒扫过一趟）
func _process(delta: float) -> void:
	if material is ShaderMaterial:
		_扫光 = fmod(_扫光 + delta / maxf(流光周期, 0.05), 1.0)
		(material as ShaderMaterial).set_shader_parameter("sweep", _扫光)


## 随机取一张谱贴图。Inspector 里挂了 `谱贴图集` 就用它，没挂就扫 `贴图目录` ——
## 这样场景资源不用改也能跑，同时保留"换美术拖 Inspector"的既有约定。
func _取贴图() -> Texture2D:
	if not 谱贴图集.is_empty():
		return 谱贴图集[randi() % 谱贴图集.size()]
	var 名: Array[String] = []
	var d := DirAccess.open(贴图目录)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".png") and not f.ends_with(".import"):
				名.append(f)
			f = d.get_next()
	名.sort()
	if 名.is_empty():
		return null
	return load(贴图目录 + "/" + 名[randi() % 名.size()]) as Texture2D


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


# ──────────────────────────── 视觉 ────────────────────────────
#
# 2026-09-22 起改用**贴图**（作者："整个五线谱加上面点缀的音符，是一张图，用 GPT 生成"）。
# 贴图用 `create_image_gpt.py -b transparent` 出的**真 alpha**，不用抠图 ——
# 旧方案是 `draw_line` 程序化画 5 条线，洋红底抠图会把细线抠脏。
# 判定形状（5 个模板 / 缝的位置）**完全没动**，只换了画法。


func _draw() -> void:
	if _外框.size == Vector2.ZERO:
		return
	var 贴 := _贴图
	if 贴 == null:
		_画兜底线()
		return
	var 贴宽 := float(贴.get_width())
	var 贴高 := float(贴.get_height())
	# **横向一整条、不断**（2026-09-22 定：x 方向不许有缺口）：
	# 外框宽 = 贴图宽（420）→ 每个块横向只铺**一张**、1:1，不缩放。
	# 纵向按块高铺满：单条模板只铺 1 张；"上下夹击/全屏"的块高是 72 的整数倍，
	# 会铺成**多条平行的谱**（这就是"全屏铺满"该有的样子）。
	for 块 in _分解矩形(_外框, _安全区):
		if 块.size.x <= 0.5 or 块.size.y <= 0.5:
			continue
		var 行数 := maxi(1, int(round(块.size.y / 贴高)))
		for j in 行数:
			draw_texture_rect_region(贴,
				Rect2(块.position.x, 块.position.y + float(j) * 贴高, 贴宽, 贴高),
				Rect2(0.0, 0.0, 贴宽, 贴高))
	if 调试显示范围:
		draw_rect(_外框, Color(1, 0.3, 0.3, 0.5), false, 2.0)
		draw_rect(_安全区, Color(0.3, 1.0, 0.4, 0.8), false, 2.0)


## 没挂贴图时的兜底：老的程序化 5 条线（保证场景没配贴图也能看见东西）
func _画兜底线() -> void:
	var 外框左 := _外框.position.x
	var 外框右 := _外框.end.x
	var 中高 := (_外框.position.y + _外框.end.y) * 0.5
	var 起 := 中高 - 行距 * (线数 - 1) * 0.5
	for i in 线数:
		var y := 起 + 行距 * i
		for 段 in _该行的可见段(Rect2(外框左, y, 外框右 - 外框左, 1.0)):
			draw_line(Vector2(段.position.x, y), Vector2(段.end.x, y), 线色, 线宽)


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
