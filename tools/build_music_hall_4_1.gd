extends Node
## 生成音乐厅 4_1 场景（一次性工具）。
## 运行：godot --headless --path . res://tools/build_music_hall_4_1.tscn
## （必须走场景模式：`--script` 不加载 autoload，GameState/AudioManager 都不存在）
##
## 为什么用脚本搭：4_1 里有 28 个跳跳乐实例 + 背景/碰撞/UI/门/spawn，
## 手写 .tscn 容易错行；照 `tools/build_school1_room.gd` 的先例 —— 建节点树再 pack + save。
## 生成之后**布局就是场景里的普通节点**，之后全部改由作者在编辑器里拖（脚本不再参与）。
##
## ⚠️ 位置表里的 y 是「落脚面」的高度；平台/鼓的节点原点要按各自贴图高度下移，
##    换算在 _place() 里做（平台顶面 = 节点 y-26；鼓面 = 节点 y-31）。

const OUT := "res://scenes/levels/music_hall/4_1.tscn"

const PLATFORM := preload("res://scenes/props/music_hall/HallPlatform.tscn")
const WALL := preload("res://scenes/props/music_hall/HallWall.tscn")
const DRUM := preload("res://scenes/props/music_hall/HallDrum.tscn")
const PLAYER := preload("res://scenes/player/Player.tscn")
const GAMEFLOW := preload("res://scripts/game/GameFlow.gd")
const SPAWNP := preload("res://scripts/game/SpawnPoint.gd")
const DOOR := preload("res://scripts/game/Door.gd")
const HUD := preload("res://scenes/ui/HUD.tscn")
const PAUSE := preload("res://scenes/ui/PauseMenu.tscn")
const ENDING := preload("res://scenes/ui/EndingScreen.tscn")
const MINIMAP := preload("res://addons/MetroidvaniaSystem/Template/Nodes/Minimap.tscn")
const ROOMINST := preload("res://addons/MetroidvaniaSystem/Nodes/RoomInstance.tscn")
const BACK_TEX := preload("res://art/level/7_music_hall/hall_back_tall5.png")
const PLAT_TEX := preload("res://art/level/7_music_hall/hall_platform_mirror.png")

const 房间宽 := 2560.0
const 房间高 := 3600.0        # 2 格宽 × 5 格高（MetSys 第五分组）
const 地面顶边 := 3426.0      # 底层那一格的地面（原 1270 + 2 格 2152）
const 单幅宽 := 1086.0

## (段, 类型, 序号, 落脚面 x, 落脚面 y)  —— 顺序即示意图上的 J1..J16 / P1..P11
const 布局 := [
	# 段1/段2：上行段 —— 从底层地面一路踩鼓爬到最上面两格（每 5 件插一块休息平台，左右交替成串）
	# 起步：鼓01 在底层地面上
	["段1_起步", "drum", 1, 400.0, 3426.0],
	["段1_起步", "drum", 2, 620.0, 3314.0],
	["段1_起步", "drum", 3, 880.0, 3202.0],
	["段1_起步", "drum", 4, 620.0, 3090.0],
	["段1_起步", "drum", 5, 880.0, 2978.0],
	# 上行段
	["段2_上行段", "plat", 1, 880.0, 2866.0],
	["段2_上行段", "drum", 6, 880.0, 2754.0],
	["段2_上行段", "drum", 7, 620.0, 2642.0],
	["段2_上行段", "drum", 8, 880.0, 2530.0],
	["段2_上行段", "drum", 9, 620.0, 2418.0],
	["段2_上行段", "plat", 2, 620.0, 2306.0],
	["段2_上行段", "drum", 10, 620.0, 2194.0],
	["段2_上行段", "drum", 11, 880.0, 2082.0],
	["段2_上行段", "drum", 12, 620.0, 1970.0],
	["段2_上行段", "drum", 13, 880.0, 1858.0],
	["段2_上行段", "plat", 3, 880.0, 1746.0],
	["段2_上行段", "drum", 14, 880.0, 1634.0],
	["段2_上行段", "drum", 15, 620.0, 1522.0],
	["段2_上行段", "drum", 16, 880.0, 1410.0],
	["段2_上行段", "drum", 17, 620.0, 1298.0],
	["段2_上行段", "plat", 4, 620.0, 1186.0],
	["段2_上行段", "drum", 18, 620.0, 1074.0],
	["段2_上行段", "drum", 19, 880.0, 962.0],
	["段2_上行段", "drum", 20, 620.0, 850.0],
	["段2_上行段", "plat", 5, 620.0, 738.0],
	["段2_上行段", "plat", 6, 150.0, 600.0],
	# 上行段
	# 段3：二阶段战斗层 —— 放在最上两格的【中央】，整齐交错（平台只在 y=120/360/600 三行）
	["段3_战斗层", "drum", 21, 1000.0, 700.0],
	["段3_战斗层", "drum", 22, 1300.0, 700.0],
	["段3_战斗层", "drum", 23, 1600.0, 700.0],
	["段3_战斗层", "drum", 24, 1000.0, 480.0],
	["段3_战斗层", "drum", 25, 1300.0, 480.0],
	["段3_战斗层", "drum", 26, 1600.0, 480.0],
	["段3_战斗层", "drum", 27, 1000.0, 240.0],
	["段3_战斗层", "drum", 28, 1300.0, 240.0],
	["段3_战斗层", "drum", 29, 1600.0, 240.0],
	["段3_战斗层", "plat", 7, 900.0, 600.0],
	["段3_战斗层", "drum", 30, 1150.0, 600.0],
	["段3_战斗层", "plat", 8, 1400.0, 600.0],
	["段3_战斗层", "drum", 31, 1650.0, 600.0],
	["段3_战斗层", "plat", 9, 900.0, 360.0],
	["段3_战斗层", "drum", 32, 1150.0, 360.0],
	["段3_战斗层", "plat", 10, 1400.0, 360.0],
	["段3_战斗层", "drum", 33, 1650.0, 360.0],
	["段3_战斗层", "plat", 11, 900.0, 120.0],
	["段3_战斗层", "drum", 34, 1150.0, 120.0],
	["段3_战斗层", "plat", 12, 1400.0, 120.0],
	["段3_战斗层", "drum", 35, 1650.0, 120.0],
]

var _root: Node2D


func _ready() -> void:
	_root = Node2D.new()
	_root.name = "MusicHall4_1"

	_背景()
	_地面与边界()
	_跳跳乐()
	_流程与玩家()
	_界面()

	var packed := PackedScene.new()
	packed.pack(_root)
	var err := ResourceSaver.save(packed, OUT)
	print("保存 %s -> err=%d" % [OUT, err])
	# ⚠️ pack() 会把实例上"跟类默认值不同"的属性写进场景（比如预制体里配好的 音效列表），
	# 于是以后改预制体就不生效了（踩过：鼓声一直随机）。这里保存后剥掉这类覆盖，让实例只吃预制体。
	剥掉实例上多余覆盖()
	get_tree().quit(0 if err == OK else 1)


func 剥掉实例上多余覆盖() -> void:
	var f := FileAccess.open(OUT, FileAccess.READ)
	if f == null: return
	var 行 := f.get_as_text().split("
"); f.close()
	var 脏 := ["\"音效列表\" =", "texture = ExtResource(", "script = ExtResource("]
	var 留 := []
	for l in 行:
		var 去掉 := false
		for k in 脏:
			if l.begins_with(k): 去掉 = true
		if not 去掉: 留.append(l)
	var w := FileAccess.open(OUT, FileAccess.WRITE)
	w.store_string("
".join(留)); w.close()
	print("剥掉实例覆盖后行数 %d -> %d" % [行.size(), 留.size()])


func _add(node: Node, parent: Node) -> Node:
	parent.add_child(node)
	node.owner = _root
	return node


func _背景() -> void:
	var back := _add(Node2D.new(), _root) as Node2D
	back.name = "Back"
	var p := _add(Parallax2D.new(), back) as Parallax2D
	p.name = "back"                       # 视差背景：墙 + 包厢 + 吊灯 + 拱门 + 幕布 + 管风琴
	p.scroll_scale = Vector2(0.45, 1.0)
	p.repeat_size = Vector2(单幅宽 * 2.0, 0.0)
	p.repeat_times = 3
	p.z_index = -2
	var s := _add(Sprite2D.new(), p) as Sprite2D
	s.name = "Sprite"
	s.texture = BACK_TEX
	s.position = Vector2(1086.0, 房间高 * 0.5)      # 2172x3600，左边缘对齐 x=0、顶边对齐 y=0

	var plat := _add(Parallax2D.new(), back) as Parallax2D
	plat.name = "plat"                    # 地面美术层：1:1 跟镜头（scroll 1 = 无视差）
	plat.scroll_scale = Vector2(1.0, 1.0)
	plat.repeat_size = Vector2(单幅宽 * 2.0, 0.0)
	plat.repeat_times = 3
	plat.z_index = -1
	var ps := _add(Sprite2D.new(), plat) as Sprite2D
	ps.name = "Sprite"
	ps.texture = PLAT_TEX
	ps.position = Vector2(1086.0, 2876.0)           # 台面顶边(贴图 y1274) 落在世界 y=3426


func _地面与边界() -> void:
	# 压暗遮罩：z 在背景(z=-2)之上、跳跳乐(z=0)之下 —— 只压暗背景，平台不受影响
	var dim := _add(ColorRect.new(), _root) as ColorRect
	dim.name = "背景压暗遮罩"
	dim.position = Vector2.ZERO
	dim.size = Vector2(房间宽, 房间高)
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = -1
	dim.set_script(preload("res://scripts/props/HallBackdropDim.gd"))

	var tile := _add(Node2D.new(), _root) as Node2D
	tile.name = "tile"
	_静态矩形(tile, "Ground", 房间宽 * 0.5 + 200.0, 地面顶边 + 55.0, 房间宽 + 400.0, 110.0)
	_静态矩形(tile, "WallLeft", -21.0, 房间高 * 0.5, 42.0, 房间高 + 400.0)
	_静态矩形(tile, "WallRight", 房间宽 + 21.0, 房间高 * 0.5, 42.0, 房间高 + 400.0)
	_静态矩形(tile, "Ceiling", 房间宽 * 0.5, -21.0, 房间宽 + 400.0, 42.0)


func _静态矩形(parent: Node, node_name: String, x: float, y: float, w: float, h: float) -> void:
	var body := _add(StaticBody2D.new(), parent) as StaticBody2D
	body.name = node_name
	body.position = Vector2(x, y)
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := _add(CollisionShape2D.new(), body) as CollisionShape2D
	cs.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, h)
	cs.shape = rect


func _跳跳乐() -> void:
	var root := _add(Node2D.new(), _root) as Node2D
	root.name = "跳跳乐"
	var 段: Dictionary = {}
	var 计数 := {"drum": 0, "plat": 0}
	for row in 布局:
		var 段名: String = row[0]
		if not 段.has(段名):
			段[段名] = _add(Node2D.new(), root)
			段[段名].name = 段名
		计数[row[1]] += 1
		var 序号 := int(计数[row[1]])
		var 名 := ("鼓%02d" % 序号) if row[1] == "drum" else ("平台%02d" % 序号)
		_place(段[段名], row[1], 名, float(row[3]), float(row[4]))
	# 墙片：**只放这一个模板节点**（作者自己复制到需要的位置）——立在右下格地面上
	var 墙根 := _add(Node2D.new(), root)
	墙根.name = "墙片模板（复制这个）"
	var w := _add(WALL.instantiate(), 墙根) as Node2D
	w.name = "墙片01"
	w.position = Vector2(1600.0, 地面顶边 - 227.0 * 0.5)
	w.add_to_group("跳跳乐")


func _place(parent: Node, kind: String, node_name: String, x: float, y: float) -> void:
	var node: Node2D
	if kind == "drum":
		node = _add(DRUM.instantiate(), parent) as Node2D
		node.position = Vector2(x, y + 31.0)     # 鼓面在节点上方 31px
	else:
		node = _add(PLATFORM.instantiate(), parent) as Node2D
		node.position = Vector2(x, y + 13.0)     # 平台顶面在节点上方 13px（贴图缩到 0.5 后）
	node.name = node_name
	node.add_to_group("跳跳乐")
	node.set_meta("landing", Vector2(x, y))   # 自检读这个：元素的落脚面坐标（ASCII 键名，Godot 的 meta 不接受非 ASCII）


func _流程与玩家() -> void:
	var gf := _add(Node.new(), _root) as Node
	gf.name = "GameFlow"
	gf.set_script(GAMEFLOW)
	gf.set("camera_left", 0)
	gf.set("camera_right", int(房间宽))
	gf.set("camera_top", 0)
	gf.set("camera_bottom", int(房间高))

	var spawns := _add(Node2D.new(), _root) as Node2D
	spawns.name = "SpawnPoints"
	var sp := _add(Marker2D.new(), spawns) as Marker2D
	sp.name = "3_1-4_1"
	sp.position = Vector2(240.0, 地面顶边 - 57.0)
	sp.set_script(SPAWNP)
	sp.set("id", "3_1-4_1")

	var doors := _add(Node2D.new(), _root) as Node2D
	doors.name = "Door"
	var door := _add(Area2D.new(), doors) as Area2D
	door.name = "4_1-3_1"
	door.position = Vector2(58.0, 地面顶边 - 110.0)
	door.collision_layer = 0
	door.collision_mask = 2
	door.set_script(DOOR)
	door.set("target_scene", "res://scenes/levels/3_moss/3_1.tscn")
	door.set("target_spawn_id", "4_1-3_1")
	var dcs := _add(CollisionShape2D.new(), door) as CollisionShape2D
	dcs.name = "CollisionShape2D"
	var drect := RectangleShape2D.new()
	drect.size = Vector2(70.0, 260.0)
	dcs.shape = drect

	var player := _add(PLAYER.instantiate(), _root) as CharacterBody2D
	player.name = "Player"
	player.position = Vector2(240.0, 地面顶边 - 57.0)
	player.collision_mask = 49            # 与 3_1 一致：1(地形) + 16(单向平台) + 32


func _界面() -> void:
	var ui := _add(Node.new(), _root) as Node
	ui.name = "UI"
	for item in [["HUD", HUD], ["PauseMenu", PAUSE], ["EndingScreen", ENDING]]:
		var n := _add(item[1].instantiate(), ui) as Node
		n.name = item[0]
	var layer := _add(CanvasLayer.new(), ui) as CanvasLayer
	layer.name = "MapLayer"
	layer.layer = 50
	var mm := _add(MINIMAP.instantiate(), layer) as Control
	mm.name = "Minimap"
	mm.anchors_preset = Control.PRESET_TOP_RIGHT
	mm.anchor_left = 1.0
	mm.anchor_right = 1.0
	mm.offset_left = -216.0
	mm.offset_top = 64.0
	mm.offset_right = -16.0
	mm.offset_bottom = 160.0
	mm.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mm.set("display_player_location", true)

	var room := _add(ROOMINST.instantiate(), _root) as Node
	room.name = "RoomInstance"
