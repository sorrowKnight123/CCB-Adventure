extends Node
## 一次性工具：把宿舍从 4800x800 压缩到 2560x720（方案A：2格横排）。

const SCENE_PATH := "res://scenes/levels/main.tscn"


func _ready() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		printerr("加载失败")
		get_tree().quit(1)
		return
	var inst := scene.instantiate()

	_set_body(inst, "Ceiling", Vector2(1280, 0), Vector2(2560, 20))
	_set_body(inst, "WallLeft", Vector2(16, 360), Vector2(32, 720))
	_set_body(inst, "WallRight", Vector2(2544, 360), Vector2(32, 720))
	_set_body(inst, "GroundA", Vector2(575, 580), Vector2(1150, 40))
	_set_body(inst, "GroundB", Vector2(1970, 580), Vector2(1180, 40))
	_set_body(inst, "Basement", Vector2(1265, 710), Vector2(220, 40))
	_set_body(inst, "RecoverStep", Vector2(1265, 618), Vector2(80, 16))
	_set_body(inst, "WallPitL", Vector2(1150, 665), Vector2(20, 170))
	_set_body(inst, "WallPitR", Vector2(1380, 665), Vector2(20, 170))
	_set_body(inst, "BedLoft", Vector2(360, 480), Vector2(130, 16))
	_set_body(inst, "S1", Vector2(850, 488), Vector2(150, 16))
	_set_body(inst, "S2", Vector2(930, 408), Vector2(150, 16))
	_set_body(inst, "S3", Vector2(1010, 328), Vector2(150, 16))
	_set_body(inst, "BlockCabinet", Vector2(1000, 430), Vector2(120, 260))
	_set_body(inst, "RangedLedge", Vector2(2200, 468), Vector2(140, 16))
	_set_body(inst, "SheetDesk", Vector2(2400, 560), Vector2(80, 40))
	_set_body(inst, "HighWindowLedge", Vector2(600, 270), Vector2(140, 16))

	_set_pos(inst, "school_start", Vector2(100, 530))
	_set_pos(inst, "school_from_playground", Vector2(160, 530))
	_set_pos(inst, "school_from_forest", Vector2(220, 530))
	_set_pos(inst, "DT_welcome", Vector2(170, 545))
	_set_pos(inst, "DT_jump", Vector2(700, 545))
	_set_pos(inst, "DT_dash", Vector2(1000, 545))
	_set_pos(inst, "DT_combat", Vector2(1900, 545))
	_set_pos(inst, "DT_inventory", Vector2(2300, 545))
	_set_pos(inst, "Player", Vector2(120, 530))
	_set_pos(inst, "Checkpoint_school", Vector2(1900, 530))
	_set_pos(inst, "Enemy1", Vector2(2000, 544))
	_set_pos(inst, "Enemy2", Vector2(2100, 544))
	_set_pos(inst, "RangedEnemy1", Vector2(2200, 444))
	_set_pos(inst, "Clue3", Vector2(2380, 530))
	_set_pos(inst, "Door_playground", Vector2(2480, 540))
	_set_pos(inst, "NoteS1", Vector2(850, 470))
	_set_pos(inst, "NoteRangedLedge", Vector2(2200, 440))
	_set_pos(inst, "NoteHighWindow", Vector2(600, 252))

	# 移除压缩后放不下的阁楼/暗格，保留高窗回访点
	_remove(inst, "LoftPath")
	_remove(inst, "HiddenAlcove")
	_remove(inst, "NoteAlcove")

	var gf := inst.get_node_or_null("GameFlow") as Node
	if gf:
		gf.camera_right = 2560
		gf.camera_top = 0
		gf.camera_bottom = 720

	var packed := PackedScene.new()
	packed.pack(inst)
	var err := ResourceSaver.save(packed, SCENE_PATH)
	print("saved err=", err)
	inst.free()
	get_tree().quit(0)


func _set_body(inst: Node, node_name: String, pos: Vector2, size: Vector2) -> void:
	var n := inst.get_node_or_null(node_name) as Node2D
	if n == null:
		printerr("missing " + node_name)
		return
	n.position = pos
	var cs := n.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs:
		var shape := RectangleShape2D.new()
		shape.size = size
		cs.shape = shape
	var vis := n.get_node_or_null("Visual") as Polygon2D
	if vis:
		vis.polygon = PackedVector2Array([-size.x / 2.0, -size.y / 2.0, size.x / 2.0, -size.y / 2.0, size.x / 2.0, size.y / 2.0, -size.x / 2.0, size.y / 2.0])


func _set_pos(inst: Node, node_name: String, pos: Vector2) -> void:
	var n := inst.get_node_or_null(node_name) as Node2D
	if n:
		n.position = pos
	else:
		printerr("missing " + node_name)


func _remove(inst: Node, node_name: String) -> void:
	var n := inst.get_node_or_null(node_name)
	if n:
		n.queue_free()
