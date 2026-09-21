extends Node2D
## 音乐厅 1.5 追逐段（跳跳乐 → 二阶段）总控。
##
## 规则（作者定稿）：
##   · 鼓 / 平台 / 墙三类**统一参与**同一条序号队列
##   · **浮现只增不减**：碰到序号 N → 浮现到 N + 领先级数，永不回收
##   · 初始**全部隐藏**：一阶段战斗期间跳跳乐一点都不露，只有进入追逐段才浮现 1、2
##   · 唯一会"消失"的时机：**进入二阶段战斗时，所有带序号元素一起消失**
##   · **1.5 期间掉到地面没有任何惩罚**（不扣血、不位移）—— 重跑一遍本身就是惩罚。
##     难度以后由"88 的干扰攻击"提供（待做），不靠摔落惩罚。
##   · 进入 phase_2_area → 隐藏跳跳乐、显示二阶段背景层、视口锁到该区域；
##     **二阶段掉出视口扣 1 血**并在战斗区域的平台里随机重生（这条保留：单层背景的**四边浓中央疏**就是它的视觉提示）
##
## 序号怎么给（两种都认，**metadata 优先**）：
##   ① 节点名直接写成整数（作者现在用的方式）：`跳跳乐/1` … `跳跳乐/18`
##   ② Inspector 最下方 Metadata 加 `浮现序号`（int）—— 名字不是数字、或想覆盖名字时用
## 两类都**不需要给预制体加脚本、也不用改任何预制体**。
##
## ⚠️ `排除子树` 默认指向 `跳跳乐/战斗层`：那是二阶段场地，整棵子树不参与浮现，
##    否则它的 `1`/`2`/`3`… 会和爬升段的同名节点撞号。
##
## 镜头严格遵守 `agent.md §20`：只用 tween/lerp 改 `global_position`，
## **绝不碰** `position_smoothing_enabled` / `offset`，**绝不调** `reset_smoothing()`。

signal 二阶段开始            ## 二阶段视口锁定完成（以后给 88 本体接）
signal 掉落扣血(扣血: int)   ## 二阶段掉出视口（给音效/表现留口子）

@export_group("节点")
@export var 跳跳乐路径: NodePath = ^"../跳跳乐"
@export var 二阶段区域路径: NodePath = ^"../phase_2_area"
## 这棵子树整个不参与浮现（二阶段场地）
@export var 排除子树路径: NodePath = ^"../跳跳乐/战斗层"
## 二阶段专属的背景层（血丝网 + 四边危险带已合成一层），
## 进二阶段时显示、退出时隐藏（节点不存在时静默跳过）
@export var 二阶段背景路径: NodePath = ^"../二阶段背景"

@export_group("浮现规则")
## 浮现到"已碰最高序号 + 这个值"
@export var 领先级数: int = 2
@export var 淡入时长: float = 0.30

@export_group("二阶段")
@export var 二阶段镜头时长: float = 0.8
@export var 二阶段掉出容差: float = 40.0
## 掉出视口重生后的无敌宽限，防止同一次掉落连判
@export var 掉落宽限: float = 0.35
## 重生点相对平台顶面再抬高多少（玩家胶囊半高 57 + 余量）
@export var 复活点上方偏移: float = 72.0
@export var 切换二阶段时全部隐藏: bool = true

@export_group("调试")
## 一阶段 Boss 还没做，所以"变身结束 → 开始追逐"这一步暂时没人调。
## 开着这个开关就能在游戏里直接试：
##   Y = 开始追逐（跳跳乐开始依次浮现）    U = 直接进二阶段（隐藏跳跳乐 + 显示背景 + 锁视口）
## 上线前关掉。（比照 `HallBackdropDim.gd` 的 调试按键）
@export var 调试按键: bool = true

var 启用: bool = false                  ## 有任何一个元素带序号才为真
var 追逐中: bool = false                ## 追逐段已开始
var 二阶段: bool = false

var _元素: Array[Node2D] = []           ## 带序号的元素，按序号升序
var _序号: Dictionary = {}              ## Node2D -> int
var _类型: Dictionary = {}              ## Node2D -> "鼓" / "平台" / "墙"
var _已显示: Dictionary = {}            ## Node2D -> bool
## 原始碰撞层缓存：只在第一次收集时记录，跨 重新收集() 保留 ——
## 否则元素被隐藏（层写成 0）之后再收集，会把 0 当成原始层，平台就再也变不回来。
var _原始层缓存: Dictionary = {}        ## CollisionObject2D -> int
var _初采完成: bool = false
var _刚体: Dictionary = {}              ## Node2D -> Array[[CollisionObject2D, 原始层]]
var _触发: Dictionary = {}              ## Node2D -> Array[Area2D]
var _补间: Dictionary = {}              ## Node2D -> Tween
var _游标: int = 0                      ## 已碰过的最高序号
var _宽限: float = 0.0                  ## 只服务二阶段掉落

var _玩家: CharacterBody2D = null
var _相机: Camera2D = null
var _区域矩形: Rect2 = Rect2()
var _存_top_level: bool = false
var _存_本地位置: Vector2 = Vector2.ZERO
var _存_zoom: Vector2 = Vector2.ONE
var _镜头补间: Tween = null
var _y_was_down: bool = false
var _u_was_down: bool = false


func _ready() -> void:
	add_to_group("hall_chase")
	重新收集()
	set_process(调试按键 and 启用)
	if not 启用:
		# 一个序号都没有：完全不介入，行为与以前一致
		set_physics_process(false)


## 调试：按一下切一次（不是按住连切）
func _process(_delta: float) -> void:
	var y := Input.is_physical_key_pressed(KEY_Y)
	if y and not _y_was_down:
		开始追逐()
	_y_was_down = y
	var u := Input.is_physical_key_pressed(KEY_U)
	if u and not _u_was_down:
		进入二阶段()
	_u_was_down = u


## 重新扫描跳跳乐、按序号重建状态。序号运行时也能改（测试与调试都靠它）。
func 重新收集() -> void:
	_收集元素()
	_初采完成 = true        # 第一次采完就锁住原始层，之后不再覆盖
	_元素.sort_custom(_按序号升序)
	启用 = not _元素.is_empty()
	set_physics_process(启用)
	set_process(调试按键 and 启用)
	if 启用:
		_初始状态()


func _按序号升序(a: Node2D, b: Node2D) -> bool:
	return int(_序号[a]) < int(_序号[b])


# ──────────────────────────── 收集 ────────────────────────────


func _收集元素() -> void:
	_元素.clear()
	_序号.clear()
	_类型.clear()
	_刚体.clear()
	_触发.clear()
	var 根 := get_node_or_null(跳跳乐路径)
	if 根 == null:
		push_warning("追逐段：找不到跳跳乐节点 %s" % 跳跳乐路径)
		return
	_遍历(根, get_node_or_null(排除子树路径))


func _遍历(n: Node, 排除: Node) -> void:
	for 子 in n.get_children():
		if 子 == 排除:
			continue
		if 子 is Node2D:
			var k := _取序号(子)
			if k > 0:
				var e := 子 as Node2D
				_元素.append(e)
				_序号[e] = k
				_缓存碰撞件(e)          # 先缓存原始层，_判类型 要用
				_类型[e] = _判类型(e)
		_遍历(子, 排除)


## metadata 优先，其次把节点名当整数（作者现在把爬升段命名成 1…18）
func _取序号(n: Node) -> int:
	if n.has_meta("浮现序号"):
		return int(n.get_meta("浮现序号"))
	var 名 := String(n.name)
	return int(名) if 名.is_valid_int() else 0


## 按子树判类型：有层 16 的实体 = 平台；有层 1 的实体 = 墙；只有 Area2D 触发器的 = 鼓。
## （墙可能装在 Node2D 分组节点里；平台/墙的实体就是元素自身，所以**必须把自己也算进来**）
##
## ⚠️ 层取的是 `_原始层缓存`（第一次收集时的值），不是当前值 ——
##    元素被隐藏后当前层是 0，拿当前值判会把平台/墙全判成"没类型"。
##    所以调用顺序必须是：先 `_缓存碰撞件()`，再 `_判类型()`。
func _判类型(n: Node) -> String:
	var 有平台 := false
	var 有墙 := false
	var 有触发 := false
	for c in _自身与后代(n):
		if c is Area2D:
			有触发 = true
		elif c is CollisionObject2D:
			var 体 := c as CollisionObject2D
			var 层 := int(_原始层缓存.get(体, 体.collision_layer))
			if (层 & 16) != 0:
				有平台 = true
			if (层 & 1) != 0:
				有墙 = true
	if 有平台:
		return "平台"
	if 有墙:
		return "墙"
	if 有触发:
		return "鼓"
	return ""


func _自身与后代(n: Node) -> Array[Node]:
	var 出: Array[Node] = [n]
	_收后代(n, 出)
	return 出


func _收后代(n: Node, 出: Array[Node]) -> void:
	for 子 in n.get_children():
		出.append(子)
		_收后代(子, 出)


## 隐藏一个"分组节点"（比如装着 3 片墙的 `10`）时，光隐藏它在视觉上有效，
## 但子 StaticBody2D 的碰撞依然在 —— 所以收集时就把整棵子树的碰撞件缓存下来。
## 元素自身的实体（平台的 StaticBody2D）也要算，否则它的碰撞永远关不掉。
func _缓存碰撞件(e: Node2D) -> void:
	var 刚: Array = []
	var 触: Array[Area2D] = []
	for c in _自身与后代(e):
		if c is Area2D:
			触.append(c as Area2D)
		elif c is CollisionObject2D:
			var 体 := c as CollisionObject2D
			if not _初采完成:
				_原始层缓存[体] = 体.collision_layer
			刚.append([体, int(_原始层缓存.get(体, 体.collision_layer))])
	_刚体[e] = 刚
	_触发[e] = 触


# ──────────────────────────── 初始状态与浮现 ────────────────────────────


## 初始：**全部隐藏**。一阶段战斗期间跳跳乐一点都不露。
func _初始状态() -> void:
	_游标 = 0
	_宽限 = 0.0
	for e in _元素:
		_已显示.erase(e)
		_补间.erase(e)
		_设显示(e, false)
	_连鼓信号()


func _连鼓信号() -> void:
	for e in _元素:
		if _类型[e] != "鼓":
			continue
		for c in _触发[e]:
			if not c.body_entered.is_connected(_on_鼓被踩):
				c.body_entered.connect(_on_鼓被踩.bind(e))


## **只增不减**：把序号 ≤ 游标+领先级数 的全部显示出来，不隐藏任何东西
func _推导() -> void:
	for e in _元素:
		if int(_序号[e]) <= _游标 + 领先级数:
			_设显示(e, true)


func _设显示(n: Node2D, 显示: bool) -> void:
	if bool(_已显示.get(n, not 显示)) == 显示:
		return
	_已显示[n] = 显示
	_切碰撞(n, 显示)

	var 旧: Tween = _补间.get(n)
	if 旧 != null and 旧.is_valid():
		旧.kill()

	if not 显示:
		# 隐藏只在"初始"和"进二阶段"发生，都是硬切
		n.modulate.a = 0.0
		n.visible = false
		return

	# 浮现做淡入（节点由隐藏转可见，所以从 0 开始）
	n.visible = true
	n.modulate.a = 0.0
	_补间[n] = create_tween()
	_补间[n].tween_property(n, "modulate:a", 1.0, 淡入时长)


## 隐藏必须同时关碰撞 —— 只看不见是不够的（`agent.md §21.2`：看不见的鼓照样会弹人）
func _切碰撞(n: Node2D, 开: bool) -> void:
	for 对 in _刚体.get(n, []):
		(对[0] as CollisionObject2D).set_deferred("collision_layer", int(对[1]) if 开 else 0)
	for c in _触发.get(n, []):
		c.set_deferred("monitoring", 开)
		c.set_deferred("monitorable", 开)


func _是否显示(n: Node2D) -> bool:
	return bool(_已显示.get(n, false))


# ──────────────────────────── 触碰 ────────────────────────────


func _on_鼓被踩(body: Node2D, 鼓: Node2D) -> void:
	if body.is_in_group("player"):
		_碰触(鼓)


func _碰触(n: Node2D) -> void:
	# 追逐段没开始之前，碰什么都不算（一阶段战斗期间跳跳乐是关着的，
	# 正常也碰不到；这条是显式不变量，不靠"碰撞恰好关着"）。
	if not 追逐中 or 二阶段:
		return
	if not _元素.has(n):
		return
	if int(_序号[n]) > _游标:
		_游标 = int(_序号[n])
		_推导()


## 平台/墙用玩家这一帧的滑动碰撞来判"碰到"（零预制体改动、零额外 Area2D）；
## 鼓没有实体碰撞，走它自带的 Trigger.body_entered。
func _轮询脚下() -> void:
	if _玩家 == null:
		return
	for i in _玩家.get_slide_collision_count():
		var 对象 := _玩家.get_slide_collision(i).get_collider()
		if 对象 is Node2D:
			var e := _找元素祖先(对象)
			if e != null:
				_碰触(e)
				return


## 从碰撞体往上找最近的"带序号元素"（碰撞形状可能挂在子节点上）
func _找元素祖先(n: Node) -> Node2D:
	var 走: Node = n
	for _i in 6:
		if 走 == null:
			return null
		if 走 is Node2D and _元素.has(走):
			return 走 as Node2D
		走 = 走.get_parent()
	return null


# ──────────────────────────── 每帧 ────────────────────────────


func _physics_process(delta: float) -> void:
	_找玩家和相机()
	if _玩家 == null:
		return
	_宽限 = maxf(_宽限 - delta, 0.0)
	if 二阶段:
		_判掉出视口()
	elif 追逐中:
		# 1.5 期间掉到地面不做任何事，只要认出"碰到哪块"来推进浮现队列
		_轮询脚下()


func _找玩家和相机() -> void:
	if _玩家 == null or not is_instance_valid(_玩家):
		_玩家 = get_tree().get_first_node_in_group("player") as CharacterBody2D
	if _玩家 != null and (_相机 == null or not is_instance_valid(_相机)):
		_相机 = _玩家.get_node_or_null("Camera2D") as Camera2D


## 平台顶面 = 节点上方 13px（碰撞形状 196×16，本地 y=-5）
func _重生点(n: Node2D) -> Vector2:
	var 顶 := n.global_position + Vector2(0.0, -13.0)
	return Vector2(顶.x, 顶.y - 复活点上方偏移)


# ──────────────────────────── 舞台切换 ────────────────────────────


## 追逐段开始（变身演出结束后调用）：这时候才让 1、2 浮现。
func 开始追逐() -> void:
	if 追逐中:
		return
	追逐中 = true
	_宽限 = 掉落宽限
	_推导()          # 游标为 0 → 浮现序号 ≤ 领先级数


## 玩家进入 phase_2_area 时调用
func 进入二阶段() -> void:
	if 二阶段:
		return
	二阶段 = true
	追逐中 = false
	if 切换二阶段时全部隐藏:
		# 唯一一次"一起消失"
		for e in _元素:
			_设显示(e, false)
	_设背景层(true)
	_算区域矩形()
	if _区域矩形.size != Vector2.ZERO:
		_锁镜头到区域(_区域矩形)
	二阶段开始.emit()


func 区域矩形() -> Rect2:
	return _区域矩形


## 二阶段专属的背景层（节点不在或路径没填就静默跳过）
func _设背景层(开: bool) -> void:
	var n := get_node_or_null(二阶段背景路径)
	if n is CanvasItem:
		(n as CanvasItem).visible = 开


func _算区域矩形() -> void:
	var 区 := get_node_or_null(二阶段区域路径) as Area2D
	if 区 == null:
		push_warning("追逐段：找不到二阶段区域 %s" % 二阶段区域路径)
		return
	var 形 := 区.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if 形 == null or not (形.shape is RectangleShape2D):
		push_warning("追逐段：phase_2_area 的碰撞形状不是矩形，锁不了视口")
		return
	var 尺寸 := (形.shape as RectangleShape2D).size
	_区域矩形 = Rect2(形.global_position - 尺寸 * 0.5, 尺寸)


## 二阶段：掉出视口 = 扣 1 血 + 在战斗区域的平台里随机重生
func _判掉出视口() -> void:
	if _区域矩形.size == Vector2.ZERO or _宽限 > 0.0:
		return
	if _玩家.global_position.y <= _区域矩形.end.y + 二阶段掉出容差:
		return
	_玩家.take_damage(1, _玩家.global_position)
	掉落扣血.emit(1)
	var 点 := _随机战斗平台()
	if 点 != null:
		_玩家.global_position = _重生点(点)
	_宽限 = 掉落宽限


## 战斗区域里的平台（含不参与浮现的 `战斗层`）随机一块
func _随机战斗平台() -> Node2D:
	var 候选: Array[Node2D] = []
	var 根 := get_node_or_null(跳跳乐路径)
	if 根 != null:
		for e in _扫全局平台(根):
			if _区域矩形.has_point(e.global_position):
				候选.append(e)
	if 候选.is_empty():
		return null
	return 候选[randi() % 候选.size()]


func _扫全局平台(n: Node) -> Array[Node2D]:
	var 出: Array[Node2D] = []
	for 子 in n.get_children():
		if 子 is Node2D and _判类型(子) == "平台":
			出.append(子 as Node2D)
		出.append_array(_扫全局平台(子))
	return 出


# ──────────────────────────── 调试/自检接口 ────────────────────────────


func 取元素(序号值: int) -> Node2D:
	for e in _元素:
		if int(_序号[e]) == 序号值:
			return e
	return null


## 给自检与调试看的快照
func 调试状态() -> Dictionary:
	var 显: Array[int] = []
	var 全部: Array[int] = []
	for e in _元素:
		全部.append(int(_序号[e]))
		if _是否显示(e):
			显.append(int(_序号[e]))
	显.sort()
	全部.sort()
	return {
		"启用": 启用,
		"序号表": 全部,
		"游标": _游标,
		"显示": 显,
		"区域矩形": _区域矩形,
		"玩家": _玩家,
	}


# ──────────────────────────── 镜头（§20） ────────────────────────────


func _锁镜头到区域(区域: Rect2) -> void:
	if _相机 == null:
		return
	_存_top_level = _相机.top_level
	_存_本地位置 = _相机.position
	_存_zoom = _相机.zoom
	var 起点 := _相机.global_position
	_相机.top_level = true
	_相机.global_position = 起点        # 同一个值赋回，抵消 top_level 带来的继承变换
	if _镜头补间 != null and _镜头补间.is_valid():
		_镜头补间.kill()
	_镜头补间 = create_tween()
	_镜头补间.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_镜头补间.tween_property(_相机, "global_position", 区域.get_center(), 二阶段镜头时长)


## 退出二阶段（回普通跟随）。top_level 与本地位置的两次赋值必须在同一次调用里完成。
func 退出二阶段() -> void:
	if not 二阶段:
		return
	二阶段 = false
	_设背景层(false)
	if _相机 == null:
		return
	if _镜头补间 != null and _镜头补间.is_valid():
		_镜头补间.kill()
	var 回到 := _玩家.global_position if _玩家 != null else _相机.global_position
	_镜头补间 = create_tween()
	_镜头补间.tween_property(_相机, "global_position", 回到, 0.6)
	_镜头补间.tween_callback(_镜头还原收尾)


func _镜头还原收尾() -> void:
	if _相机 == null:
		return
	_相机.top_level = _存_top_level
	if not _存_top_level:
		_相机.position = _存_本地位置
	_相机.zoom = _存_zoom
