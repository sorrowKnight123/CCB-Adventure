extends Node
## 音乐厅 1.5 追逐段自检：初始全隐藏 / 浮现只增不减 / **落地无惩罚** /
## 进二阶段一起消失 / 二阶段掉出视口重生。
##
## 期望值直接来自设计：
##   初始全隐藏 → 开始追逐才浮现 1、2 → 踩 1 则 3 浮现 → 碰 2 则 4 浮现
##   **浮现之后永不回收**（早期"收掉 N-1"的规则实机导致踩空，已废弃）
##   **1.5 期间掉到地面不扣血也不位移**（作者定：重跑本身就是惩罚）
##
## 逻辑检查直接调管理器方法，不依赖物理帧率；最后一项"玩家真站在平台上会被轮询到"跑物理。
## 运行：godot --headless --path . res://tests/test_hall_chase.tscn --quit-after 9000

const LEVEL := preload("res://scenes/levels/music_hall/4_1.tscn")
## phase_2_area 的世界矩形：节点 (1341,565)，形状本地 (-1,0)、1280×720
const 期望区域 := Rect2(700.0, 205.0, 1280.0, 720.0)

var _p: int = 0
var _f: int = 0
var _lvl: Node2D = null
var _chase: Node = null
var _player: CharacterBody2D = null


func _ready() -> void:
	_lvl = LEVEL.instantiate()
	add_child(_lvl)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_chase = _lvl.get_node_or_null("追逐段")
	_player = _lvl.get_node_or_null("Player")

	await _检查接线与收集()
	await _检查初始全隐藏()
	await _检查浮现只增不减()
	await _检查爬满全场()
	await _检查落地无事()
	await _检查二阶段()
	await _检查物理轮询()

	print("\n===== 音乐厅 1.5 追逐段自检结果：通过 %d / 失败 %d =====" % [_p, _f])
	get_tree().quit(0 if _f == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_p += 1
		print("[PASS] " + what)
	else:
		_f += 1
		print("[FAIL] " + what)


func _状态() -> Dictionary:
	return _chase.调试状态()


## set_deferred 写进去的碰撞层要等一帧物理；而 Tween 默认跑在 idle 帧上，两种帧都得等。
func _等一帧() -> void:
	await get_tree().physics_frame
	for _i in 6:
		await get_tree().process_frame


## 玩家身上的 Camera2D（找不到就返回 null，断言会自己跳过）
func _相机() -> Camera2D:
	if _player == null:
		return null
	return _player.get_node_or_null("Camera2D") as Camera2D


func _踩(序号: int) -> void:
	_chase._碰触(_chase.取元素(序号))


## 鼓没有实体碰撞（根节点是 Sprite2D），看的是 $Trigger.monitoring；
## 平台/墙才是 CollisionObject2D，看 collision_layer。
func _碰撞开着(序号: int) -> bool:
	var e: Node2D = _chase.取元素(序号)
	if e == null:
		return false
	if e is CollisionObject2D:
		return (e as CollisionObject2D).collision_layer != 0
	var tr := e.get_node_or_null("Trigger") as Area2D
	return tr != null and tr.monitoring


# ──────────────────────────── 接线与收集 ────────────────────────────


func _检查接线与收集() -> void:
	_check(_chase != null, "接线：4_1 里有 追逐段 节点")
	_check(_player != null, "接线：4_1 里有 Player")
	if _chase == null:
		return
	await _等一帧()
	_check(_chase.启用 == true, "接线：管理器已启用（跳跳乐里存在带序号的元素）")
	_check(_状态()["玩家"] != null, "接线：管理器已通过 player 组找到玩家")

	var 表: Array = _状态()["序号表"]
	_check(表.size() == 18, "收集：爬升段共 18 个带序号元素（实际 %d 个）" % 表.size())
	var 升序 := true
	for i in range(1, 表.size()):
		if 表[i] <= 表[i - 1]:
			升序 = false
	_check(升序, "收集：序号升序")

	var 战斗层 := _lvl.get_node_or_null("跳跳乐/战斗层")
	var 序1: Node2D = _chase.取元素(1)
	_check(战斗层 != null and 序1 != null and not 战斗层.is_ancestor_of(序1),
		"收集：序号 1 属于爬升段，不是战斗层里的同名节点")

	_check(_chase._类型[_chase.取元素(9)] == "平台", "收集：序号 9 识别为 平台")
	_check(_chase._类型[_chase.取元素(17)] == "平台", "收集：序号 17 识别为 平台")
	_check(_chase._类型[_chase.取元素(1)] == "鼓", "收集：序号 1 识别为 鼓")
	_check(_chase._类型[_chase.取元素(10)] == "墙", "收集：序号 10（墙分组）识别为 墙")

	# 掉落惩罚去掉之后，这些导出项与内部状态都不该再存在
	_check(_chase.get("地面站立Y") == null, "简化：`地面站立Y` 已移除（落地不再判摔）")
	_check(_chase.get("落点容差") == null, "简化：`落点容差` 已移除")
	_check(_chase.get("无锚点横向偏移") == null, "简化：`无锚点横向偏移` 已移除")
	_check(_chase.get("_锚点") == null, "简化：`_锚点` 已移除（不再记录上一个碰撞平台）")
	_check(_chase.get("_已武装") == null, "简化：`_已武装` 已移除")
	_check(_chase.get("掉落宽限") != null, "简化：`掉落宽限` 保留（只服务二阶段掉出视口）")

	_检查背景层结构()


## 二阶段背景的**结构**：单层、初始隐藏、在背景层、排在 背景压暗遮罩 之后
func _检查背景层结构() -> void:
	var 背景 := _lvl.get_node_or_null("二阶段背景") as Sprite2D
	_check(背景 != null, "背景层：`二阶段背景` 存在于 4_1")
	if 背景 == null:
		return
	_check(not 背景.visible, "背景层：初始是隐藏的")
	_check(背景.z_index == -1, "背景层：z_index = -1（在背景层，不压平台与玩家）")
	_check(背景.texture != null, "背景层：贴图已挂")
	# 两层合一的验收：旧的两个节点都不该在了
	_check(_lvl.get_node_or_null("二阶段背景_细血丝") == null,
		"背景层：旧的 `二阶段背景_细血丝` 节点已不存在（已合并）")
	_check(_lvl.get_node_or_null("二阶段背景_边缘危险带") == null,
		"背景层：旧的 `二阶段背景_边缘危险带` 节点已不存在（已合并）")

	var 序 := {}
	for i in _lvl.get_child_count():
		序[_lvl.get_child(i).name] = i
	_check(int(序.get("背景压暗遮罩", -1)) < int(序.get("二阶段背景", -1)),
		"背景层：排在 背景压暗遮罩 之后（盖住被压暗的音乐厅）")
	_check(int(序.get("二阶段背景", 999)) < int(序.get("跳跳乐", -1)),
		"背景层：排在 跳跳乐 之前（在平台与玩家之下）")


# ──────────────────────────── 初始全隐藏 ────────────────────────────


func _检查初始全隐藏() -> void:
	if _chase == null:
		return
	var s := _状态()
	_check(s["游标"] == 0, "初始：游标为 0")
	_check(s["显示"].is_empty(),
		"初始：**所有跳跳乐元素都不出现**（一阶段战斗期间一点都不露）（实际 %s）" % str(s["显示"]))
	_check(not _碰撞开着(1), "初始：序号 1 的碰撞也关着")
	_check(_chase.追逐中 == false, "初始：还没进追逐段")

	_踩(5)
	_check(_状态()["显示"].is_empty(), "初始：追逐未开始时踩元素不浮现任何东西")


# ──────────────────────────── 浮现只增不减 ────────────────────────────


func _检查浮现只增不减() -> void:
	if _chase == null:
		return
	_chase.开始追逐()
	var s := _状态()
	_check(_chase.追逐中 == true, "追逐：开始追逐后状态位置位")
	_check(s["显示"] == [1, 2], "追逐：开始追逐才浮现 1、2（实际 %s）" % str(s["显示"]))

	_踩(1)
	s = _状态()
	_check(s["游标"] == 1, "浮现：踩 1 之后游标 = 1")
	_check(s["显示"] == [1, 2, 3], "浮现：显示 1、2、3（实际 %s）" % str(s["显示"]))

	_踩(2)
	s = _状态()
	_check(s["显示"] == [1, 2, 3, 4],
		"浮现：碰 2 之后显示 1、2、3、4 —— **1 不再被收掉**（实际 %s）" % str(s["显示"]))

	# ★ 回归断言：作者实机踩到的 bug（"还没碰到就消失了"）
	await _等一帧()
	var 都还在 := true
	var 缺 := []
	for k in [3, 4]:
		var e: Node2D = _chase.取元素(k)
		if e == null or not e.visible or not _碰撞开着(k):
			都还在 = false
			缺.append(k)
	_check(都还在, "★ 回归：踩到 2 之后，还没碰到的 3、4 仍然可见且碰撞开着（缺 %s）" % str(缺))
	_check(_碰撞开着(1), "★ 回归：已经踩过的 1 也没有被抽掉（浮现只增不减）")

	# 擦到墙（序号 10）不应该让任何东西消失 —— 这正是当初踩空的根因
	var 前: Array = _状态()["显示"].duplicate()
	_踩(10)
	await _等一帧()
	var 后: Array = _状态()["显示"]
	var 少了 := false
	for k in 前:
		if not (k in 后):
			少了 = true
	_check(not 少了, "★ 回归：擦到墙（序号 10）之后，之前的元素一个都没少（%s → %s）"
		% [str(前), str(后)])


# ──────────────────────────── 爬满全场 ────────────────────────────


func _检查爬满全场() -> void:
	if _chase == null:
		return
	var 序列: Array[int] = []
	for k in range(1, 19):
		_踩(k)
		序列.append(_状态()["显示"].size())
	var 掉过 := false
	for i in range(1, 序列.size()):
		if 序列[i] < 序列[i - 1]: 掉过 = true
	_check(not 掉过, "爬升：一路踩到 18，可见数量单调不减（各步可见数 %s）" % str(序列))
	var s := _状态()
	_check(s["显示"].size() == 18, "爬升：18 个元素全部可见（实际 %d）" % s["显示"].size())
	_check(s["游标"] == 18, "爬升：游标到 18")
	await _等一帧()
	_check(_碰撞开着(1) and _碰撞开着(18), "爬升：首尾两个的碰撞都开着")


# ──────────────────────────── 落地无惩罚（本轮改的重点） ────────────────────────────


func _检查落地无事() -> void:
	if _chase == null:
		return
	_player.restore_full_hp()
	_player.invincible_timer = 0.0
	var hp0: int = _player.hp
	var 游标0: int = int(_状态()["游标"])
	var 显示0: int = int(_状态()["显示"].size())

	# 把玩家丢到最底层地面上（1.5 期间这就是"摔下去了"）
	_player.global_position = Vector2(800.0, 3369.0)
	_player.velocity = Vector2.ZERO
	await _等一帧()
	await _等一帧()

	_check(_player.hp == hp0, "落地无事：摔到地面**不扣血**（%d → %d）" % [hp0, _player.hp])
	_check(absf(_player.global_position.y - 3369.0) < 24.0,
		"落地无事：没有被强行传送到别处（y = %.0f）" % _player.global_position.y)
	_check(absf(_player.global_position.x - 800.0) < 24.0,
		"落地无事：也没有被横向挪走（x = %.0f）" % _player.global_position.x)
	_check(int(_状态()["游标"]) == 游标0,
		"落地无事：游标不回退（%d → %d）" % [游标0, int(_状态()["游标"])])
	_check(int(_状态()["显示"].size()) == 显示0,
		"落地无事：已浮现的元素一个都不消失（%d → %d）"
		% [显示0, int(_状态()["显示"].size())])

	# 连续几次也不该有任何变化（早期版本会连环扣血）
	for _i in 5:
		_player.global_position = Vector2(800.0, 3369.0)
		await get_tree().physics_frame
	_check(_player.hp == hp0, "落地无事：反复落地也不扣血（%d → %d）" % [hp0, _player.hp])


# ──────────────────────────── 二阶段 ────────────────────────────


func _检查二阶段() -> void:
	if _chase == null:
		return
	await _等一帧()
	_chase.进入二阶段()
	await _等一帧()
	var s := _状态()
	_check(s["显示"].is_empty(),
		"二阶段：所有参与浮现的元素一起消失（实际 %s）" % str(s["显示"]))
	_check(not _碰撞开着(1), "二阶段：序号 1 的碰撞也关了")
	_check(not _碰撞开着(9), "二阶段：序号 9（平台）的碰撞也关了")
	_check(_区域相等(s["区域矩形"]),
		"二阶段：区域矩形 = 期望 %s（实际 %s）" % [str(期望区域), str(s["区域矩形"])])
	_check(_chase.二阶段 == true, "二阶段：状态位已置位")
	_check(_chase.追逐中 == false, "二阶段：追逐中 已关闭")

	var 背景 := _lvl.get_node_or_null("二阶段背景") as Sprite2D
	_check(背景 != null and 背景.visible, "二阶段：单层背景已显示")

	# ── 背景压暗（设计稿 §9 原本写好、一直没接的一环）──
	#    透明血丝层叠在**压暗后**的音乐厅上才显眼；实测压暗把远景墙亮度 75.5 → 34.2。
	var 遮罩 := _lvl.get_node_or_null("背景压暗遮罩")
	_check(遮罩 != null and 遮罩.has_method("是否变暗"),
		"二阶段：找得到 背景压暗遮罩 且它有 是否变暗 接口")
	if 遮罩 != null and 遮罩.has_method("是否变暗"):
		_check(bool(遮罩.call("是否变暗")), "二阶段：背景压暗已打开")

	# ── 镜头 limits 必须收到二阶段区域 ──
	#    一阶段的 ArenaLock 会把 limits 夹到竞技场（y 2880~3600），而二阶段区域在
	#    y 205~925 —— 只改相机位置、不改 limits 的话镜头会被夹回下面那个房间，
	#    二阶段区域根本进不了画面，而且**完全不报错**（背景层看着"没生效"）。
	var 相机 := _相机()
	if 相机 != null:
		_check(相机.limit_left == int(期望区域.position.x)
			and 相机.limit_right == int(期望区域.end.x)
			and 相机.limit_top == int(期望区域.position.y)
			and 相机.limit_bottom == int(期望区域.end.y),
			"二阶段：镜头 limits 收到区域 %s（实际 %d~%d / %d~%d）"
			% [str(期望区域), 相机.limit_left, 相机.limit_right,
			  相机.limit_top, 相机.limit_bottom])
		_check(相机.limit_top < 2880,
			"二阶段：limit_top 已脱离竞技场（%d < 2880，否则镜头还在下面那个房间）"
			% 相机.limit_top)

	# 退出后 limits 必须还原（不然回到一阶段会被锁在二阶段的框里）。
	# ⚠️ 退出是 0.6s 的镜头补间，limits 在补间**结束的回调里**才还原 ——
	#    提前还原会把回程补间夹在半路。所以这里要等补间走完，不能只等两帧。
	_chase.退出二阶段()
	var 还原了 := false
	for _i in 200:
		await get_tree().physics_frame
		if 相机 == null or 相机.limit_top != int(期望区域.position.y):
			还原了 = true
			break
	_check(还原了, "二阶段：退出后 limits 已还原（limit_top=%d）"
		% (相机.limit_top if 相机 != null else -1))
	if 遮罩 != null and 遮罩.has_method("是否变暗"):
		_check(not bool(遮罩.call("是否变暗")), "二阶段：退出后背景压暗已关闭")
	_chase.进入二阶段()      # 还原状态，别影响后面的断言
	await _等一帧()


# ──────────────────────────── 二阶段掉落 + 物理轮询 ────────────────────────────


func _检查物理轮询() -> void:
	if _chase == null:
		return
	# 二阶段掉出视口 → 扣 1 血 + 在战斗层平台重生（这条保留：边缘危险带就是它的提示）
	_player.invincible_timer = 0.0
	_player.restore_full_hp()
	_chase._宽限 = 0.0
	var hp0: int = _player.hp
	_player.global_position = Vector2(1340.0, 期望区域.end.y + 200.0)
	_chase._判掉出视口()
	_check(_player.hp == hp0 - 1, "二阶段掉落：掉出视口扣 1 血（%d → %d）" % [hp0, _player.hp])
	_check(期望区域.has_point(_player.global_position),
		"二阶段掉落：在战斗区域内的平台上方重生（实际 %s）" % str(_player.global_position))
	_check(_chase._宽限 > 0.0, "二阶段掉落：重生后有宽限时间")

	# 物理轮询：让玩家真站在爬升段的平台 9 上，看管理器能否认出"脚下"
	_chase.退出二阶段()
	_chase.重新收集()
	_chase.开始追逐()
	_踩(9)
	await _等一帧()
	var 台: Node2D = _chase.取元素(9)
	_check(台 != null and (台 as CollisionObject2D).collision_layer != 0,
		"物理轮询：平台 9 已浮现且碰撞恢复")
	_player.global_position = 台.global_position + Vector2(0.0, -13.0 - 57.0 - 4.0)
	_player.velocity = Vector2.ZERO
	_player.invincible_timer = 0.0
	for _i in 14:
		await get_tree().physics_frame
	_check(_chase._游标 >= 9, "物理轮询：站上去后游标 ≥ 9（实际 %d）" % _chase._游标)
	_check(_碰撞开着(9), "物理轮询：站上去的平台仍存在（不会被抽掉）")


func _区域相等(a: Rect2) -> bool:
	return absf(a.position.x - 期望区域.position.x) < 0.5 \
		and absf(a.position.y - 期望区域.position.y) < 0.5 \
		and absf(a.size.x - 期望区域.size.x) < 0.5 \
		and absf(a.size.y - 期望区域.size.y) < 0.5
