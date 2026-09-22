extends Node2D
## 88 战的竞技场控制器：玩家进触发区 → 锁定镜头 → 锁回程门 → 开战；战胜后反向解锁。
##
## 镜头严格遵守 `agent.md §20`：**只动 `limit_*`**，绝不碰 `position_smoothing_enabled` / `offset`，
## 绝不调 `reset_smoothing()`，也绝不直接给 `global_position` / `zoom` 赋值（除非同一个值）。
##
## 为什么默认不需要"滑入"：触发区在竞技场**内部**，玩家走进去时相机已经在竞技场范围内，
## 直接把 `limit_*` 收到竞技场矩形，被夹住的位置和原来完全一样 → 不会有跳变。
## 真需要把镜头挪一段（例如二阶段换到顶层）时，把 `镜头滑入时长` 设成 > 0 就会先 tween 再套限制。
##
## 接口**可传矩形、可重复调用** —— 二阶段换到顶层时同一个脚本能直接复用。

@export var 触发区路径: NodePath = NodePath("触发区")
@export var 战斗对象路径: NodePath = NodePath("../Boss88Phase1")
@export var 回程门路径: NodePath = NodePath("../Door/4_1-3_1")
## 竞技场**右侧阻挡**（2026-09-22 作者实测："玩家可以走出这个区域，88 只能干瞪眼他出不去"）。
## 竞技场是 x 0~1600，而关卡右墙在 2560 —— 中间 960px 空白，玩家能走过去、
## 88 的 `活动右=1400` 追不过去。开战时把这道墙**启用**，胜利后**解除**。
## ⚠️ 它和 `回程门` 是**反向**的语义：门"锁"= 不触发，墙"锁"= 变实心。
@export var 右侧阻挡路径: NodePath = NodePath("../tile/ArenaBlocker")
## 竞技场矩形（作者定：一阶段 x 0~1600，y 取第 1 格）
@export var 竞技场矩形: Rect2 = Rect2(0, 2880, 1600, 720)
## > 0 时先把镜头 tween 到矩形中心再套限制（二阶段换房间时用）
@export var 镜头滑入时长: float = 0.0
@export var 已战胜时也锁场: bool = false

@export_group("开场演出（2026-09-22 加）")
## 开场把镜头推近到多少（默认 1.0）。以 Boss 为中心。
@export_range(1.0, 4.0, 0.1) var 开场缩放: float = 2.0
## 推近/还原各花多久（秒）。§20.2 的标准时长量级。
@export var 镜头推近时长: float = 0.6
## 聚焦点在 Boss 原点之上的偏移 —— 默认 (0,-44) = sprite 可视框的竖直中心。
## 用偏移而不是硬编码 Boss 坐标：换体型/换美术时只调这一个数。
@export var 镜头聚焦偏移: Vector2 = Vector2(0, -44)

## 门的意图状态。`门是否锁着()` 读它而不是读 Area2D 的 monitoring ——
## 因为 `_锁门` 走的是 set_deferred，物理属性要下一帧才变，读它会有假阴性。
var _门已锁: bool = false

var 战斗中: bool = false
var 已结束: bool = false
## 开战演出结束后置 true → **每帧重申**镜头限制（见 `_process`）。
## 为什么要重申：实测"镜头压根没锁死" —— `GameFlow._post_ready` 是 `call_deferred`，
## 可能晚于本组件的 `开始()` 并把 limit 写回关卡默认值；而且 `_锁到Boss()` 会把
## `top_level` 置 true（那时 limit 失效），万一还原收尾没跑到就一直是 true。
## 与其逐个猜谁覆盖，不如战斗期间每帧摁回去 —— 写 4 个 int 的成本可以忽略。
var _镜头锁住: bool = false
## 「这次还原之后要不要**重新上锁**」——
## ⚠️ 2026-09-22 修的一个自造 bug：原先 `_还原收尾()` 无条件写 `_镜头锁住 = true`，
##    而"一阶段结束解除"那条路也会走 `_还原镜头()` → 补间收尾又把锁打开了 ✗
##    → 下一帧重申把 limit 摁回竞技场 → 再检测到已结束 → 再解除 → **每 0.6 秒闪一次**
##    （作者实测："跳跳乐阶段每秒钟镜头都会闪回去一下"）。
##    所以"还原"和"重新上锁"必须分开：开场演出结束→上锁；一阶段结束→只还原、不上锁。
var _还原后锁回: bool = false

var _存限制 := Rect2i()
var _存_smoothing: bool = false
var _存_偏移 := Vector2.ZERO
var _存_top_level: bool = false
var _存_本地位置 := Vector2.ZERO
var _存_缩放 := Vector2.ONE
var _相机: Camera2D = null
var _补间: Tween = null


func _ready() -> void:
	add_to_group("boss_arena")
	var 区 := get_node_or_null(触发区路径) as Area2D
	if 区 != null:
		区.body_entered.connect(_on_进入)
	# 已经打赢过：不重开战斗（Boss 自己会进虚弱等你选唱片）
	if _已战胜():
		call_deferred("_处理已战胜")


func _已战胜() -> bool:
	var boss := get_node_or_null(战斗对象路径)
	var id: String = "boss88_phase1"
	if boss != null and boss.get("BOSS_ID") != null:
		id = str(boss.get("BOSS_ID"))
	return GameState.is_boss_defeated(id)


func _处理已战胜() -> void:
	已结束 = true
	if 已战胜时也锁场:
		_存镜头()
		_套限制(竞技场矩形)
		_锁门(true)
	else:
		_锁门(false)


func _on_进入(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if 战斗中 or 已结束:
		return
	开始()


## 也可以由外部直接调（测试与二阶段复用）
##
## 2026-09-22 起多了一段**开场演出**：推近镜头 → 冻住玩家 → 开战 → 等 Boss 的
## `intro_finished`（对话结束 + intro 动画播完）→ 还原镜头 → 解冻玩家。
## 作者要求："进入对战场地后镜头要放大、以 88 为中心……intro 完整播放完，镜头才恢复，
## 玩家才能动，boss 战才开始。"
func 开始() -> void:
	if 战斗中 or 已结束:
		return
	战斗中 = true
	_存镜头()
	if 镜头滑入时长 > 0.0:
		await _滑入到(竞技场矩形)
	_套限制(竞技场矩形)
	_锁门(true)
	_设右侧阻挡(true)
	var boss := get_node_or_null(战斗对象路径)
	if boss == null or not boss.has_method("start_battle"):
		return
	if boss.has_signal("victory") and not boss.victory.is_connected(_on_胜利):
		boss.victory.connect(_on_胜利)
	# ① 冻住玩家（马上，别让他在演出里乱跑）
	_冻玩家(true)
	# ② 开战：Boss 保持 intro 第 0 帧 → 放对话 → 对话结束才播 intro → 播完发信号
	#
	# ⚠️ 顺序很重要：**必须先把 `start_battle()` 发出去**，再推镜头。
	#    第一版我把 `await _锁到Boss()`（0.6 秒变焦）排在开战之前 —— 于是那 0.6 秒里
	#    `battle_started` 还是 false，任何按"战斗已开始"判断的东西（`_攻击有效`、
	#    招式里的 `_等到帧`）都会直接返回。自检立刻抓到了：三连击"整段耗时 0.00 秒"、
	#    位移 0px。推镜头本来就不该阻塞开战 —— 它正好在对话那几秒里滑完。
	var 有信号 := boss.has_signal("intro_finished")
	if 有信号 and not boss.intro_finished.is_connected(_on_开场结束):
		boss.intro_finished.connect(_on_开场结束, CONNECT_ONE_SHOT)
	boss.start_battle()
	# ③ 推近镜头（不 await：让它在对话期间自己滑完）
	_锁到Boss()
	if not 有信号:
		# 没有这个信号（旧版 Boss / 二阶段复用）→ 不卡流程，直接还原
		_on_开场结束()


## Boss 的 intro 播完：还原镜头 + 解冻玩家。
## 解冻与还原**同时**开始 —— 不等 0.6 秒滑完再解冻，否则 Boss 的攻击循环已经起来了、
## 玩家还动不了，不公平（Boss 首招有 `出手间隔 1.8s` 兜底）。
func _on_开场结束() -> void:
	_冻玩家(false)
	_还原后锁回 = true          # 开场演出结束 → 还原后把镜头锁死在竞技场
	_还原镜头()


## 显式冻结玩家。对话期间是**自动**冻结的（`DialogueBridge.is_active`），
## 但 `dialogue_ended` 一触发就自动解冻 —— 所以 intro 播放那段必须显式冻住。
## 用 `输入软冻结` 而不是 `get_tree().paused`：后者会把镜头 Tween 一起冻死（§19/§20）。
func _冻玩家(开: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if player.get("输入软冻结") == null:      # 旧版玩家脚本：静默跳过
		return
	if bool(player.get("输入软冻结")) != 开:
		player.set("输入软冻结", 开)


func _on_胜利() -> void:
	if 已结束:
		return
	战斗中 = false
	已结束 = true
	_镜头锁住 = false
	_还原镜头()
	_锁门(false)
	_设右侧阻挡(false)


## 退出场景时把门放开，别让下一次进来是锁着的
func _exit_tree() -> void:
	if 战斗中:
		_锁门(false)


# ──────────────────────────── 镜头（§20） ────────────────────────────


func _存镜头() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	_相机 = player.get_node_or_null("Camera2D") as Camera2D
	if _相机 == null:
		return
	_存限制 = Rect2i(_相机.limit_left, _相机.limit_top,
		_相机.limit_right - _相机.limit_left, _相机.limit_bottom - _相机.limit_top)
	_存_smoothing = _相机.position_smoothing_enabled
	_存_偏移 = _相机.offset
	_存_top_level = _相机.top_level
	_存_本地位置 = _相机.position
	_存_缩放 = _相机.zoom


## 只改 limits。触发区在竞技场内部，相机被夹的位置不变 → 无跳变
func _套限制(矩形: Rect2) -> void:
	if _相机 == null:
		return
	_相机.limit_left = int(矩形.position.x)
	_相机.limit_top = int(矩形.position.y)
	_相机.limit_right = int(矩形.end.x)
	_相机.limit_bottom = int(矩形.end.y)


## 开场推近：以 Boss 为中心放大到 `开场缩放`。严格照 §20.2-A ——
## `top_level = true` 之后**必须把同一个 global_position 赋回**（抵消继承变换变化），
## 然后位置与 zoom **并行 tween**，绝不直接赋值。
func _锁到Boss() -> void:
	if _相机 == null or not is_instance_valid(_相机):
		return
	var boss := get_node_or_null(战斗对象路径) as Node2D
	if boss == null:
		return
	var 起点 := _相机.global_position
	_相机.top_level = true
	_相机.global_position = 起点
	if 补间有效():
		_补间.kill()
	_补间 = create_tween()
	_补间.set_parallel(true)
	_补间.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_补间.tween_property(_相机, "global_position", boss.global_position + 镜头聚焦偏移, 镜头推近时长)
	_补间.tween_property(_相机, "zoom", Vector2(开场缩放, 开场缩放), 镜头推近时长)
	await _补间.finished


## 还原镜头：limit 立刻还原（它只改可拖动范围、不产生位移），位置与 zoom 走 tween。
##
## ⚠️ 2026-09-22 补：原先这里**只还原 `limit_*`**（当时这个组件只改 limit 所以无所谓）。
##    现在它改了 zoom，就必须把 **zoom / top_level / 本地 position** 一起还原 ——
##    正是 `agent.md §20.3` 点名的"很多老实现漏了这个"。
func _还原镜头() -> void:
	if _相机 == null or not is_instance_valid(_相机):
		return
	if 补间有效():
		_补间.kill()
	_相机.limit_left = _存限制.position.x
	_相机.limit_top = _存限制.position.y
	_相机.limit_right = _存限制.end.x
	_相机.limit_bottom = _存限制.end.y
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var 目标 := player.global_position if player != null else _相机.global_position
	_补间 = create_tween()
	_补间.set_parallel(true)
	_补间.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_补间.tween_property(_相机, "global_position", 目标, 镜头推近时长)
	_补间.tween_property(_相机, "zoom", _存_缩放, 镜头推近时长)
	_补间.chain().tween_callback(_还原收尾)


## §20.2-C：三项必须在**同一次调用**里翻回去 —— `top_level` 先翻回，再恢复本地 position 与 zoom。
## 翻回时相机重新跟随 Player，global 位置由"玩家位置 + 本地 position"决定；
## 本地 position 存的就是原来的值（通常 (0,0)），所以和 tween 的终点一致，不会跳。
func _还原收尾() -> void:
	if _相机 == null or not is_instance_valid(_相机):
		return
	_相机.top_level = _存_top_level
	_相机.position = _存_本地位置
	_相机.zoom = _存_缩放
	# 只在"开场演出结束"那条路才重新上锁；"一阶段结束解除"那条路到这里必须**保持解除**
	if _还原后锁回:
		_镜头锁住 = true
		_套限制(竞技场矩形)
	_还原后锁回 = false


## 需要挪一段镜头时：先 tween 到目标点，再在这个回调里套限制（避免"先夹住再滑"的二次位移）
func _滑入到(矩形: Rect2) -> void:
	if _相机 == null:
		return
	var 起点 := _相机.global_position
	_相机.top_level = true
	_相机.global_position = 起点          # 同一个值赋回，抵消 top_level 带来的继承变换
	if 补间有效():
		_补间.kill()
	_补间 = create_tween()
	_补间.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_补间.tween_property(_相机, "global_position", 矩形.get_center(), 镜头滑入时长)
	await _补间.finished


func 补间有效() -> bool:
	return _补间 != null and _补间.is_valid()


# ──────────────────────────── 门 ────────────────────────────


## 右侧阻挡：`开` = 变实心（`collision_layer = 1`，与关卡里的墙同层），`关` = 透明可穿。
## 必须 `set_deferred`：`开始()` 是从触发区的 `body_entered` 里调下来的，
## 物理回调期间直接改 collision_layer 会被引擎挡掉（和 `_锁门` 同一个坑）。
func _设右侧阻挡(开: bool) -> void:
	var 墙 := get_node_or_null(右侧阻挡路径) as StaticBody2D
	if 墙 == null:
		return
	墙.set_deferred("collision_layer", 1 if 开 else 0)


## 锁门 = 关掉 Area2D 的 monitoring/monitorable（与 BossArena 同一套语义）。
##
## ⚠️ 必须 `set_deferred`：`开始()` 是从触发区的 `body_entered` 里调下来的，
##    物理回调期间直接改 monitoring / monitorable 会被引擎挡掉 —— 只在输出里留一行
##    「Function blocked during in/out signal」，**门其实没锁上**。这类错误不崩不卡，
##    只能靠翻日志发现，所以这里连同 `_门已锁` 一起记意图，供自检立刻读到。
func _锁门(锁: bool) -> void:
	_门已锁 = 锁
	var 门 := get_node_or_null(回程门路径) as Area2D
	if 门 == null:
		return
	门.set_deferred("monitoring", not 锁)
	门.set_deferred("monitorable", not 锁)


# ──────────────────────────── 自检/调试接口 ────────────────────────────


## 只做一件事：**一阶段结束时解除**（作者 2026-09-22："你就一阶段战斗，镜头锁定，
## 结束解除，不就好了吗？不要做成每秒强制锁到目标区域，那样很消耗性能也很多余"）。
##
## 镜头锁定本身是**一次性**的：`开始()` 与开场演出收尾各写一次 `_套限制`，
## 之后**不再每帧重申** ✗。这里每帧只读一个 bool（`battle_started`）判断"一阶段是不是结束了"，
## 结束了就**只还原一次**（`_还原镜头` 会 kill 掉旧补间，重复调也无害，但下面用标志位挡住）。
func _process(_delta: float) -> void:
	if not _镜头锁住 or _相机 == null or not is_instance_valid(_相机):
		return
	var boss := get_node_or_null(战斗对象路径)
	if boss != null and not bool(boss.get("battle_started")):
		# 一阶段结束（88 进虚弱）→ 解除一次，之后不再上锁
		_镜头锁住 = false
		_还原后锁回 = false
		_还原镜头()


func 取竞技场矩形() -> Rect2:
	return 竞技场矩形


func 门是否锁着() -> bool:
	return _门已锁
