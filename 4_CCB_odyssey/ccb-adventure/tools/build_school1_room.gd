extends Node
## 临时工具：在 school1.tscn 中用 TileMapLayer 布置小图书馆房间。
## 结构：沿用 collisionLayer 已有“楼梯/地板”瓦片，额外加两个平台；
## 前景散落书本使用 FGLayer + Full Asset 2 的装饰瓦片。

const SCENE_PATH := "res://scenes/levels/school1.tscn"


func _ready() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		printerr("加载失败")
		get_tree().quit(1)
		return
	var inst := scene.instantiate()
	var collision_layer := inst.get_node_or_null("collisionLayer") as TileMapLayer
	var fg_layer := inst.get_node_or_null("FGLayer") as TileMapLayer
	if collision_layer == null or fg_layer == null:
		printerr("图层缺失")
		get_tree().quit(1)
		return

	# 1. 读取现有 collisionLayer 的格子作为“瓦片库”（只复制已有视觉）
	var cells := {}
	for c in collision_layer.get_used_cells():
		cells[c] = {
			"source": collision_layer.get_cell_source_id(c),
			"atlas": collision_layer.get_cell_atlas_coords(c),
		}

	# 2. 两个平台：复制现有地板顶部一行，放到右侧不同高度
	_add_copied_row(collision_layer, cells, 0, 5, 20, 15)
	_add_copied_row(collision_layer, cells, 0, 4, 30, 12)

	# 3. 前景散落书本：放在 FGLayer（不参与碰撞）
	var book_tiles := [Vector2i(9, 21), Vector2i(13, 36), Vector2i(15, 34), Vector2i(23, 23)]
	var book_cells := [Vector2i(2, 7), Vector2i(5, 7), Vector2i(8, 7), Vector2i(11, 7)]
	for i in range(book_tiles.size()):
		fg_layer.set_cell(book_cells[i], 1, book_tiles[i])

	var packed := PackedScene.new()
	packed.pack(inst)
	var err := ResourceSaver.save(packed, SCENE_PATH)
	print("saved err=", err)
	inst.free()
	get_tree().quit(0)


func _add_copied_row(layer: TileMapLayer, cells: Dictionary, x0: int, x1: int, offset_x: int, y: int) -> void:
	var count := 0
	for c in cells:
		if c.y == 6 and c.x >= x0 and c.x <= x1:
			var info: Dictionary = cells[c]
			var target := Vector2i(c.x + offset_x, y)
			layer.set_cell(target, info["source"], info["atlas"])
			count += 1
	print("copied row cells=", count, " -> y=", y)
