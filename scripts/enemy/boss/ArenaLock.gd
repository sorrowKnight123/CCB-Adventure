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
## 竞技场矩形（作者定：一阶段 x 0~1600，y 取第 1 格）
@export var 竞技场矩形: Rect2 = Rect2(0, 2880, 1600, 720)
## > 0 时先把镜头 tween 到矩形中心再套限制（二阶段换房间时用）
@export var 镜头滑入时长: float = 0.0
@export var 已战胜时也锁场: bool = false

## 门的意图状态。`门是否锁着()` 读它而不是读 Area2D 的 monitoring ——
## 因为 `_锁门` 走的是 set_deferred，物理属性要下一帧才变，读它会有假阴性。
var _门已锁: bool = false

var 战斗中: bool = false
var 已结束: bool = false

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
func 开始() -> void:
	if 战斗中 or 已结束:
		return
	战斗中 = true
	_存镜头()
	if 镜头滑入时长 > 0.0:
		await _滑入到(竞技场矩形)
	_套限制(竞技场矩形)
	_锁门(true)
	var boss := get_node_or_null(战斗对象路径)
	if boss != null and boss.has_method("start_battle"):
		if boss.has_signal("victory") and not boss.victory.is_connected(_on_胜利):
			boss.victory.connect(_on_胜利)
		boss.start_battle()


func _on_胜利() -> void:
	if 已结束:
		return
	战斗中 = false
	已结束 = true
	_还原镜头()
	_锁门(false)


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


func _还原镜头() -> void:
	if _相机 == null or not is_instance_valid(_相机):
		return
	if _补间 != null and _补间.is_valid():
		_补间.kill()
	_相机.limit_left = _存限制.position.x
	_相机.limit_top = _存限制.position.y
	_相机.limit_right = _存限制.end.x
	_相机.limit_bottom = _存限制.end.y


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


func 取竞技场矩形() -> Rect2:
	return 竞技场矩形


func 门是否锁着() -> bool:
	return _门已锁
