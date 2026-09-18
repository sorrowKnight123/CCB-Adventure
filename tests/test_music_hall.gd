extends Node2D
## 音乐厅 4_1 的自检（headless，场景模式 —— `--script` 不加载 autoload）。
## 运行：godot --headless --path . res://tests/test_music_hall.tscn --quit-after 9000
##
## 覆盖：
##   结构   —— 地面碰撞顶边 ≈1270；左右隐形墙与天花板都在（玩家跑不出房间）
##   背景   —— Back/back 视差 0.45 + repeat 2172×3；Back/plat 1:1（地面美术层）
##   接线   —— 4_1 的门 → 3_1 的 spawn `4_1-3_1`；3_1 的门 → 4_1、spawn `3_1-4_1`（读 3_1 文本核对）
##   可达性 —— **从场景读**每个元素的落点，判断"能否从下面某个落点上得来"，
##             打出一张表（作者改完位置跑一次就能核对）；上不去才失败
##   单向平台 —— 同列上下两块平台间距 > 116（`agent.md:273` 铁律）
##
## ⚠️ 不写死坐标：位置全部来自场景节点的 `metadata/landing`，所以你增删、移动元素之后自检依然有效。

const LEVEL := preload("res://scenes/levels/music_hall/4_1.tscn")
const 三关文本 := "res://scenes/levels/3_moss/3_1.tscn"

## 玩家能力（实测值，用来判定"跳得上去吗"；留了余量）
const 二段跳高 := 240.0        # 单跳 150 + 二段跳 150
const 跳鼓高 := 204.0          # 踩鼓弹起 ~204（700²/(2·1200)）
const 横向跳距 := 320.0        # 弹起后空中横移约 280，留余量
const 长缺口上限 := 900.0      # 超过这个距离连飞行都嫌长，视为设计错误
const 地面_y := 3426.0      # 房间改成 2×5 格后，地面落到最下一格
## 贴图实际宽度（用来算"边到边"的间隙；平台预制体把 398 缩到了 0.5）
const 平台宽 := 196.0
const 鼓宽 := 120.0
const 单向平台间距 := 116.0    # 铁律

var _p := 0
var _f := 0


func _ready() -> void:
	var lvl: Node2D = LEVEL.instantiate()
	add_child(lvl)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_检查结构(lvl)
	_检查背景(lvl)
	_检查接线(lvl)
	_检查鼓声(lvl)
	_检查单向平台(lvl)
	_检查可达性(lvl)
	print("\n===== 音乐厅 4_1 自检结果：通过 %d / 失败 %d =====" % [_p, _f])
	get_tree().quit(0 if _f == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok: _p += 1; print("[PASS] " + what)
	else: _f += 1; print("[FAIL] " + what)


# ──────────────────────────── 结构 ────────────────────────────


func _检查结构(lvl: Node) -> void:
	var ground := lvl.get_node_or_null("tile/Ground") as StaticBody2D
	_check(ground != null, "结构：地面 StaticBody2D 存在")
	if ground != null:
		var cs := ground.get_node("CollisionShape2D") as CollisionShape2D
		var rect := cs.shape as RectangleShape2D
		var top := ground.position.y - rect.size.y * 0.5
		_check(absf(top - 地面_y) <= 2.0, "结构：地面碰撞顶边 = %.1f（期望 ≈%.0f）" % [top, 地面_y])
		_check(ground.collision_layer == 1, "结构：地面在物理层 1（实心）")
	var gf := lvl.get_node_or_null("GameFlow")
	_check(gf != null and int(gf.get("camera_bottom")) == 3600, "结构：相机下边界 = 3600（五格高）")
	var dim := lvl.get_node_or_null("背景压暗遮罩") as ColorRect
	_check(dim != null, "变暗：遮罩节点存在")
	if dim != null:
		_check(is_zero_approx(dim.color.a), "变暗：默认是关的（alpha=0）")
		_check(dim.z_index > -2 and dim.z_index < 0, "变暗：夹在背景(z=-2)与跳跳乐(z=0)之间（只压暗背景）")
		_check(dim.has_method("设置变暗"), "变暗：对外提供 设置变暗() 方法")
	_check(_背景覆盖(lvl), "背景：贴图高度覆盖整间房（3600）")
	for n in ["tile/WallLeft", "tile/WallRight", "tile/Ceiling"]:
		var b := lvl.get_node_or_null(n) as StaticBody2D
		_check(b != null and b.collision_layer == 1, "结构：%s 存在且为实心（拦得住玩家）" % n)
	_check(lvl.get_node_or_null("Door/4_1-3_1") != null, "结构：回程门 4_1-3_1 存在")
	var player := lvl.get_node_or_null("Player") as CharacterBody2D
	_check(player != null and (player.collision_mask & 16) != 0, "结构：玩家掩码含 16（能站上单向平台）")


# ──────────────────────────── 背景 ────────────────────────────


func _检查背景(lvl: Node) -> void:
	var b := lvl.get_node_or_null("Back/back") as Parallax2D
	var p := lvl.get_node_or_null("Back/plat") as Parallax2D
	_check(b != null and absf(b.scroll_scale.x - 0.45) < 0.01, "背景：远层 scroll_scale=0.45")
	if b != null:
		_check(absf(b.repeat_size.x - 2172.0) < 1.0 and b.repeat_times == 3,
			"背景：远层 repeat_size=2172 / times=3（镜像图一个周期）")
	_check(p != null and absf(p.scroll_scale.x - 1.0) < 0.01, "背景：地面美术层 1:1 跟镜头")


# ──────────────────────────── 接线 ────────────────────────────


func _检查接线(lvl: Node) -> void:
	var door := lvl.get_node_or_null("Door/4_1-3_1") as Area2D
	if door != null:
		_check(str(door.get("target_scene")).ends_with("3_moss/3_1.tscn"), "接线：4_1 的门指向 3_1")
		_check(str(door.get("target_spawn_id")) == "4_1-3_1", "接线：4_1 的门用 spawn id 4_1-3_1")
	var 有落点 := false
	var sp := lvl.get_node_or_null("SpawnPoints")
	if sp != null:
		for c in sp.get_children():
			if str(c.get("id")) == "3_1-4_1": 有落点 = true
	_check(有落点, "接线：4_1 里有落点 spawn id = 3_1-4_1")

	var f := FileAccess.open(三关文本, FileAccess.READ)
	var txt := f.get_as_text() if f != null else ""
	_check(txt.contains("res://scenes/levels/music_hall/4_1.tscn"), "接线：3_1 里有门指向 4_1.tscn")
	_check(txt.contains('target_spawn_id = "3_1-4_1"'), "接线：3_1 的门目标 spawn = 3_1-4_1")
	_check(txt.contains('id = "4_1-3_1"'), "接线：3_1 里有 spawn 4_1-3_1（从大厅回来落脚）")


# ──────────────────────────── 鼓声 ────────────────────────────


func _检查鼓声(lvl: Node) -> void:
	## 鼓声必须**每面鼓只有一个音**（作者定的"鼓声全用 kick"，不允许随机）。
	##
	## 这个坑**复发过一次**：鼓实例身上如果带一个空的 `音效列表` 覆盖（在编辑器里保存场景时会写出来），
	## HallDrum 就会退回"多个占位音里随机取一个"，听起来就是鼓声随机。
	## 所以这里永久盯住：只要哪面鼓的音效列表不是"恰好 1 个"，就判失败。
	var 鼓: Array = []
	for n in lvl.find_children("*", "", true, false):
		if str(n.name).begins_with("鼓") and n.get("音效列表") != null:
			鼓.append(n)
	if 鼓.is_empty():
		_check(false, "鼓声：场景里一个鼓都没找到")
		return
	var 坏: Array = []
	var 流派: Array = []
	for n in 鼓:
		var 列表: Array = n.get("音效列表")
		if 列表.size() != 1:
			坏.append("%s 有 %d 个音" % [n.name, 列表.size()])
		else:
			流派.append((列表[0] as AudioStream).resource_path.get_file())
	_check(坏.is_empty(), "鼓声：%d 面鼓全部只有一个音（不允许随机）%s"
		% [鼓.size(), "" if 坏.is_empty() else "　异常：" + ", ".join(坏)])
	var 唯一 := {}
	for s in 流派: 唯一[s] = true
	_check(唯一.size() <= 1, "鼓声：所有鼓用的是同一个音（实际：%s）" % ", ".join(唯一.keys()))


# ──────────────────────────── 单向平台 ────────────────────────────


func _元素(lvl: Node) -> Array:
	## 从场景读：[名字, 落点, 类型, 宽度]
	var out := []
	for n in lvl.find_children("*", "", true, false):
		if not n.has_meta("landing"):
			continue
		var 是鼓 := str(n.name).begins_with("鼓")
		out.append([str(n.name), n.get_meta("landing"),
			("drum" if 是鼓 else "plat"), (鼓宽 if 是鼓 else 平台宽)])
	return out


func _检查单向平台(lvl: Node) -> void:
	var plats := []
	for e in _元素(lvl):
		if e[2] == "plat": plats.append(e)
	var bad := 0
	for i in plats.size():
		for j in range(i + 1, plats.size()):
			var dy: float = absf(plats[i][1].y - plats[j][1].y)
			if absf(plats[i][1].x - plats[j][1].x) < 平台宽 and dy <= 单向平台间距:
				bad += 1
				print("      ↳ %s 与 %s 竖向只差 %.0f（同列，会一次穿多层）" % [plats[i][0], plats[j][0], dy])
	_check(bad == 0, "单向平台：同列平台竖向间距全部 > %.0f（%d 处违例）" % [单向平台间距, bad])


# ──────────────────────────── 可达性（核心） ────────────────────────────


func _检查可达性(lvl: Node) -> void:
	## 从地面做 BFS：向上要"跳/踩鼓弹/飞"够得着，向下则"掉下去"就行（下落是免费的）——
	## 这样战斗层最下面那几块（要靠从上面掉下来）也能正确判成可达。
	var 全部 := _元素(lvl)
	var 节点 := [["地面", Vector2(0.0, 地面_y), "plat", 99999.0]]
	节点.append_array(全部)
	var 可达 := {0: ["起点", "地面"]}
	var 变化 := true
	while 变化:
		变化 = false
		for i in 节点.size():
			if 可达.has(i): continue
			var 点: Vector2 = 节点[i][1]
			var 宽: float = 节点[i][3]
			for j in 节点.size():
				if i == j or not 可达.has(j): continue
				var c = 节点[j]
				var gap: float = maxf(0.0, absf(点.x - c[1].x) - (宽 + c[3]) * 0.5)
				# ⚠️ y 轴向下增大：dy>0 = 借力点在下面 → 要"往上够"；dy<0 = 借力点在上面 → "掉下去"即可
				var dy: float = c[1].y - 点.y
				var 方式 := ""
				# dy = 借力点.y - 目标.y：> 0 表示借力点在下面 → 要"往上够"
				var 上: float = dy
				var 上限: float = 跳鼓高 if c[2] == "drum" else 二段跳高
				if gap <= 1.0 and absf(dy) <= 20.0:
					方式 = "就在 %s 上" % c[0]
				elif 上 > 0.0:
					if 上 <= 上限 + 1.0 and gap <= 横向跳距:
						方式 = ("踩 %s 弹起" % c[0]) if c[2] == "drum" else ("从 %s 跳上" % c[0])
					elif 上 <= 80.0 and gap <= 长缺口上限:
						方式 = "华彩终章从 %s 飞越" % c[0]
				else:
					if gap <= 横向跳距:
						方式 = "从 %s 下落" % c[0]
					elif absf(dy) <= 80.0 and gap <= 长缺口上限:
						方式 = "华彩终章从 %s 飞越" % c[0]
				if 方式 != "":
					可达[i] = [c[0], 方式]
					变化 = true
					break
	print("
──── 跳跳乐可达性表（自下而上的推进结果）────")
	print("%-8s %-16s %s" % ["元素", "落点", "怎么到的"])
	var 失败 := 0
	for i in range(1, 节点.size()):
		if 可达.has(i):
			print("%-8s %-16s %s" % [节点[i][0], str(节点[i][1]), 可达[i][1]])
		else:
			print("%-8s %-16s ✗ 无法到达" % [节点[i][0], str(节点[i][1])])
			失败 += 1
	print("──────────────────────────────")
	_check(失败 == 0, "可达性：全部 %d 个元素都能到达（%d 个到不了）" % [节点.size() - 1, 失败])


func _背景覆盖(lvl: Node) -> bool:
	var s := lvl.get_node_or_null("Back/back/Sprite") as Sprite2D
	if s == null: return false
	return s.texture.get_height() >= 3600.0 and s.position.y - s.texture.get_height() * 0.5 <= 1.0
