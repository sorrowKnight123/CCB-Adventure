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
## 一阶段 Boss。接它的 `收尾完成(走真结局)`：玩家给《狂喜之诗》→ 变身对话结束 → 进跳跳乐。
@export var 战斗对象路径: NodePath = ^"../Boss88Phase1"
@export var 二阶段区域路径: NodePath = ^"../phase_2_area"
## 这棵子树整个不参与浮现（二阶段场地）
@export var 排除子树路径: NodePath = ^"../跳跳乐/战斗层"
## 二阶段专属的背景层（血丝网 + 四边危险带已合成一层），
## 进二阶段时显示、退出时隐藏（节点不存在时静默跳过）
@export var 二阶段背景路径: NodePath = ^"../二阶段背景"
## 背景压暗遮罩。二阶段把它打开 —— 透明血丝层叠在**压暗后**的音乐厅上才显眼
## （设计稿 §9：实测压暗把远景墙亮度 75.5 → 34.2，约 55%）。
@export var 压暗遮罩路径: NodePath = ^"../背景压暗遮罩"
@export var 二阶段压暗: bool = true

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
## 2026-09-22 起"一阶段收尾 → 开始追逐"已经接上（见 `_on_收尾完成`），
## 下面两个键只在**调试**时用（`调试按键` 打开才生效）。
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
## 二阶段锁定前存下的镜头 limits。**必须存**：一阶段的 ArenaLock 会把 limits
## 夹到竞技场（0~1600 / 2880~3600），而二阶段区域在 y 205~925 ——
## 只改相机位置、不改 limits 的话，镜头会被 limits 夹回下面那个房间，
## 二阶段区域根本进不了画面（表现为"背景一片不对/看不见"，且完全不报错）。
var _存_limits: Rect2 = Rect2()
var _有存_limits: bool = false
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
	# 2026-09-22 接上收尾：一阶段战胜 + 玩家给《狂喜之诗》→ 变身对话结束 → 进跳跳乐。
	# 原先 `Boss88Phase1.收尾完成` 这个信号**没有任何人监听** —— 所以跳跳乐只能靠
	# 调试键 Y 触发（作者："对话结束后，进入跳跳乐阶段（效果同现在的 y 键）"）。
	var boss := get_node_or_null(战斗对象路径)
	if boss != null and boss.has_signal("收尾完成") and not boss.收尾完成.is_connected(_on_收尾完成):
		boss.收尾完成.connect(_on_收尾完成)


## 一阶段收尾：走真结局（给了《狂喜之诗》）时，等**变身对话**结束再进跳跳乐。
## 给普通唱片则不介入（那条路走普通结局，不进二阶段）。
func _on_收尾完成(走真结局: bool) -> void:
	if not 走真结局:
		return
	# 对话是由 `Boss88Phase1._on_唱片选定` 在同一帧里放出来的，这里等它结束。
	# ⚠️ 等"**对话不再活跃**"而不是只等 `DialogueManager.dialogue_ended`：
	#    `DialogueBridge.interrupt()`（打断）只关气球、**不发** `dialogue_ended`，
	#    只等信号的话被打断时会永远卡住。两种结束方式都要能接上。
	while DialogueBridge.is_active:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	开始追逐()


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
	# ⚠️ 2026-09-22 作者要求：**背景压暗从"跳跳乐出现"就开始**，不是等到二阶段。
	#    原先只在 `进入二阶段()` 里压暗 —— 那之前跳跳乐已经在亮背景上浮出来了，
	#    观感上"跳跳乐是亮的、二阶段才暗"，割裂。现在一进追逐段就压暗（渐变 1 秒，
	#    见 `HallBackdropDim.渐变时长`）。`进入二阶段()` 里那次调用保留（幂等）。
	_设压暗(true)
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
	_设压暗(二阶段压暗)
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


## 背景压暗开关。用 `has_method` 守卫 —— 遮罩脚本可能被换掉或路径没填。
func _设压暗(开: bool) -> void:
	var n := get_node_or_null(压暗遮罩路径)
	if n != null and n.has_method("设置变暗"):
		n.call("设置变暗", 开)


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
	_套限制(区域)
	if _镜头补间 != null and _镜头补间.is_valid():
		_镜头补间.kill()
	_镜头补间 = create_tween()
	_镜头补间.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_镜头补间.tween_property(_相机, "global_position", 区域.get_center(), 二阶段镜头时长)


## 把镜头 limits 收到目标区域（区域正好一屏 → 相机被钉死在区域中心）。
## ⚠️ **只碰 limit_\***（`agent.md §20`）：绝不碰 position_smoothing_enabled / offset，
## 也绝不调 reset_smoothing()。
func _套限制(区域: Rect2) -> void:
	if _相机 == null:
		return
	if not _有存_limits:
		_存_limits = Rect2(_相机.limit_left, _相机.limit_top,
			_相机.limit_right - _相机.limit_left, _相机.limit_bottom - _相机.limit_top)
		_有存_limits = true
	_相机.limit_left = int(round(区域.position.x))
	_相机.limit_right = int(round(区域.end.x))
	_相机.limit_top = int(round(区域.position.y))
	_相机.limit_bottom = int(round(区域.end.y))


func _还原限制() -> void:
	if _相机 == null or not _有存_limits:
		return
	_相机.limit_left = int(round(_存_limits.position.x))
	_相机.limit_right = int(round(_存_limits.end.x))
	_相机.limit_top = int(round(_存_limits.position.y))
	_相机.limit_bottom = int(round(_存_limits.end.y))
	_有存_limits = false


## 退出二阶段（回普通跟随）。top_level 与本地位置的两次赋值必须在同一次调用里完成。
func 退出二阶段() -> void:
	if not 二阶段:
		return
	二阶段 = false
	_设背景层(false)
	_设压暗(false)
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
	# limits 在补间**之后**还原 —— 提前还原会把回程补间夹在半路
	_还原限制()
